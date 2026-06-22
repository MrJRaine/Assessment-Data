import 'server-only'
import { queryAsUser, query } from './db'

/**
 * Secured data-access layer (SERVER-ONLY).
 *
 * SECURITY MODEL -- read carefully:
 *   The web app connects as the `StudentDataAssessment` service principal, so the warehouse's
 *   caller-scoped RLS views (which filter on CURRENT_USER) return NOTHING to us. Instead we QUERY
 *   the @UPN-parameterized inline TVFs (`tvf_UserAssessmentWindows`, `tvf_TeacherGroups`,
 *   `tvf_TeacherRoster`) -- `SELECT ... FROM dbo.tvf_X(@UPN, ...)`. They run the SAME teacher /
 *   school-admin / regional-analyst role branches as the caller-scoped views but take the caller as
 *   @UPN. Scoping (incl. an analyst's multi-school reach) is enforced in SQL INSIDE the TVF;
 *   `queryAsUser` always binds the signed-in UPN, which the TVF trusts, and the TVFs are
 *   SELECT-granted to the SP only. These replace the earlier bridge-view reads (which only covered
 *   the teacher branch -- the bug that dropped admin/analyst access). Reads are TVFs (queryable);
 *   writes stay stored procs (they INSERT/UPDATE + audit). When we move to user-token/OBO auth, the
 *   caller-scoped views can be used directly and the @UPN arg dropped.
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
  }>(upn, 'SELECT * FROM dbo.tvf_UserAssessmentWindows(@UPN) ORDER BY WindowName')
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
    'SELECT * FROM dbo.tvf_TeacherGroups(@UPN, @WindowID) ORDER BY GroupKey',
    { WindowID: windowId },
  )
  return rows.map((r) => {
    const key = String(r.GroupKey)
    // Build homeroom labels in the app (reliable spacing); use the TVF label for section groups.
    const label = key.startsWith('HR:') ? `Homeroom ${key.slice(3)}` : (r.GroupLabel ?? key)
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
  programFamily: string | null // IPP row's ProgramFamily (window-over-student) — passed to the IPP proc
  currentLevel: string | null // existing LevelCode for this window, or null if not yet entered
  currentDelta: number | null
  assessmentDate: string | null
  expectedMin: string | null
  expectedMax: string | null
  ippStatus: boolean | null // IsIPP (Reading): true/false/null(=unresolved)
  ippNeedsConfirmation: boolean
  achievementLevel: string | null // DimAchievementLevel code/name for the current delta
  achievementHexColor: string | null // strong colour (text/border)
  achievementHexColorTint: string | null // light colour (cell background)
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
    IPPProgramFamily: string | null
    AchievementLevel: string | null
    AchievementLevelName: string | null
    AchievementHexColor: string | null
    AchievementHexColorTint: string | null
  }>(
    upn,
    'SELECT * FROM dbo.tvf_TeacherRoster(@UPN, @WindowID, @GroupKey) ORDER BY LastName, FirstName',
    { WindowID: windowId, GroupKey: groupKey },
  )
  return rows.map((r) => ({
    studentKey: String(r.StudentKey),
    studentNumber: String(r.StudentNumber),
    firstName: r.FirstName,
    lastName: r.LastName,
    grade: r.Grade ?? null,
    scaleSystem: r.ScaleSystem ?? null,
    programFamily: r.IPPProgramFamily ?? null,
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
    achievementLevel: r.AchievementLevelName ?? r.AchievementLevel ?? null,
    achievementHexColor: r.AchievementHexColor ?? null,
    achievementHexColorTint: r.AchievementHexColorTint ?? null,
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

export interface CohortStudent {
  studentKey: string
  studentNumber: string
  fullName: string
  firstName: string
  lastName: string
  grade: string | null
  gradeOrder: number | null
  schoolId: string | null
  schoolName: string | null
  schoolAbbreviation: string | null
  programFamily: string | null
  gender: string | null
  selfIDAfrican: boolean | null
  selfIDIndigenous: boolean | null
  homeroom: string | null
  ippStatusReading: string // 'N/A' | 'Unresolved' | 'IPP' | 'Not IPP'
  chartEligible: boolean // excluded from aggregate charts when IPP/unresolved
  // Most-recent (lifetime) reading evidence — null when never assessed
  mostRecentDate: string | null
  mostRecentWindowName: string | null
  mostRecentSchoolYear: string | null
  mostRecentLevelCode: string | null
  mostRecentLevelOrder: number | null
  mostRecentDelta: number | null
  achievementCode: number | null
  achievementName: string | null
  achievementHexColor: string | null
  achievementHexColorTint: string | null
}

function toBool(v: unknown): boolean | null {
  if (v === true || v === 1) return true
  if (v === false || v === 0) return false
  return null
}

function toDateStr(v: Date | string | null | undefined): string | null {
  if (v == null) return null
  return v instanceof Date ? v.toISOString().slice(0, 10) : v
}

/** Student cohort in the signed-in user's scope (role-branched in SQL), with most-recent reading. */
export async function getStudentCohort(upn: string): Promise<CohortStudent[]> {
  const rows = await queryAsUser<Record<string, unknown>>(
    upn,
    'SELECT * FROM dbo.tvf_StudentCohort(@UPN) ORDER BY LastName, FirstName',
  )
  return rows.map((r) => ({
    studentKey: String(r.StudentKey),
    studentNumber: String(r.StudentNumber),
    fullName: String(r.FullName),
    firstName: String(r.FirstName),
    lastName: String(r.LastName),
    grade: (r.Grade as string) ?? null,
    gradeOrder: r.GradeOrder == null ? null : Number(r.GradeOrder),
    schoolId: (r.SchoolID as string) ?? null,
    schoolName: (r.SchoolName as string) ?? null,
    schoolAbbreviation: (r.SchoolAbbreviation as string) ?? null,
    programFamily: (r.ProgramFamily as string) ?? null,
    gender: (r.Gender as string) ?? null,
    selfIDAfrican: toBool(r.SelfIDAfrican),
    selfIDIndigenous: toBool(r.SelfIDIndigenous),
    homeroom: (r.Homeroom as string) ?? null,
    ippStatusReading: (r.IPPStatus_Reading as string) ?? 'N/A',
    chartEligible: toBool(r.IsChartEligibleReading) === true,
    mostRecentDate: toDateStr(r.MostRecentAssessmentDate as Date | string | null),
    mostRecentWindowName: (r.MostRecentWindowName as string) ?? null,
    mostRecentSchoolYear: (r.MostRecentSchoolYear as string) ?? null,
    mostRecentLevelCode: (r.MostRecentLevelCode as string) ?? null,
    mostRecentLevelOrder: r.MostRecentLevelOrder == null ? null : Number(r.MostRecentLevelOrder),
    mostRecentDelta: r.MostRecentReadingDelta == null ? null : Number(r.MostRecentReadingDelta),
    achievementCode: r.MostRecentAchievementLevelCode == null ? null : Number(r.MostRecentAchievementLevelCode),
    achievementName: (r.MostRecentAchievementLevelName as string) ?? null,
    achievementHexColor: (r.MostRecentAchievementHexColor as string) ?? null,
    achievementHexColorTint: (r.MostRecentAchievementHexColorTint as string) ?? null,
  }))
}

