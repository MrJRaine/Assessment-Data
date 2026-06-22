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

export interface IPPResult {
  ok: boolean
  message?: string
}

/**
 * Confirm (or flip) a student's Reading-IPP status from the roster's inline prompt. Mirrors the
 * Power App's scrRosterGrid inline Yes/No buttons: fires immediately (not batched), then revalidates
 * so the row leaves the "needs confirmation" gate. UPN is resolved server-side (never from the
 * client) and passed as @CallerUPN; @ProgramFamily must be the value the roster TVF returned
 * (IPPProgramFamily = window-over-student) so the proc finds the matching current FactStudentIPP row.
 */
export async function setStudentIPP(
  windowId: string,
  groupKey: string,
  studentKey: string,
  programFamily: string,
  isIPP: boolean,
): Promise<IPPResult> {
  const upn = await getCurrentUpn()
  try {
    await execProc('usp_UpsertStudentIPP', {
      StudentKey: studentKey,
      Subject: 'Reading',
      ProgramFamily: programFamily,
      IsIPP: isIPP ? 1 : 0,
      CallerUPN: upn,
    })
    revalidatePath(`/enter/${windowId}/${groupKey}`)
    return { ok: true }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    return { ok: false, message: msg }
  }
}
