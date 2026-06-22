'use server'

import { getCurrentUpn } from '@/lib/auth'
import { execProc } from '@/lib/db'
import { revalidatePath } from 'next/cache'

export interface SaveEntry {
  studentNumber: string
  readingScaleId: string
}

export interface SaveResult {
  saved: number
  errors: { studentNumber: string; message: string }[]
}

/**
 * Save reading-level entries for a group. The signed-in teacher's UPN is resolved HERE on the
 * server (never trusted from the client) and passed to the proc as @CallerUPN — the proc runs as
 * the StudentDataAssessment SP but attributes the write to, and gates permission by, the teacher.
 */
export async function saveReadingAssessments(
  windowId: string,
  groupKey: string,
  entries: SaveEntry[],
): Promise<SaveResult> {
  const upn = await getCurrentUpn()
  // Atlantic "today" (DST-aware) to satisfy the proc's [WindowStart, today] date gate.
  const assessmentDate = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Halifax' })

  const errors: SaveResult['errors'] = []
  let saved = 0
  for (const e of entries) {
    try {
      await execProc('usp_UpsertReadingAssessment', {
        StudentNumber: e.studentNumber,
        AssessmentWindowID: windowId,
        ReadingScaleID: e.readingScaleId,
        AssessmentDate: assessmentDate,
        CallerUPN: upn,
      })
      saved++
    } catch (err) {
      // Surface the proc's THROW message (e.g. 51017 date gate, 51031 closed window) per row.
      const msg = err instanceof Error ? err.message : String(err)
      errors.push({ studentNumber: e.studentNumber, message: msg })
    }
  }

  // Re-read the roster so the grid reflects the new levels/deltas.
  revalidatePath(`/enter/${windowId}/${groupKey}`)
  return { saved, errors }
}
