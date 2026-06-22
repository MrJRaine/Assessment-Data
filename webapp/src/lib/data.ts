import 'server-only'
import { queryAsUser, query } from './db'

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

export interface RosterStudent {
  studentKey: string
  studentNumber: string // provincial 10-digit (string for display; within JS-safe range)
  firstName: string
  lastName: string
  grade: string | null
  scaleSystem: string | null // window's scale (e.g. EN_Reading) — drives the level dropdown
  currentLevel: string | null // existing LevelCode for this window, or null if not yet entered
  currentDelta: number | null
  assessmentDate: string | null
  expectedMin: string | null
  expectedMax: string | null
  ippStatus: boolean | null // IsIPP (Reading): true/false/null(=unresolved)
  ippNeedsConfirmation: boolean
}

/** One window's roster for the signed-in teacher + group, with each student's existing entry. */
export async function getTeacherRoster(
  upn: string,
  windowId: string,
  groupKey: string,
): Promise<RosterStudent[]> {
  const rows = await queryAsUser<{
    StudentKey: string
    StudentNumber: number | string
    FirstName: string
    LastName: string
    Grade: string | null
    ScaleSystem: string | null
    ExistingScaleValue: string | null
    ExistingDelta: number | null
    ExistingAssessmentDate: Date | string | null
    ExpectedMinLevel: string | null
    ExpectedMaxLevel: string | null
    ReadingIPPStatus: boolean | null
    ReadingIPPNeedsConfirmation: boolean | null
  }>(
    upn,
    // DISTINCT collapses the view's per-section fan-out: a PP-9 homeroom student whose teacher
    // takes them in >1 section yields multiple view rows differing only by SectionNumber/
    // CourseName (not selected here), so the projected rows are identical -> one row per student.
    `SELECT DISTINCT
        StudentKey, StudentNumber, FirstName, LastName, Grade, ScaleSystem,
        ExistingScaleValue, ExistingDelta, ExistingAssessmentDate,
        ExpectedMinLevel, ExpectedMaxLevel, ReadingIPPStatus, ReadingIPPNeedsConfirmation
     FROM ${BRIDGE_ROSTER}
     WHERE LOWER(TeacherEmail) = LOWER(@UPN)
       AND AssessmentWindowID = @WindowID
       AND GroupKey = @GroupKey
     ORDER BY LastName, FirstName`,
    { WindowID: windowId, GroupKey: groupKey },
  )
  return rows.map((r) => ({
    studentKey: String(r.StudentKey),
    studentNumber: String(r.StudentNumber),
    firstName: r.FirstName,
    lastName: r.LastName,
    grade: r.Grade ?? null,
    scaleSystem: r.ScaleSystem ?? null,
    currentLevel: r.ExistingScaleValue ?? null,
    currentDelta: r.ExistingDelta ?? null,
    assessmentDate:
      r.ExistingAssessmentDate instanceof Date
        ? r.ExistingAssessmentDate.toISOString().slice(0, 10)
        : (r.ExistingAssessmentDate ?? null),
    expectedMin: r.ExpectedMinLevel ?? null,
    expectedMax: r.ExpectedMaxLevel ?? null,
    ippStatus: r.ReadingIPPStatus ?? null,
    ippNeedsConfirmation: Boolean(r.ReadingIPPNeedsConfirmation),
  }))
}

export interface ScaleLevel {
  readingScaleId: string
  levelCode: string
  levelOrder: number
}

/**
 * Valid reading levels for a scale system (e.g. EN_Reading), ordered. Drives the roster New-Level
 * dropdown. Reference data (not user-scoped), so it reads the bridge scale view directly.
 */
export async function getScaleLevels(scaleSystem: string): Promise<ScaleLevel[]> {
  const rows = await query<{ ReadingScaleID: string; LevelCode: string; LevelOrder: number }>(
    `SELECT ReadingScaleID, LevelCode, LevelOrder
     FROM dbo.vw_BridgeScaleLevels
     WHERE ScaleSystem = @ScaleSystem AND ActiveFlag = 1
     ORDER BY LevelOrder`,
    { ScaleSystem: scaleSystem },
  )
  return rows.map((r) => ({
    readingScaleId: String(r.ReadingScaleID),
    levelCode: r.LevelCode,
    levelOrder: Number(r.LevelOrder),
  }))
}
