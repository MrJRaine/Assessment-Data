'use server'

import { randomUUID } from 'node:crypto'
import { getCurrentUpn } from '@/lib/auth'
import { getCallerCapabilities } from '@/lib/data'
import { execProc } from '@/lib/db'

/**
 * Managing Short Cycles of Response requires the CanManageCycles capability (StaffAppAccess
 * allowlist). The /cycles page hides the UI for everyone else, but authorization is enforced HERE
 * too (server-side) so the action can't be reached directly by a non-admin. Mirrors ingest gating.
 */
async function requireCycleAdmin(): Promise<string> {
  const upn = await getCurrentUpn()
  const caps = await getCallerCapabilities(upn)
  if (!caps.canManageCycles) {
    throw new Error('You do not have permission to manage assessment cycles.')
  }
  return upn
}

export interface SubjectGrades {
  minGrade: string
  maxGrade: string
}

export interface ShortCycleInput {
  groupId?: string | null // CycleGroupID for edit; omit/null to create a new cycle
  subjects: string[] // selected subjects, e.g. ['Reading', 'Writing']
  grades: Record<string, SubjectGrades> // per-subject grade band (Reading P-8, Writing P-RG, Math P-6)
  cycleName: string
  startDate: string // 'YYYY-MM-DD'
  endDate: string
  benchmarkMonth: number | null // reading only; null = dominant-month fallback
  active: boolean
  existingRows?: { subject: string; id: string }[] // the cycle's current per-subject rows (edit); reconcile against these
}

// Fallback band if a subject somehow has no grades entry (defensive; the form always supplies one).
const DEFAULT_BAND: SubjectGrades = { minGrade: 'PP', maxGrade: '12' }

/**
 * Create or edit a multi-subject Short Cycle. A cycle is one DimAssessmentWindow row PER subject,
 * all sharing a CycleGroupID (a GUID we generate on create, reuse on edit). We upsert a row for
 * every selected subject and deactivate rows for any subject the analyst un-checked. Reconciliation
 * reads the group's existing rows so edits update in place (keeping surrogate keys / fact links).
 *
 * Nullable proc params (BenchmarkMonth, AssessmentWindowID) are OMITTED when empty so the proc's
 * own NULL defaults apply — mssql can't infer a SQL type from a bare JS null.
 */
export async function saveShortCycle(input: ShortCycleInput): Promise<void> {
  const upn = await requireCycleAdmin()
  const subjects = input.subjects.filter((s) => ['Reading', 'Writing', 'Math'].includes(s))
  if (subjects.length === 0) throw new Error('Select at least one subject for the cycle.')

  // Reuse the group's GUID on edit; generate one on create. Legacy single windows have no group
  // id -- editing one adopts its existing row into a fresh group (updated in place by its id below).
  const groupId = input.groupId ?? randomUUID()

  // The cycle's current per-subject rows (passed from the client), so edits update in place and
  // un-checked subjects get deactivated.
  const idBySubject = new Map((input.existingRows ?? []).map((r) => [r.subject, r.id]))
  const selected = new Set(subjects)

  const base: Record<string, unknown> = {
    CycleName: input.cycleName.trim(),
    StartDate: input.startDate,
    EndDate: input.endDate,
    CycleGroupID: groupId,
    CallerUPN: upn,
  }

  const bandFor = (subject: string): SubjectGrades => input.grades[subject] ?? DEFAULT_BAND

  // Upsert each selected subject with ITS OWN grade band.
  for (const subject of subjects) {
    const band = bandFor(subject)
    const inputs: Record<string, unknown> = {
      ...base,
      AssessmentType: subject,
      MinGrade: band.minGrade,
      MaxGrade: band.maxGrade,
      ActiveFlag: input.active,
    }
    if (subject === 'Reading' && input.benchmarkMonth != null) inputs.BenchmarkMonth = input.benchmarkMonth
    const existingId = idBySubject.get(subject)
    if (existingId) inputs.AssessmentWindowID = existingId
    await execProc('usp_UpsertShortCycle', inputs)
  }

  // Deactivate rows for subjects removed from the cycle (band preserved for the audit trail).
  for (const [subject, id] of idBySubject) {
    if (!selected.has(subject)) {
      const band = bandFor(subject)
      await execProc('usp_UpsertShortCycle', {
        ...base,
        AssessmentType: subject,
        MinGrade: band.minGrade,
        MaxGrade: band.maxGrade,
        AssessmentWindowID: id,
        ActiveFlag: false,
      })
    }
  }
}
