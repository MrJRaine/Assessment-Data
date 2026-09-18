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
  cycleGroupId: string | null // the SCoR header key — /enter collapses a cycle's instances into ONE card per subject
  cycleName: string | null // the HEADER's name ('SCoR 1'); the collapsed card's title, since instance names differ
  name: string
  assessmentType: string // 'Reading' | 'Writing' | 'Math' -- groups the window-select screen
  status: string // Upcoming | Open | ClosesToday | Closed
  scaleSystem: string | null
  language: string | null // 'English' | 'French' | null (Both) — distinguishes same-name instances
  programScope: string[] // {English, Early Immersion, Late Immersion}; [] = all programs
  minGrade: string
  maxGrade: string
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
  key: string // GroupKey: URL-safe homeroom key '<SchoolAbbrev>-<cleanHomeroom>' (grades <=9) or 'SEC:<sectionId>' (10+)
  label: string // display name, e.g. 'Homeroom 5/6' (real name; the key is what travels in the URL)
  scope: 'Taught' | 'Oversight' // 'Taught' = the caller's own classes (any role); 'Oversight' = above-teacher school/region view
  groupType: 'Homeroom' | 'Section' | 'Grade' | 'Course' // Data Entry is now 'Course' (a mapped course section); Programming still uses the lenses
  // Course-scoped Data Entry only (Programming leaves these undefined):
  language?: string | null // 'English' | 'French' | null — from the section's course; groups the cards + gates multi-select
  courseCode?: string | null
  teacherNames?: string | null // whose class this is — shown on Oversight cards (co-taught sections list all)
  windowIds?: string[] // the cycle instance(s) this section's students fall under; the roster routes saves by it
  schoolName: string | null
  grade: string | null // MAX(grade) in the group — kept for display/back-compat
  grades: string[] // ALL grades present in the group (e.g. ['P','1'] for a split); drives the grade filter
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
    AssessmentLanguage: string | null
    ProgramScope: string | null
    CycleGroupID: string | null
    CycleName: string | null
    MinGrade: string
    MaxGrade: string
    StartDate: unknown
    EndDate: unknown
    ApplicableStudentCount: number
    EnteredStudentCount: number
  }>(upn, 'SELECT * FROM dbo.tvf_UserAssessmentWindows(@UPN) ORDER BY StartDate, WindowName')
  return rows.map((r) => ({
    id: String(r.AssessmentWindowID),
    cycleGroupId: r.CycleGroupID ?? null,
    cycleName: r.CycleName ?? null,
    name: r.WindowName,
    assessmentType: r.AssessmentType,
    status: r.WindowStatus,
    scaleSystem: r.ScaleSystem,
    language: r.AssessmentLanguage ?? null,
    programScope: r.ProgramScope ? r.ProgramScope.split(',').map((s) => s.trim()).filter(Boolean) : [],
    minGrade: r.MinGrade,
    maxGrade: r.MaxGrade,
    startDate: toYMD(r.StartDate),
    endDate: toYMD(r.EndDate),
    applicableCount: Number(r.ApplicableStudentCount ?? 0),
    enteredCount: Number(r.EnteredStudentCount ?? 0),
  }))
}

// One scoped assessment INSTANCE within a cycle: a DimAssessmentWindow row (subject x language x
// program-scope x grade band). Many can share a cycle header (CycleGroupID).
export interface ShortCycleInstance {
  id: string // AssessmentWindowID (string -- BIGINT precision)
  subject: string // 'Reading' | 'Writing' | 'Math'
  language: string | null // 'English' | 'French' | null (Both); ignored for Math
  programScope: string[] // buckets {English, Early Immersion, Late Immersion}; [] = all programs
  minGrade: string
  maxGrade: string
  benchmarkMonth: number | null // reading only; null = dominant-month fallback
  active: boolean
}

