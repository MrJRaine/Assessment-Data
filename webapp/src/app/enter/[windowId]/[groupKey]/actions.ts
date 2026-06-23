'use server'

import { getCurrentUpn } from '@/lib/auth'
import { execProc } from '@/lib/db'
import { getTeacherRoster } from '@/lib/data'
import { toUserMessage } from '@/lib/errors'
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

  // SCOPE GATE: the write procs trust @CallerUPN but don't enforce per-student RLS, so verify
  // each target is on THIS caller's RLS-scoped roster (via the @UPN TVF) before writing. Blocks a
  // crafted request from saving for a student outside the caller's window/group scope.
  const allowed = new Set((await getTeacherRoster(upn, windowId, groupKey)).map((r) => r.studentNumber))

  const errors: SaveResult['errors'] = []
  let saved = 0
  for (const e of entries) {
    if (!allowed.has(e.studentNumber)) {
      errors.push({ studentNumber: e.studentNumber, message: 'Not in your roster for this window/group — not saved.' })
      continue
    }
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
      const msg = toUserMessage(err)
      errors.push({ studentNumber: e.studentNumber, message: msg })
    }
  }

  // Re-read the roster so the grid reflects the new levels/deltas.
  revalidatePath(`/enter/${windowId}/${groupKey}`)
  return { saved, errors }
}

export interface IppEntry {
  studentKey: string
  programFamily: string
  isIPP: boolean
}

export interface IppSaveResult {
  saved: number
  errors: { studentKey: string; message: string }[]
}

/**
 * Commit a BATCH of staged Reading-IPP confirmations from the roster grid (the inline Yes/No is
 * staged client-side and saved with the Save button, not fired per click). Scope-checks the whole
 * batch once against the caller's RLS-scoped roster, then calls the proc per entry. UPN is resolved
 * server-side (never from the client) and passed as @CallerUPN; @ProgramFamily is the value the
 * roster TVF returned (IPPProgramFamily = window-over-student) so the proc finds the matching row.
 */
export async function confirmRosterIPPs(
  windowId: string,
  groupKey: string,
  entries: IppEntry[],
): Promise<IppSaveResult> {
  const upn = await getCurrentUpn()
  // SCOPE GATE (once for the batch): only students on this caller's RLS-scoped roster.
  const allowed = new Set((await getTeacherRoster(upn, windowId, groupKey)).map((r) => r.studentKey))

  const errors: IppSaveResult['errors'] = []
  let saved = 0
  for (const e of entries) {
    if (!allowed.has(e.studentKey)) {
      errors.push({ studentKey: e.studentKey, message: 'Not in your roster for this window/group — not saved.' })
      continue
    }
    try {
      await execProc('usp_UpsertStudentIPP', {
        StudentKey: e.studentKey,
        Subject: 'Reading',
        ProgramFamily: e.programFamily,
        IsIPP: e.isIPP ? 1 : 0,
        CallerUPN: upn,
      })
      saved++
    } catch (err) {
      errors.push({ studentKey: e.studentKey, message: toUserMessage(err) })
    }
  }

  revalidatePath(`/enter/${windowId}/${groupKey}`)
  return { saved, errors }
}