export interface StudentNavItem {
  studentKey: string
  fullName: string
  grade: string | null
  programFamily: string | null
  schoolLabel: string | null
  homeroom: string | null
  ippStatusReading: string
}

/**
 * Lightweight ordered roster for the detail screen's prev/next navigation: keys + the meta-strip
 * fields only, NO per-student history. Fetched ONCE on detail load so paging is client-side
 * (the heavy history is fetched per student + prefetched for neighbours). Same ordering as the
 * cohort table so "Student X of Y" lines up.
 */
export async function getStudentNavList(upn: string): Promise<StudentNavItem[]> {
  const rows = await queryAsUser<{
    StudentKey: string
    FullName: string
    Grade: string | null
    ProgramFamily: string | null
    SchoolLabel: string | null
    Homeroom: string | null
    IPPStatus_Reading: string | null
  }>(
    upn,
    `SELECT StudentKey, FullName, Grade, ProgramFamily,
            COALESCE(SchoolAbbreviation, SchoolName, SchoolID) AS SchoolLabel,
            Homeroom, IPPStatus_Reading
     FROM dbo.tvf_StudentCohort(@UPN)
     ORDER BY LastName, FirstName`,
  )
  return rows.map((r) => ({
    studentKey: String(r.StudentKey),
    fullName: String(r.FullName),
    grade: r.Grade ?? null,
    programFamily: r.ProgramFamily ?? null,
    schoolLabel: r.SchoolLabel ?? null,
    homeroom: r.Homeroom ?? null,
    ippStatusReading: r.IPPStatus_Reading ?? 'N/A',
  }))
}

export interface HistoryRow {
  readingAssessmentId: string
  windowName: string
  windowSchoolYear: string | null
  assessmentDate: string | null
  levelCode: string | null
  levelOrder: number | null
  delta: number | null
  achievementCode: number | null
  achievementName: string | null
  achievementHexColor: string | null
  achievementHexColorTint: string | null
}

