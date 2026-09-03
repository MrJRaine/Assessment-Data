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
  assessmentType: string // 'Reading' | 'Writing' | 'Math' -- groups the window-select screen
  status: string // Upcoming | Open | ClosesToday | Closed
  scaleSystem: string | null
  startDate: string // 'YYYY-MM-DD' (window opens on the 1st of its month)
  endDate: string // 'YYYY-MM-DD' (window closes on the last day of its month)
  applicableCount: number
  enteredCount: number
}

// DATE columns come back from tedious as a JS Date (UTC midnight) or a string; normalize to 'YYYY-MM-DD'.
function toYMD(v: unknown): string {
  if (v instanceof Date) return v.toISOString().slice(0, 10)
  return String(v).slice(0, 10)
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
    AssessmentType: string
    WindowStatus: string
    ScaleSystem: string | null
    StartDate: unknown
    EndDate: unknown
    ApplicableStudentCount: number
    EnteredStudentCount: number
  }>(upn, 'SELECT * FROM dbo.tvf_UserAssessmentWindows(@UPN) ORDER BY StartDate, WindowName')
  return rows.map((r) => ({
    id: String(r.AssessmentWindowID),
    name: r.WindowName,
    assessmentType: r.AssessmentType,
    status: r.WindowStatus,
    scaleSystem: r.ScaleSystem,
    startDate: toYMD(r.StartDate),
    endDate: toYMD(r.EndDate),
    applicableCount: Number(r.ApplicableStudentCount ?? 0),
    enteredCount: Number(r.EnteredStudentCount ?? 0),
  }))
}

export interface ShortCycleRow {
  subject: string // 'Reading' | 'Writing' | 'Math'
  id: string // that subject's AssessmentWindowID (string -- BIGINT precision)
  active: boolean
}

export interface ShortCycle {
  groupId: string | null // CycleGroupID; null for legacy single windows (each its own cycle)
  key: string // stable grouping key for React (groupId ?? 'win:<id>')
  name: string
  subjects: string[] // subjects the cycle currently covers (active rows)
  schoolYear: string
  status: string // Upcoming | Open | ClosesToday | Closed (rows share dates -> same status)
  startDate: string // 'YYYY-MM-DD'
  endDate: string
  minGrade: string
  maxGrade: string
  benchmarkMonth: number | null // 1-12, from the reading row; null = dominant-month fallback
  active: boolean // any row active
  rows: ShortCycleRow[] // every per-subject row (for edit reconciliation)
}

/**
 * All Short Cycles of Response, grouped for the admin screen. A cycle is one or more per-subject
 * DimAssessmentWindow rows sharing a CycleGroupID (multi-subject); legacy rows with no group id are
 * treated as their own single-subject cycle. Config, not per-user PII, so a plain SP query is fine
 * (mirrors getWindowEndDate). Status is date-derived in Atlantic time to match the entry gate.
 */
export async function getShortCycles(): Promise<ShortCycle[]> {
  const rows = await query<{
    AssessmentWindowID: string
    WindowName: string
    AssessmentType: string
    SchoolYear: string
    StartDate: unknown
    EndDate: unknown
    MinGrade: string
    MaxGrade: string
    BenchmarkMonth: number | null
    CycleGroupID: string | null
    ActiveFlag: boolean
    Status: string
  }>(`
    SELECT
      CAST(AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
      WindowName, AssessmentType, SchoolYear, StartDate, EndDate,
      MinGrade, MaxGrade, BenchmarkMonth, CycleGroupID, ActiveFlag,
      CASE
        WHEN CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) < StartDate THEN 'Upcoming'
        WHEN CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) > EndDate   THEN 'Closed'
        WHEN CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) = EndDate   THEN 'ClosesToday'
        ELSE 'Open'
      END AS Status
    FROM DimAssessmentWindow
    ORDER BY StartDate DESC, WindowName, AssessmentType`)

  // Group per-subject rows into cycles by CycleGroupID (ungrouped rows stand alone).
  const groups = new Map<string, typeof rows>()
  for (const r of rows) {
    const key = r.CycleGroupID ?? `win:${r.AssessmentWindowID}`
    const g = groups.get(key)
    if (g) g.push(r)
    else groups.set(key, [r] as typeof rows)
  }

  const cycles: ShortCycle[] = []
  for (const [key, grp] of groups) {
    const first = grp[0]
    const activeRows = grp.filter((r) => r.ActiveFlag)
    const subjectRows = activeRows.length ? activeRows : grp
    const subjects = [...new Set(subjectRows.map((r) => r.AssessmentType))]
    const readingRow = grp.find((r) => r.AssessmentType === 'Reading' && r.ActiveFlag)
      ?? grp.find((r) => r.AssessmentType === 'Reading')
    cycles.push({
      groupId: first.CycleGroupID ?? null,
      key,
      name: first.WindowName,
      subjects,
      schoolYear: first.SchoolYear,
      status: first.Status,
      startDate: toYMD(first.StartDate),
      endDate: toYMD(first.EndDate),
      minGrade: first.MinGrade,
      maxGrade: first.MaxGrade,
      benchmarkMonth: readingRow?.BenchmarkMonth == null ? null : Number(readingRow.BenchmarkMonth),
      active: grp.some((r) => r.ActiveFlag),
      rows: grp.map((r) => ({ subject: r.AssessmentType, id: String(r.AssessmentWindowID), active: Boolean(r.ActiveFlag) })),
    })
  }
  return cycles.sort((a, b) => b.startDate.localeCompare(a.startDate) || a.name.localeCompare(b.name))
}

