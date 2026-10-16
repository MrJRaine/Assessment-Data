'use server'

import { getCurrentUpn } from '@/lib/auth'
import { getReadingGroup, type ReadingGroupRow } from '@/lib/data'
import { toUserMessage } from '@/lib/errors'

/**
 * One Grade/Homeroom group's reading detail for the oversight roll-up tree (1.3.0 Slice 1b), loaded
 * when a node is expanded. UPN is resolved server-side; tvf_StudentCohortReadingGroup applies the same
 * scope gate as the roll-up feed, so a key outside the caller's scope returns no rows.
 */
export async function loadReadingGroup(
  groupKey: string,
  cycleGroupId: string | null,
): Promise<{ rows: ReadingGroupRow[]; error: string | null }> {
  try {
    const upn = await getCurrentUpn()
    return { rows: await getReadingGroup(upn, groupKey, cycleGroupId), error: null }
  } catch (e) {
    return { rows: [], error: toUserMessage(e) }
  }
}
