import 'server-only'
import { queryAsUser, query } from './db'

/**
 * Secured data-access layer (SERVER-ONLY).
 *
 * SECURITY MODEL -- read carefully:
 *   The web app connects as the `StudentDataAssessment` service principal, so the warehouse's
 *   caller-scoped RLS views (which filter on CURRENT_USER) return NOTHING to us. Instead we call
 *   the @UPN-parameterized entry-flow procs (`usp_GetUserAssessmentWindows`, `usp_GetTeacherGroups`,
 *   `usp_GetTeacherRoster`) -- they run the SAME teacher / school-admin / regional-analyst role
 *   branches as the caller-scoped views, but take the caller as @UPN. Scoping (incl. an analyst's
 *   multi-school reach) is enforced in SQL INSIDE the procs; `queryAsUser` always binds the
 *   signed-in UPN, which the proc trusts, and the procs are EXECUTE-granted to the SP only. These
 *   replace the earlier bridge-view reads (which only covered the teacher branch -- the bug that
 *   dropped admin/analyst access). When we move to user-token/OBO auth, the caller-scoped views can
 *   be used directly and the @UPN arg dropped.
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

/** Assessment windows applicable to the signed-in user (any role), with per-window progress counts. */
export async function getTeacherWindows(upn: string): Promise<TeacherWindow[]> {
  const rows = await queryAsUser<{
    AssessmentWindowID: string
    WindowName: string
    WindowStatus: string
    ScaleSystem: string | null
    ApplicableStudentCount: number
    EnteredStudentCount: number
  }>(upn, 'EXEC dbo.usp_GetUserAssessmentWindows @UPN = @UPN')
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
    GroupLabel: string | null
    Grade: string | null
    ApplicableStudentCount: number
    EnteredStudentCount: number
  }>(
    upn,
    'EXEC dbo.usp_GetTeacherGroups @UPN = @UPN, @AssessmentWindowID = @WindowID',
    { WindowID: windowId },
  )
  return rows.map((r) => ({
    key: String(r.GroupKey),
    label: r.GroupLabel ?? String(r.GroupKey),
    grade: r.Grade ?? null,
    applicableCount: Number(r.ApplicableStudentCount ?? 0),
    enteredCount: Number(r.EnteredStudentCount ?? 0),
  }))
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
    'EXEC dbo.usp_GetTeacherRoster @UPN = @UPN, @AssessmentWindowID = @WindowID, @GroupKey = @GroupKey',
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
    `SELECT CAST(ReadingScaleID AS VARCHAR(20)) AS ReadingScaleID, LevelCode, LevelOrder
     FROM dbo.DimReadingScale
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