/**
 * The window's EndDate ('YYYY-MM-DD'), or null if not found. Used by the entry save path to date a
 * LATE entry into a closed window at the window's own month-end (the proc's 51017 gate caps the
 * assessment date at MIN(today, EndDate), so a plain "today" would be rejected for a past window).
 * Window dates are reference metadata (not per-user PII), so a plain query is fine.
 */
export async function getWindowEndDate(windowId: string): Promise<string | null> {
  const rows = await query<{ EndDate: unknown }>(
    'SELECT EndDate FROM DimAssessmentWindow WHERE AssessmentWindowID = CAST(@WID AS BIGINT)',
    { WID: windowId },
  )
  return rows.length ? toYMD(rows[0].EndDate) : null
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

/** The window's AssessmentType ('Reading' | 'Writing' | 'Math'), used to branch the entry grid. */
export async function getWindowAssessmentType(windowId: string): Promise<string | null> {
  const rows = await query<{ AssessmentType: string }>(
    'SELECT AssessmentType FROM DimAssessmentWindow WHERE AssessmentWindowID = CAST(@WID AS BIGINT)',
    { WID: windowId },
  )
  return rows.length ? rows[0].AssessmentType : null
}

export interface WritingRosterStudent {
  studentKey: string
  studentNumber: string
  firstName: string
  lastName: string
  grade: string | null
  programFamily: string | null // IPP row's ProgramFamily (window-over-student) — passed to the IPP proc
  ideas: number | null // existing 1–4 trait scores for this window (latest entry), or null if none
  organization: number | null
  language: number | null
  conventions: number | null
  avgScore: number | null
  assessmentDate: string | null
  ippStatus: boolean | null // IsIPP (Writing): true/false/null(=unresolved)
  ippNeedsConfirmation: boolean
  achievementLevel: string | null // band name for the average
  achievementHexColor: string | null
  achievementHexColorTint: string | null
}

/** One Writing window's roster for the signed-in teacher + group, with each student's latest 4-trait entry. */
export async function getTeacherRosterWriting(
  upn: string,
  windowId: string,
  groupKey: string,
): Promise<WritingRosterStudent[]> {
  const rows = await queryAsUser<{
    StudentKey: string
    StudentNumber: number | string
    FirstName: string
    LastName: string
    Grade: string | null
    ExistingIdeasScore: number | null
    ExistingOrganizationScore: number | null
    ExistingLanguageScore: number | null
    ExistingConventionsScore: number | null
    ExistingAvgScore: number | null
    ExistingAssessmentDate: Date | string | null
    WritingIPPStatus: boolean | null
    WritingIPPNeedsConfirmation: boolean | null
    IPPProgramFamily: string | null
    AchievementLevelName: string | null
    AchievementHexColor: string | null
    AchievementHexColorTint: string | null
  }>(
    upn,
    'SELECT * FROM dbo.tvf_TeacherRosterWriting(@UPN, @WindowID, @GroupKey) ORDER BY LastName, FirstName',
    { WindowID: windowId, GroupKey: groupKey },
  )
  return rows.map((r) => ({
    studentKey: String(r.StudentKey),
    studentNumber: String(r.StudentNumber),
    firstName: r.FirstName,
    lastName: r.LastName,
    grade: r.Grade ?? null,
    programFamily: r.IPPProgramFamily ?? null,
    ideas: r.ExistingIdeasScore ?? null,
    organization: r.ExistingOrganizationScore ?? null,
    language: r.ExistingLanguageScore ?? null,
    conventions: r.ExistingConventionsScore ?? null,
    avgScore: r.ExistingAvgScore != null ? Number(r.ExistingAvgScore) : null,
    assessmentDate:
      r.ExistingAssessmentDate instanceof Date
        ? r.ExistingAssessmentDate.toISOString().slice(0, 10)
        : (r.ExistingAssessmentDate ?? null),
    ippStatus: r.WritingIPPStatus ?? null,
    ippNeedsConfirmation: Boolean(r.WritingIPPNeedsConfirmation),
    achievementLevel: r.AchievementLevelName ?? null,
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

/**
 * The signed-in user's DimStaff AccessLevel ('RegionalAnalyst' | 'Administrator' |
 * 'SpecialistTeacher' | null=Teacher), or null if not in DimStaff. Used to gate analyst-only
 * actions (e.g. ingest upload/trigger) server-side, mirroring the proc role checks.
 */
export async function getCallerAccessLevel(upn: string): Promise<string | null> {
  const rows = await query<{ AccessLevel: string | null }>(
    `SELECT TOP 1 AccessLevel FROM dbo.DimStaff WHERE LOWER(Email) = LOWER(@UPN) AND IsCurrent = 1`,
    { UPN: upn },
  )
  return rows.length ? rows[0].AccessLevel ?? null : null
}

export interface CallerCapabilities {
  isSysAdmin: boolean // super-user: implies all capabilities
  canManageCycles: boolean // /cycles admin
  canRunIngest: boolean // /ingest admin
}

/**
 * App-level admin capabilities for the signed-in user, from the curated StaffAppAccess allowlist
 * (one column per capability, matched case-insensitively by email). Narrower than the analyst role:
 * a staff email with no row here has NO admin capabilities. IsSysAdmin implies every capability.
 * Gates /cycles and /ingest (their pages, server actions, nav items, and home cards).
 */
export async function getCallerCapabilities(upn: string): Promise<CallerCapabilities> {
  const rows = await query<{ IsSysAdmin: boolean; CanManageCycles: boolean; CanRunIngest: boolean }>(
    `SELECT TOP 1 IsSysAdmin, CanManageCycles, CanRunIngest FROM dbo.StaffAppAccess WHERE LOWER(Email) = LOWER(@UPN)`,
    { UPN: upn },
  )
  const r = rows[0]
  const sysAdmin = Boolean(r?.IsSysAdmin)
  return {
    isSysAdmin: sysAdmin,
    canManageCycles: sysAdmin || Boolean(r?.CanManageCycles),
    canRunIngest: sysAdmin || Boolean(r?.CanRunIngest),
  }
}

export interface ImpersonationTarget {
  upn: string
  fullName: string
  accessLevel: string | null // 'RegionalAnalyst' | 'Administrator' | 'SpecialistTeacher' | null
  sections: number // count of current sections they teach (0 = privileged staff with no roster)
}

/**
 * DEV-ONLY: list synthetic staff a developer can impersonate for making how-to docs.
 * Returns teachers who have a current roster (>=1 current section) PLUS any privileged staff
 * (non-null AccessLevel), teachers first, then alphabetical. Reads synthetic dev data via the
 * unscoped SP `query` (no PII concern -- dev warehouse only). The CALLER must gate this to dev
 * mode; it is only ever rendered by the dev impersonation bar.
 */
export async function getImpersonationTargets(): Promise<ImpersonationTarget[]> {
  const rows = await query<{
    Email: string
    FirstName: string | null
    LastName: string | null
    AccessLevel: string | null
    Sections: number
  }>(
    `SELECT s.Email, s.FirstName, s.LastName, s.AccessLevel,
            COUNT(DISTINCT sec.SectionKey) AS Sections
     FROM dbo.DimStaff s
     LEFT JOIN dbo.DimSection sec
            ON sec.TeacherStaffKey = s.StaffKey
           AND sec.IsCurrent = 1
     WHERE s.IsCurrent = 1
       AND s.ActiveFlag = 1
       AND NULLIF(LTRIM(RTRIM(s.Email)), '') IS NOT NULL
     GROUP BY s.Email, s.FirstName, s.LastName, s.AccessLevel
     HAVING COUNT(DISTINCT sec.SectionKey) > 0 OR s.AccessLevel IS NOT NULL
     ORDER BY CASE WHEN COUNT(DISTINCT sec.SectionKey) > 0 THEN 0 ELSE 1 END,
              s.LastName, s.FirstName`,
  )
  return rows.map((r) => ({
    upn: r.Email,
    fullName: [r.FirstName, r.LastName].filter(Boolean).join(' ').trim() || r.Email,
    accessLevel: r.AccessLevel ?? null,
    sections: Number(r.Sections ?? 0),
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

/**
 * Writing cohort in the same CohortStudent shape so CohortView renders it unchanged: the 4-trait
 * average fills the "Level" slot (shown as a 2-dec score) and the writing band fills the achievement
 * fields. ippStatusReading carries the WRITING IPP status here (the field is reused for the table's
 * IPP display); reading-only fields (delta, level order) are null.
 */
export async function getStudentCohortWriting(upn: string): Promise<CohortStudent[]> {
  const rows = await queryAsUser<Record<string, unknown>>(
    upn,
    'SELECT * FROM dbo.tvf_StudentCohortWriting(@UPN) ORDER BY LastName, FirstName',
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
    ippStatusReading: (r.IPPStatus_Writing as string) ?? 'N/A',
    chartEligible: toBool(r.IsChartEligibleWriting) === true,
    mostRecentDate: toDateStr(r.MostRecentAssessmentDate as Date | string | null),
    mostRecentWindowName: (r.MostRecentWindowName as string) ?? null,
    mostRecentSchoolYear: (r.MostRecentSchoolYear as string) ?? null,
    mostRecentLevelCode: r.MostRecentAvgScore == null ? null : Number(r.MostRecentAvgScore).toFixed(2),
    mostRecentLevelOrder: null,
    mostRecentDelta: null,
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
  ippStatus: string // IPP status for the SUBJECT the nav was loaded for (Reading or Writing)
}

/**
 * Lightweight ordered roster for the detail screen's prev/next navigation: keys + the meta-strip
 * fields only, NO per-student history. Fetched ONCE on detail load so paging is client-side
 * (the heavy history is fetched per student + prefetched for neighbours). Same ordering as the
 * cohort table so "Student X of Y" lines up.
 */
export async function getStudentNavList(upn: string, subject: 'Reading' | 'Writing' = 'Reading'): Promise<StudentNavItem[]> {
  // subject is a fixed enum (never user input), so interpolating the TVF + IPP column is injection-safe.
  const tvf = subject === 'Writing' ? 'tvf_StudentCohortWriting' : 'tvf_StudentCohort'
  const ippCol = subject === 'Writing' ? 'IPPStatus_Writing' : 'IPPStatus_Reading'
  const rows = await queryAsUser<Record<string, unknown>>(
    upn,
    `SELECT StudentKey, FullName, Grade, ProgramFamily,
            COALESCE(SchoolAbbreviation, SchoolName, SchoolID) AS SchoolLabel,
            Homeroom, ${ippCol} AS IPPStatus
     FROM dbo.${tvf}(@UPN)
     ORDER BY LastName, FirstName`,
  )
  return rows.map((r) => ({
    studentKey: String(r.StudentKey),
    fullName: String(r.FullName),
    grade: (r.Grade as string) ?? null,
    programFamily: (r.ProgramFamily as string) ?? null,
    schoolLabel: (r.SchoolLabel as string) ?? null,
    homeroom: (r.Homeroom as string) ?? null,
    ippStatus: (r.IPPStatus as string) ?? 'N/A',
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
  // Reject a malformed surrogate key before it reaches SQL (the TVF CASTs it to BIGINT). RLS in
  // the TVF already scopes results; this just turns a garbage key into a clean empty result.
  if (!/^\d{1,20}$/.test(studentKey)) return []
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

export interface WritingHistoryRow {
  writingAssessmentId: string
  windowName: string
  windowSchoolYear: string | null
  assessmentDate: string | null
  ideas: number | null
  organization: number | null
  language: number | null
  conventions: number | null
  avgScore: number | null
  achievementName: string | null
  achievementHexColor: string | null
  achievementHexColorTint: string | null
}

/** One student's writing-assessment history (per-entry 4 traits + average + band), scoped by @UPN. */
export async function getStudentHistoryWriting(upn: string, studentKey: string): Promise<WritingHistoryRow[]> {
  if (!/^\d{1,20}$/.test(studentKey)) return []
  const rows = await queryAsUser<Record<string, unknown>>(
    upn,
    'SELECT * FROM dbo.tvf_StudentAssessmentHistoryWriting(@UPN, @StudentKey) ORDER BY AssessmentDate',
    { StudentKey: studentKey },
  )
  return rows.map((r) => ({
    writingAssessmentId: String(r.WritingAssessmentID),
    windowName: String(r.WindowName),
    windowSchoolYear: (r.WindowSchoolYear as string) ?? null,
    assessmentDate: toDateStr(r.AssessmentDate as Date | string | null),
    ideas: r.IdeasScore == null ? null : Number(r.IdeasScore),
    organization: r.OrganizationScore == null ? null : Number(r.OrganizationScore),
    language: r.LanguageScore == null ? null : Number(r.LanguageScore),
    conventions: r.ConventionsScore == null ? null : Number(r.ConventionsScore),
    avgScore: r.AvgScore == null ? null : Number(r.AvgScore),
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

// ---------------------------------------------------------------------------
// Math roster (P-6 Math). One row per (student x applicable task) from
// tvf_TeacherRosterMath; the client grid structures these into the student x
// task matrix (grouped by grade + unit). See project_math_assessment_model.
// ---------------------------------------------------------------------------
export interface MathRosterRow {
  studentKey: string
  studentNumber: string
  firstName: string
  lastName: string
  grade: string | null
  programFamily: string | null
  mathTaskKey: string
  unitName: string | null
  unitOrder: number | null
  questionNumber: string
  displayOrder: number | null
  outcomeCode: string | null
  description: string
  answerKey: string | null
  existingResult: boolean | null // latest 0/1 (BIT), or null if never marked
  mathIPPStatus: boolean | null // true = math IPP, false = not, null = unresolved gate
  mathIPPNeedsConfirmation: boolean
  ippProgramFamily: string | null
}

export async function getMathRoster(
  upn: string,
  windowId: string,
  groupKey: string,
): Promise<MathRosterRow[]> {
  const rows = await queryAsUser<{
    StudentKey: string
    StudentNumber: number | string
    FirstName: string
    LastName: string
    Grade: string | null
    ProgramFamily: string | null
    MathTaskKey: string
    UnitName: string | null
    UnitOrder: number | null
    QuestionNumber: string
    DisplayOrder: number | null
    OutcomeCode: string | null
    TaskDescription: string
    AnswerKey: string | null
    ExistingResult: boolean | null
    MathIPPStatus: boolean | null
    MathIPPNeedsConfirmation: boolean | null
    IPPProgramFamily: string | null
  }>(
    upn,
    'SELECT * FROM dbo.tvf_TeacherRosterMath(@UPN, @WindowID, @GroupKey) ORDER BY LastName, FirstName, UnitOrder, DisplayOrder',
    { WindowID: windowId, GroupKey: groupKey },
  )
  return rows.map((r) => ({
    studentKey: String(r.StudentKey),
    studentNumber: String(r.StudentNumber),
    firstName: r.FirstName,
    lastName: r.LastName,
    grade: r.Grade ?? null,
    programFamily: r.ProgramFamily ?? null,
    mathTaskKey: String(r.MathTaskKey),
    unitName: r.UnitName ?? null,
    unitOrder: r.UnitOrder ?? null,
    questionNumber: r.QuestionNumber,
    displayOrder: r.DisplayOrder ?? null,
    outcomeCode: r.OutcomeCode ?? null,
    description: r.TaskDescription,
    answerKey: r.AnswerKey ?? null,
    existingResult: r.ExistingResult ?? null,
    mathIPPStatus: r.MathIPPStatus ?? null,
    mathIPPNeedsConfirmation: Boolean(r.MathIPPNeedsConfirmation),
    ippProgramFamily: r.IPPProgramFamily ?? null,
  }))
}