/** One student's reading-assessment history (scoped by @UPN), newest sorting done by the caller. */
export async function getStudentHistory(upn: string, studentKey: string): Promise<HistoryRow[]> {
  const rows = await queryAsUser<Record<string, unknown>>(
    upn,
    'SELECT * FROM dbo.tvf_StudentAssessmentHistory(@UPN, @StudentKey) ORDER BY AssessmentDate',
    { StudentKey: studentKey },
  )
  return rows.map((r) => ({
    readingAssessmentId: String(r.ReadingAssessmentID),
    windowName: String(r.WindowName),
    windowSchoolYear: (r.WindowSchoolYear as string) ?? null,
    assessmentDate: toDateStr(r.AssessmentDate as Date | string | null),
    levelCode: (r.LevelCode as string) ?? null,
    levelOrder: r.LevelOrder == null ? null : Number(r.LevelOrder),
    delta: r.ReadingDelta == null ? null : Number(r.ReadingDelta),
    achievementCode: r.AchievementLevelCode == null ? null : Number(r.AchievementLevelCode),
    achievementName: (r.AchievementLevelName as string) ?? null,
    achievementHexColor: (r.AchievementHexColor as string) ?? null,
    achievementHexColorTint: (r.AchievementHexColorTint as string) ?? null,
  }))
}

export interface IPPRow {
  studentKey: string
  studentNumber: string
  firstName: string
  lastName: string
  grade: string | null
  homeroom: string | null
  subject: string // 'Reading' (Writing/Math later)
  programFamily: string // IPP row's ProgramFamily — passed verbatim to the proc
  isIPP: boolean | null // null = needs confirmation
}

/**
 * Reading-IPP rows in the signed-in user's scope, for the bulk IPP-management screen (/ipp).
 * Reading only for the pilot (mirrors scrIPP's Subject='Reading' filter); Writing/Math join later.
 */
export async function getStudentIPPList(upn: string): Promise<IPPRow[]> {
  const rows = await queryAsUser<{
    StudentKey: string
    StudentNumber: number | string
    FirstName: string
    LastName: string
    Grade: string | null
    Homeroom: string | null
    Subject: string
    IPPProgramFamily: string
    IsIPP: boolean | number | null
  }>(
    upn,
    `SELECT * FROM dbo.tvf_StudentIPP(@UPN)
     WHERE Subject = 'Reading'
     ORDER BY LastName, FirstName, IPPProgramFamily`,
  )
  return rows.map((r) => ({
    studentKey: String(r.StudentKey),
    studentNumber: String(r.StudentNumber),
    firstName: r.FirstName,
    lastName: r.LastName,
    grade: r.Grade ?? null,
    homeroom: r.Homeroom ?? null,
    subject: r.Subject,
    programFamily: r.IPPProgramFamily,
    isIPP: toBool(r.IsIPP),
  }))
}

export interface AchievementBand {
  code: string
  name: string
  lowerBound: number | null
  lowerOp: string | null // '>=' | '>' | '='
  upperBound: number | null
  upperOp: string | null // '<=' | '<' | '='
  hexColor: string
  hexColorTint: string
}

/**
 * Achievement bands (delta -> colour). Reference data so the roster grid can colour rows LIVE as
 * the level dropdown changes (compute delta client-side, then match a band), mirroring the
 * server-side bounds logic in usp_UpsertReadingAssessment / tvf_TeacherRoster.
 */
export async function getAchievementLevels(): Promise<AchievementBand[]> {
  const rows = await query<{
    AchievementLevelCode: string
    AchievementLevelName: string
    LowerBound: number | string | null
    LowerOp: string | null
    UpperBound: number | string | null
    UpperOp: string | null
    HexColor: string
    HexColorTint: string
  }>(
    `SELECT AchievementLevelCode, AchievementLevelName, LowerBound, LowerOp, UpperBound, UpperOp, HexColor, HexColorTint
     FROM dbo.DimAchievementLevel
     WHERE ActiveFlag = 1`,
  )
  return rows.map((r) => ({
    code: r.AchievementLevelCode,
    name: r.AchievementLevelName,
    lowerBound: r.LowerBound == null ? null : Number(r.LowerBound),
    lowerOp: r.LowerOp ?? null,
    upperBound: r.UpperBound == null ? null : Number(r.UpperBound),
    upperOp: r.UpperOp ?? null,
    hexColor: r.HexColor,
    hexColorTint: r.HexColorTint,
  }))
}
