'use server'

import { getCurrentUpn } from '@/lib/auth'
import { getMathCohort, getMathCohortTrend, type MathCohortRow, type MathTrendRow } from '@/lib/data'
import { toUserMessage } from '@/lib/errors'

/**
 * One group's math matrix rows for the oversight roll-up tree, loaded when a Grade / Homeroom row is
 * expanded (math-reports #2). UPN is resolved server-side and tvf_StudentCohortMath applies the same
 * scope gate as the class matrix page, so a key outside the caller's scope returns no rows.
 */
export async function loadMathGroup(
  groupKey: string,
  cycleGroupId: string | null,
): Promise<{ rows: MathCohortRow[]; error: string | null }> {
  try {
    const upn = await getCurrentUpn()
    return { rows: await getMathCohort(upn, groupKey, cycleGroupId), error: null }
  } catch (e) {
    return { rows: [], error: toUserMessage(e) }
  }
}

/**
 * All-started-cycles counts for the summary tree's "Achievement by cycle" bars (1.4.0). Loaded AFTER
 * the tree renders so the heavier all-cycles read never delays the page. Same scope gate as the tree
 * feed (tvf_StudentCohortMathTrend mirrors tvf_StudentCohortMathAll per cycle); no names.
 */
export async function loadMathTrend(): Promise<{ rows: MathTrendRow[]; error: string | null }> {
  try {
    const upn = await getCurrentUpn()
    return { rows: await getMathCohortTrend(upn), error: null }
  } catch (e) {
    return { rows: [], error: toUserMessage(e) }
  }
}
