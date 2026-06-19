import 'server-only'
import { queryAsUser } from './db'

/**
 * Secured data-access layer (SERVER-ONLY).
 *
 * SECURITY MODEL -- read carefully:
 *   The web app connects as the `StudentDataAssessment` service principal, so the warehouse's
 *   caller-scoped RLS views (which filter on CURRENT_USER) return NOTHING to us. Instead we read
 *   the *bridge* views (`vw_BridgeTeacherRosterAll`, ...) which expose every row with the scoping
 *   key (`TeacherEmail`) as a COLUMN -- they bypass RLS BY DESIGN (see `sql/security/
 *   bridge_views.sql`). Row-level scoping is therefore enforced HERE, in code: every function
 *   filters `WHERE LOWER(TeacherEmail) = LOWER(@UPN)` via `queryAsUser`, which always binds the
 *   signed-in UPN. NEVER expose a bridge view to a screen without that predicate, and never add a
 *   bridge view as a client-reachable source. (When we move to user-token / OBO auth, switch these
 *   back to the caller-scoped views and drop the @UPN filter; native RLS takes over.)
 */

export interface TeacherWindow {
  id: string // AssessmentWindowID (kept as string -- BIGINT exceeds JS Number precision)
  name: string
  status: string // Upcoming | Open | ClosesToday | Closed
  scaleSystem: string | null
  applicableCount: number
  enteredCount: number
}

export interface TeacherGroup {
  key: string // GroupKey: 'HR:<homeroom>' or 'SEC:<sectionId>'
  label: string
  grade: string | null
  applicableCount: number
  enteredCount: number
}

const BRIDGE_ROSTER = 'dbo.vw_BridgeTeacherRosterAll'

/** Assessment windows applicable to the signed-in teacher, with per-window progress counts. */
export async function getTeacherWindows(upn: string): Promise<TeacherWindow[]> {
  const rows = await queryAsUser<{
    AssessmentWindowID: string
    WindowName: string
    WindowStatus: string
    ScaleSystem: string | null
    ApplicableStudentCount: number
    EnteredStudentCount: number
  }>(
    upn,
    `SELECT
        AssessmentWindowID,
        WindowName,
        WindowStatus,
        ScaleSystem,
        COUNT(DISTINCT StudentKey) AS ApplicableStudentCount,
        COUNT(DISTINCT CASE WHEN ExistingReadingAssessmentID IS NOT NULL THEN StudentKey END) AS EnteredStudentCount
     FROM ${BRIDGE_ROSTER}
     WHERE LOWER(TeacherEmail) = LOWER(@UPN)
     GROUP BY AssessmentWindowID, WindowName, WindowStatus, ScaleSystem
     ORDER BY WindowName`,
  )
  return rows.map((r) => ({
    id: String(r.AssessmentWindowID),
    name: r.WindowName,
    status: r.WindowStatus,
    scaleSystem: r.ScaleSystem,
    applicableCount: Number(r.ApplicableStudentCount ?? 0),
    enteredCount: Number(r.EnteredStudentCount ?? 0),
  }))
}

/** Groups (homerooms / sections) for one window, scoped to the signed-in teacher. */
export async function getTeacherGroups(upn: string, windowId: string): Promise<TeacherGroup[]> {
  const rows = await queryAsUser<{
    GroupKey: string
    Grade: string | null
    SectionNumber: string | null
    CourseName: string | null
    ApplicableStudentCount: number
    EnteredStudentCount: number
  }>(
    upn,
    `SELECT
        GroupKey,
        MAX(Grade) AS Grade,
        MAX(SectionNumber) AS SectionNumber,
        MAX(CourseName) AS CourseName,
        COUNT(DISTINCT StudentKey) AS ApplicableStudentCount,
        COUNT(DISTINCT CASE WHEN ExistingReadingAssessmentID IS NOT NULL THEN StudentKey END) AS EnteredStudentCount
     FROM ${BRIDGE_ROSTER}
     WHERE LOWER(TeacherEmail) = LOWER(@UPN)
       AND AssessmentWindowID = @WindowID
     GROUP BY GroupKey
     ORDER BY GroupKey`,
    { WindowID: windowId },
  )
  return rows.map((r) => {
    const key = String(r.GroupKey)
    const label = key.startsWith('HR:')
      ? `Homeroom ${key.slice(3)}`
      : [r.SectionNumber, r.CourseName].filter(Boolean).join(' — ') || key
    return {
      key,
      label,
      grade: r.Grade ?? null,
      applicableCount: Number(r.ApplicableStudentCount ?? 0),
      enteredCount: Number(r.EnteredStudentCount ?? 0),
    }
  })
}