// A cycle = a DimShortCycle HEADER (distinct key + name + dates) plus its instances.
export interface ShortCycle {
  cycleGroupId: string // the header's distinct key (instances tie to this)
  displayName: string
  schoolYear: string
  status: string // Upcoming | Open | ClosesToday | Closed (from header dates)
  startDate: string // 'YYYY-MM-DD'
  endDate: string
  active: boolean // header active
  instances: ShortCycleInstance[]
}

/**
 * All Short Cycles of Response for the admin screen: each DimShortCycle HEADER (distinct key + name +
 * dates) with its scoped instance windows (DimAssessmentWindow, tied by CycleGroupID). An empty header
 * (no instances yet) is included so it can be picked in the instance builder. Config, not per-user PII,
 * so a plain SP query is fine. Status is date-derived in Atlantic time to match the entry gate.
 */
export async function getShortCycles(): Promise<ShortCycle[]> {
  const headers = await query<{
    CycleGroupID: string
    DisplayName: string
    StartDate: unknown
    EndDate: unknown
    SchoolYear: string
    ActiveFlag: boolean
    Status: string
  }>(`
    SELECT CycleGroupID, DisplayName, StartDate, EndDate, SchoolYear, ActiveFlag,
      CASE
        WHEN CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) < StartDate THEN 'Upcoming'
        WHEN CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) > EndDate   THEN 'Closed'
        WHEN CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) = EndDate   THEN 'ClosesToday'
        ELSE 'Open'
      END AS Status
    FROM DimShortCycle
    ORDER BY StartDate DESC, DisplayName`)

  const wins = await query<{
    AssessmentWindowID: string
    CycleGroupID: string | null
    AssessmentType: string
    MinGrade: string
    MaxGrade: string
    BenchmarkMonth: number | null
    ProgramScope: string | null
    AssessmentLanguage: string | null
    ActiveFlag: boolean
  }>(`
    SELECT CAST(AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID, CycleGroupID, AssessmentType,
           MinGrade, MaxGrade, BenchmarkMonth, ProgramScope, AssessmentLanguage, ActiveFlag
    FROM DimAssessmentWindow`)

  // Instances grouped by their header key.
  const byGroup = new Map<string, ShortCycleInstance[]>()
  for (const w of wins) {
    if (!w.CycleGroupID) continue
    const inst: ShortCycleInstance = {
      id: String(w.AssessmentWindowID),
      subject: w.AssessmentType,
      language: w.AssessmentLanguage ?? null,
      programScope: w.ProgramScope ? w.ProgramScope.split(',').map((s) => s.trim()).filter(Boolean) : [],
      minGrade: w.MinGrade,
      maxGrade: w.MaxGrade,
      benchmarkMonth: w.BenchmarkMonth == null ? null : Number(w.BenchmarkMonth),
      active: Boolean(w.ActiveFlag),
    }
    const arr = byGroup.get(w.CycleGroupID)
    if (arr) arr.push(inst)
    else byGroup.set(w.CycleGroupID, [inst])
  }

  return headers.map((h) => ({
    cycleGroupId: h.CycleGroupID,
    displayName: h.DisplayName,
    schoolYear: h.SchoolYear,
    status: h.Status,
    startDate: toYMD(h.StartDate),
    endDate: toYMD(h.EndDate),
    active: Boolean(h.ActiveFlag),
    instances: byGroup.get(h.CycleGroupID) ?? [],
  }))
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

/**
 * Mapped-course SECTIONS for one CYCLE + SUBJECT, scoped to the signed-in user.
 *
 * Keyed on the cycle (not one AssessmentWindowID) because /enter shows ONE card per cycle per
 * subject: a collapsed "Writing" card has no single instance to point at, and pointing it at the
 * English instance would show an FLA teacher nothing. The TVF spans every instance of the cycle.
 */
export async function getTeacherGroups(
  upn: string,
  cycleGroupId: string,
  assessmentType: string,
): Promise<TeacherGroup[]> {
  const rows = await queryAsUser<{
    GroupKey: string
    GroupLabel: string | null
    Scope: string
    GroupType: string
    Language: string | null
    CourseCode: string | null
    TeacherNames: string | null
    SchoolName: string | null
    Grade: string | null
    Grades: string | null
    WindowIDs: string | null
    ApplicableStudentCount: number
    EnteredStudentCount: number
  }>(
    upn,
    'SELECT * FROM dbo.tvf_TeacherGroups(@UPN, @CycleGroupID, @AssessmentType) ORDER BY GroupKey',
    { CycleGroupID: cycleGroupId, AssessmentType: assessmentType },
  )
  return rows.map((r) => {
    const key = String(r.GroupKey)
    // The TVF supplies the display label (the course name + section number);
    // the key is the URL-safe token and no longer encodes the label.
    return {
      key,
      label: r.GroupLabel ?? key,
      scope: r.Scope === 'Oversight' ? 'Oversight' : 'Taught',
      // Data Entry groups are course sections now; keep the old lens values mapping for safety.
      groupType:
        r.GroupType === 'Course' ? 'Course'
          : r.GroupType === 'Section' ? 'Section'
          : r.GroupType === 'Grade' ? 'Grade'
          : 'Homeroom',
      language: r.Language ?? null,
      courseCode: r.CourseCode ?? null,
      teacherNames: r.TeacherNames ?? null,
      windowIds: (r.WindowIDs ?? '').split(',').map((w) => w.trim()).filter(Boolean),
      schoolName: r.SchoolName ?? null,
      grade: r.Grade ?? null,
      grades: (r.Grades ?? '').split(',').map((g) => g.trim()).filter(Boolean),
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
  homeroom: string | null // real homeroom name (for the roster header)
  groupKey: string // which selected class this student came from (combined-roster headings)
  schoolName: string | null
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
  juneLevel: string | null // prior-year "Prev June" starting reading level (anchor)
  lastLevel: string | null // last recorded reading level, ANY cycle (fallback for current)
  prevLevel: string | null // the cycle before the last (for Diff from Prev Cycle)
}

/** One window's roster for the signed-in teacher + group, with each student's existing entry. */
export async function getTeacherRoster(
  upn: string,
  windowId: string,
  groupKeys: string[], // one or MORE classes — same-language sections can be entered as one roster
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
    Homeroom: string | null
    GroupKey: string
    SchoolName: string | null
    ReadingIPPStatus: boolean | null
    ReadingIPPNeedsConfirmation: boolean | null
    IPPProgramFamily: string | null
    AchievementLevel: string | null
    AchievementLevelName: string | null
    AchievementHexColor: string | null
    AchievementHexColorTint: string | null
    JuneReadingLevel: string | null
    LastReadingLevel: string | null
    PrevCycleReadingLevel: string | null
  }>(
    upn,
    'SELECT * FROM dbo.tvf_TeacherRoster(@UPN, @WindowID, @GroupKeys) ORDER BY LastName, FirstName',
    { WindowID: windowId, GroupKeys: groupKeys.join(",") },
  )
  return rows.map((r) => ({
    studentKey: String(r.StudentKey),
    studentNumber: String(r.StudentNumber),
    firstName: r.FirstName,
    lastName: r.LastName,
    grade: r.Grade ?? null,
    homeroom: r.Homeroom ?? null,
    groupKey: String(r.GroupKey),
    schoolName: r.SchoolName ?? null,
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
    juneLevel: r.JuneReadingLevel ?? null,
    lastLevel: r.LastReadingLevel ?? null,
    prevLevel: r.PrevCycleReadingLevel ?? null,
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

// A cycle's language scope: 'English'/'French' FIXES the language (no toggle); null = Both
// (writing shows the EN/FR toggle). Set on /cycles.
export async function getWindowLanguage(windowId: string): Promise<WritingLanguage | null> {
  const rows = await query<{ AssessmentLanguage: string | null }>(
    'SELECT AssessmentLanguage FROM DimAssessmentWindow WHERE AssessmentWindowID = CAST(@WID AS BIGINT)',
    { WID: windowId },
  )
  const v = rows.length ? rows[0].AssessmentLanguage : null
  return v === 'English' || v === 'French' ? v : null
}

// Writing is dual-language: a French-Immersion grade-3+ student is assessed in BOTH English and
// French. The EN/FR toggle picks which track's roster + scores you see and enter.
export type WritingLanguage = 'English' | 'French'

export interface WritingRosterStudent {
  studentKey: string
  studentNumber: string
  firstName: string
  lastName: string
  grade: string | null
  homeroom: string | null
  groupKey: string // which selected class this student came from (combined-roster headings)
  schoolName: string | null
  programFamily: string | null // IPP row's ProgramFamily (window-over-student) — passed to the IPP proc
  ideas: number | null // existing 1–4 trait scores for this window (latest entry), or null if none
  organization: number | null
  language: number | null
  conventions: string | null // '1'–'4' or 'SCR' (Scribed) — Conventions can be scribed
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
  groupKeys: string[], // one or MORE classes — same-language sections can be entered as one roster
  language: WritingLanguage,
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
    ExistingConventionsScore: string | null // VARCHAR: '1'–'4' or 'SCR'
    ExistingAvgScore: number | null
    ExistingAssessmentDate: Date | string | null
    Homeroom: string | null
    GroupKey: string
    SchoolName: string | null
    WritingIPPStatus: boolean | null
    WritingIPPNeedsConfirmation: boolean | null
    IPPProgramFamily: string | null
    AchievementLevelName: string | null
    AchievementHexColor: string | null
    AchievementHexColorTint: string | null
  }>(
    upn,
    'SELECT * FROM dbo.tvf_TeacherRosterWriting(@UPN, @WindowID, @GroupKeys, @Language) ORDER BY LastName, FirstName',
    { WindowID: windowId, GroupKeys: groupKeys.join(","), Language: language },
  )
  return rows.map((r) => ({
    studentKey: String(r.StudentKey),
    studentNumber: String(r.StudentNumber),
    firstName: r.FirstName,
    lastName: r.LastName,
    grade: r.Grade ?? null,
    homeroom: r.Homeroom ?? null,
    groupKey: String(r.GroupKey),
    schoolName: r.SchoolName ?? null,
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
  // Capabilities drive the app chrome (nav gating), so this runs on the FIRST authenticated render.
  // A cold connection pool / token warm-up can make that first query throw; retry a few times so the
  // nav resolves correctly without the user having to refresh. A "no row" result is NOT an error
  // (that user simply has no admin capabilities) — only a thrown query retries.
  let lastErr: unknown
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
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
    } catch (e) {
      lastErr = e
      await new Promise((r) => setTimeout(r, 150 * (attempt + 1)))
    }
  }
  throw lastErr
}

// Maintenance window (single AppMaintenance row). Read unscoped (non-PII operational state);
// surfaced by /api/status to the client poller. MaintenanceAt is UTC.
export interface MaintenanceWindow {
  maintenanceAt: string | null // ISO-8601 UTC, or null = no window
  message: string | null
}
export async function getMaintenanceWindow(): Promise<MaintenanceWindow> {
  const rows = await query<{ MaintenanceAt: Date | string | null; Message: string | null }>(
    'SELECT MaintenanceAt, Message FROM dbo.AppMaintenance WHERE Id = 1',
  )
  const at = rows[0]?.MaintenanceAt ?? null
  return {
    maintenanceAt: at == null ? null : at instanceof Date ? at.toISOString() : new Date(at).toISOString(),
    message: rows[0]?.Message ?? null,
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
  conventions: string | null // '1'–'4' or 'SCR' (Scribed)
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
    conventions: r.ConventionsScore == null ? null : String(r.ConventionsScore),
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
 * Reading-IPP rows in the signed-in user's scope, for the bulk IPP-management screen (/programming).
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

// ---------------------------------------------------------------------------
// Programming (IPP + Adaptations) — window-less group picker + group roster.
// tvf_ProgrammingGroups mirrors tvf_TeacherGroups' shape (so GroupCards renders it),
// but over FLAGGED students only, with the "needs confirmation" count in enteredCount.
// ---------------------------------------------------------------------------
export async function getProgrammingGroups(upn: string): Promise<TeacherGroup[]> {
  const rows = await queryAsUser<{
    GroupKey: string
    GroupLabel: string | null
    Scope: string
    GroupType: string
    SchoolName: string | null
    Grade: string | null
    Grades: string | null
    ApplicableStudentCount: number
    NeedsConfirmCount: number
  }>(upn, 'SELECT * FROM dbo.tvf_ProgrammingGroups(@UPN) ORDER BY GroupKey')
  return rows.map((r) => ({
    key: String(r.GroupKey),
    label: r.GroupLabel ?? String(r.GroupKey),
    scope: r.Scope === 'Oversight' ? 'Oversight' : 'Taught',
    groupType: r.GroupType === 'Section' ? 'Section' : r.GroupType === 'Grade' ? 'Grade' : 'Homeroom',
    schoolName: r.SchoolName ?? null,
    grade: r.Grade ?? null,
    grades: (r.Grades ?? '').split(',').map((g) => g.trim()).filter(Boolean),
    applicableCount: Number(r.ApplicableStudentCount ?? 0),
    enteredCount: Number(r.NeedsConfirmCount ?? 0), // reuses the slot: shown as "N need confirmation"
  }))
}

// Scope-wide Programming confirmation summary (for the picker landing). CELL-level: each
// (student, subject, family) record is one "detail" being confirmed — total = records that exist,
// confirmed = records with a set value (not NULL). Reuses the existing @UPN role-scoped reads.
export interface ProgrammingSummary {
  ipp: { confirmed: number; total: number }
  adaptation: { confirmed: number; total: number }
}
function cellLevel(sets: boolean[]): { confirmed: number; total: number } {
  return { confirmed: sets.filter(Boolean).length, total: sets.length }
}
export async function getProgrammingSummary(upn: string): Promise<ProgrammingSummary> {
  const [ippRows, adapRows] = await Promise.all([
    queryAsUser<{ IsIPP: boolean | number | null }>(upn, 'SELECT IsIPP FROM dbo.tvf_StudentIPP(@UPN)'),
    queryAsUser<{ HasAdaptation: boolean | number | null }>(
      upn,
      'SELECT HasAdaptation FROM dbo.tvf_StudentAdaptation(@UPN)',
    ),
  ])
  return {
    ipp: cellLevel(ippRows.map((r) => r.IsIPP != null)),
    adaptation: cellLevel(adapRows.map((r) => r.HasAdaptation != null)),
  }
}

// One row per (student, subject, programFamily) present in EITHER fact for the chosen group.
// The client pivots these into the IPP and Adaptations grids (subjects as columns), and the
// English+FrenchImmersion pair on a literacy subject drives the FI grade-3+ 4-way cell.
export interface ProgrammingRosterRow {
  studentKey: string
  studentNumber: string
  firstName: string
  lastName: string
  grade: string | null
  homeroom: string | null
  schoolName: string | null
  studentProgramFamily: string | null // the student's OWN program (English / French Immersion)
  subject: string // 'Reading' | 'Writing' | 'Math'
  programFamily: string // the fact row's ProgramFamily
  ippExists: boolean // an IPP row exists for this (student, subject, family)
  adaptationExists: boolean // an Adaptation row exists for this (student, subject, family)
  isIPP: boolean | null // meaningful only when ippExists; null = unconfirmed
  hasAdaptation: boolean | null // meaningful only when adaptationExists; null = unresolved
}

export async function getProgrammingRoster(upn: string, groupKey: string): Promise<ProgrammingRosterRow[]> {
  const rows = await queryAsUser<{
    StudentKey: string
    StudentNumber: number | string
    FirstName: string
    LastName: string
    Grade: string | null
    Homeroom: string | null
    SchoolName: string | null
    StudentProgramFamily: string | null
    Subject: string
    ProgramFamily: string
    IPPExists: boolean | number
    AdaptationExists: boolean | number
    IsIPP: boolean | number | null
    HasAdaptation: boolean | number | null
  }>(
    upn,
    `SELECT * FROM dbo.tvf_ProgrammingRoster(@UPN, @GroupKey)
     ORDER BY LastName, FirstName, Subject, ProgramFamily`,
    { GroupKey: groupKey },
  )
  return rows.map((r) => ({
    studentKey: String(r.StudentKey),
    studentNumber: String(r.StudentNumber),
    firstName: r.FirstName,
    lastName: r.LastName,
    grade: r.Grade ?? null,
    homeroom: r.Homeroom ?? null,
    schoolName: r.SchoolName ?? null,
    studentProgramFamily: r.StudentProgramFamily ?? null,
    subject: r.Subject,
    programFamily: r.ProgramFamily,
    ippExists: Boolean(toBool(r.IPPExists)),
    adaptationExists: Boolean(toBool(r.AdaptationExists)),
    isIPP: toBool(r.IsIPP),
    hasAdaptation: toBool(r.HasAdaptation),
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
  homeroom: string | null
  groupKey: string // which selected class this student came from (combined-roster headings)
  schoolName: string | null
  programFamily: string | null
  mathTaskKey: string | null // NULL when this student's grade+month has no tasks configured
  unitName: string | null
  unitOrder: number | null
  questionNumber: string | null
  displayOrder: number | null
  outcomeCode: string | null
  description: string | null
  answerKey: string | null
  existingResult: boolean | null // latest 0/1 (BIT), or null if never marked
  mathIPPStatus: boolean | null // true = math IPP, false = not, null = unresolved gate
  mathIPPNeedsConfirmation: boolean
  ippProgramFamily: string | null
}

export async function getMathRoster(
  upn: string,
  windowId: string,
  groupKeys: string[], // one or MORE classes — same-language sections can be entered as one roster
): Promise<MathRosterRow[]> {
  const rows = await queryAsUser<{
    StudentKey: string
    StudentNumber: number | string
    FirstName: string
    LastName: string
    Grade: string | null
    Homeroom: string | null
    GroupKey: string
    SchoolName: string | null
    ProgramFamily: string | null
    MathTaskKey: string | null
    UnitName: string | null
    UnitOrder: number | null
    QuestionNumber: string | null
    DisplayOrder: number | null
    OutcomeCode: string | null
    TaskDescription: string | null
    AnswerKey: string | null
    ExistingResult: boolean | null
    MathIPPStatus: boolean | null
    MathIPPNeedsConfirmation: boolean | null
    IPPProgramFamily: string | null
  }>(
    upn,
    'SELECT * FROM dbo.tvf_TeacherRosterMath(@UPN, @WindowID, @GroupKeys) ORDER BY LastName, FirstName, UnitOrder, DisplayOrder',
    { WindowID: windowId, GroupKeys: groupKeys.join(",") },
  )
  return rows.map((r) => ({
    studentKey: String(r.StudentKey),
    studentNumber: String(r.StudentNumber),
    firstName: r.FirstName,
    lastName: r.LastName,
    grade: r.Grade ?? null,
    homeroom: r.Homeroom ?? null,
    groupKey: String(r.GroupKey),
    schoolName: r.SchoolName ?? null,
    programFamily: r.ProgramFamily ?? null,
    mathTaskKey: r.MathTaskKey == null ? null : String(r.MathTaskKey),
    unitName: r.UnitName ?? null,
    unitOrder: r.UnitOrder ?? null,
    questionNumber: r.QuestionNumber ?? null,
    displayOrder: r.DisplayOrder ?? null,
    outcomeCode: r.OutcomeCode ?? null,
    description: r.TaskDescription ?? null,
    answerKey: r.AnswerKey ?? null,
    existingResult: r.ExistingResult ?? null,
    mathIPPStatus: r.MathIPPStatus ?? null,
    mathIPPNeedsConfirmation: Boolean(r.MathIPPNeedsConfirmation),
    ippProgramFamily: r.IPPProgramFamily ?? null,
  }))
}
