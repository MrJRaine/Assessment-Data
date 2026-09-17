'use server'

import { randomUUID } from 'node:crypto'
import { getCurrentUpn } from '@/lib/auth'
import { getCallerCapabilities } from '@/lib/data'
import { execProc } from '@/lib/db'

/**
 * Managing Short Cycles of Response requires the CanManageCycles capability (StaffAppAccess
 * allowlist). The /cycles page hides the UI for everyone else, but authorization is enforced HERE
 * too (server-side) so the actions can't be reached directly by a non-admin. Mirrors ingest gating.
 */
async function requireCycleAdmin(): Promise<string> {
  const upn = await getCurrentUpn()
  const caps = await getCallerCapabilities(upn)
  if (!caps.canManageCycles) {
    throw new Error('You do not have permission to manage assessment cycles.')
  }
  return upn
}

// ---- Cycle HEADER (DimShortCycle): display name + date range, its own distinct key ----
export interface CycleHeaderInput {
  cycleGroupId?: string | null // omit/null to create (a GUID is generated); set to edit
  displayName: string
  startDate: string // 'YYYY-MM-DD'
  endDate: string
  active: boolean
}

/**
 * Create or edit a cycle header. On create we generate the distinct key (GUID) so a header exists
 * before any instances are attached; editing here re-propagates the name/dates to the cycle's
 * instance windows (usp_UpsertShortCycleHeader). Returns the header's key so the caller can then
 * add instances to it.
 */
export async function saveCycleHeader(input: CycleHeaderInput): Promise<string> {
  const upn = await requireCycleAdmin()
  const cycleGroupId = input.cycleGroupId ?? randomUUID()
  await execProc('usp_UpsertShortCycleHeader', {
    CycleGroupID: cycleGroupId,
    DisplayName: input.displayName.trim(),
    StartDate: input.startDate,
    EndDate: input.endDate,
    ActiveFlag: input.active,
    CallerUPN: upn,
  })
  return cycleGroupId
}

// ---- Scoped assessment INSTANCE (one DimAssessmentWindow row under a header) ----
export interface CycleInstanceInput {
  existingId?: string | null // AssessmentWindowID for edit; null/omit = create
  subject: string // 'Reading' | 'Writing' | 'Math'
  language: string | null // 'English' | 'French' | null (Both); ignored for Math
  programScope: string[] // buckets {English, Early Immersion, Late Immersion}; [] = all
  minGrade: string
  maxGrade: string
  benchmarkMonth: number | null // reading only
  active: boolean
}

export interface SaveInstancesInput {
  cycleGroupId: string // the header's key
  displayName: string // from the header (stored on each window for the entry gate/picker)
  startDate: string
  endDate: string
  instances: CycleInstanceInput[]
}

/**
 * Save the scoped instances of a cycle. Each instance is one DimAssessmentWindow row (subject x
 * language x program-scope x grade band) sharing the header's key + dates. Existing rows update in
 * place (by AssessmentWindowID), new rows insert; "removing" an existing instance = saving it with
 * active=false (its row/history is kept). Name + dates come from the header, not the client's whim
 * (a header edit re-propagates them anyway).
 */
export async function saveShortCycle(input: SaveInstancesInput): Promise<void> {
  const upn = await requireCycleAdmin()
  const valid = input.instances.filter((i) => ['Reading', 'Writing', 'Math'].includes(i.subject))
  if (valid.length === 0) throw new Error('Add at least one assessment instance to the cycle.')

  for (const inst of valid) {
    const params: Record<string, unknown> = {
      AssessmentType: inst.subject,
      CycleName: input.displayName.trim(),
      StartDate: input.startDate,
      EndDate: input.endDate,
      MinGrade: inst.minGrade,
      MaxGrade: inst.maxGrade,
      CycleGroupID: input.cycleGroupId,
      ActiveFlag: inst.active,
      CallerUPN: upn,
    }
    // Optional scope params: omit when empty so the proc's NULL defaults apply (mssql can't infer a
    // SQL type from a bare JS null). Language/benchmark are literacy/reading-only.
    if (inst.programScope.length) params.ProgramScope = inst.programScope.join(',')
    if (inst.subject !== 'Math' && inst.language) params.AssessmentLanguage = inst.language
    if (inst.subject === 'Reading' && inst.benchmarkMonth != null) params.BenchmarkMonth = inst.benchmarkMonth
    if (inst.existingId) params.AssessmentWindowID = inst.existingId
    await execProc('usp_UpsertShortCycle', params)
  }
}
