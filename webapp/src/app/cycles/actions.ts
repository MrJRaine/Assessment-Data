'use server'

import { getCurrentUpn } from '@/lib/auth'
import { getCallerAccessLevel } from '@/lib/data'
import { execProc } from '@/lib/db'

/**
 * Managing Short Cycles of Response is a RegionalAnalyst-only action. The /cycles page hides the
 * UI for everyone else, but authorization is enforced HERE too (server-side) so the action can't
 * be reached directly by a non-analyst. Mirrors the ingest gating.
 */
async function requireAnalyst(): Promise<string> {
  const upn = await getCurrentUpn()
  const role = await getCallerAccessLevel(upn)
  if (role !== 'RegionalAnalyst') {
    throw new Error('Regional Analyst access is required to manage assessment cycles.')
  }
  return upn
}

export interface ShortCycleInput {
  id?: string | null // AssessmentWindowID for edit; omit/null to create
  assessmentType: string // 'Reading' | 'Writing' | 'Math'
  cycleName: string
  startDate: string // 'YYYY-MM-DD'
  endDate: string
  minGrade: string
  maxGrade: string
  benchmarkMonth: number | null // reading only; null = dominant-month fallback
  active: boolean
}

/**
 * Create or edit a Short Cycle via usp_UpsertShortCycle. Nullable params (BenchmarkMonth,
 * AssessmentWindowID) are OMITTED when empty so the proc's own NULL defaults apply — mssql can't
 * infer a SQL type from a bare JS null, so we never pass one.
 */
export async function saveShortCycle(input: ShortCycleInput): Promise<void> {
  const upn = await requireAnalyst()

  const inputs: Record<string, unknown> = {
    AssessmentType: input.assessmentType,
    CycleName: input.cycleName.trim(),
    StartDate: input.startDate,
    EndDate: input.endDate,
    MinGrade: input.minGrade,
    MaxGrade: input.maxGrade,
    ActiveFlag: input.active,
    CallerUPN: upn,
  }
  // Only reading cycles carry a benchmark month; omit otherwise so the proc stores NULL.
  if (input.assessmentType === 'Reading' && input.benchmarkMonth != null) {
    inputs.BenchmarkMonth = input.benchmarkMonth
  }
  if (input.id) inputs.AssessmentWindowID = input.id

  await execProc('usp_UpsertShortCycle', inputs)
}

/** Activate / deactivate (hide) a cycle without editing its other fields. */
export async function setShortCycleActive(input: ShortCycleInput, active: boolean): Promise<void> {
  await saveShortCycle({ ...input, active })
}
