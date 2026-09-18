'use server'

import { revalidatePath } from 'next/cache'
import { getCurrentUpn } from '@/lib/auth'
import { execProc } from '@/lib/db'
import { getTeacherRoster, getTeacherRosterWriting, getWindowEndDate, getMathRoster, type WritingLanguage } from '@/lib/data'
import { toUserMessage } from '@/lib/errors'

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
  // Atlantic "today" (DST-aware). Closed (past) windows are still writeable for late entry, but the
  // proc's 51017 gate caps the assessment date at the window's own month-end -- so date the entry at
  // MIN(today, window EndDate). For the current open window that's just today; for a past window it
  // bins the late entry into that window's month (a plain "today" would be rejected).
  const today = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Halifax' })
  const windowEnd = await getWindowEndDate(windowId)
  const assessmentDate = windowEnd && windowEnd < today ? windowEnd : today

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

  // No re-read: the grid updates optimistically from the entry state, and the page is
  // force-dynamic so any later navigation re-fetches fresh anyway.
  return { saved, errors }
}

export interface WritingEntry {
  studentNumber: string
  ideas: number
  organization: number
  language: number
  conventions: string // '1'–'4' or 'SCR' (Scribed); proc validates
}

/**
 * Save 4-trait writing entries for a group. Same trust model as saveReadingAssessments: the UPN is
 * resolved server-side and passed as @CallerUPN; each target is scope-checked against the caller's
 * writing roster before the proc runs. The proc validates each score 1–4 and the program-family match.
 */
export async function saveWritingAssessments(
  windowId: string,
  groupKey: string,
  entries: WritingEntry[],
  language: WritingLanguage,
): Promise<SaveResult> {
  const upn = await getCurrentUpn()
  const today = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Halifax' })
  const windowEnd = await getWindowEndDate(windowId)
  const assessmentDate = windowEnd && windowEnd < today ? windowEnd : today

  // Scope-gate against THIS language's roster (dual-language writing): an FI grade-3+ student is
  // on both rosters, but an English-only student isn't on the French roster and vice-versa.
  const allowed = new Set((await getTeacherRosterWriting(upn, windowId, groupKey, language)).map((r) => r.studentNumber))

  const errors: SaveResult['errors'] = []
  let saved = 0
  for (const e of entries) {
    if (!allowed.has(e.studentNumber)) {
      errors.push({ studentNumber: e.studentNumber, message: 'Not in your roster for this window/group — not saved.' })
      continue
    }
    try {
      await execProc('usp_UpsertWritingAssessment', {
        StudentNumber: e.studentNumber,
        AssessmentWindowID: windowId,
        IdeasScore: e.ideas,
        OrganizationScore: e.organization,
        LanguageScore: e.language,
        ConventionsScore: e.conventions,
        AssessmentDate: assessmentDate,
        AssessmentLanguage: language,
        CallerUPN: upn,
      })
      saved++
    } catch (err) {
      errors.push({ studentNumber: e.studentNumber, message: toUserMessage(err) })
    }
  }
  return { saved, errors }
}

export interface MathEntry {
  studentNumber: string
  mathTaskKey: string
  result: '0' | '1' | null // '1' can-do / '0' cannot / null = clear the same-day mark
}

export interface MathSaveResult {
  saved: number
  errors: { studentNumber: string; mathTaskKey: string; message: string }[]
}

/**
 * Save a batch of dirty math cells for a group. Same trust model as the reading/writing saves:
 * UPN resolved server-side and passed as @CallerUPN; each target scope-checked against the caller's
 * math roster before the proc runs. Grain is per (student, task); result '0'/'1' upserts, null clears.
 */
export async function saveMathAssessments(
  windowId: string,
  groupKey: string,
  entries: MathEntry[],
): Promise<MathSaveResult> {
  const upn = await getCurrentUpn()
  const today = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Halifax' })
  const windowEnd = await getWindowEndDate(windowId)
  const assessmentDate = windowEnd && windowEnd < today ? windowEnd : today

  const allowed = new Set((await getMathRoster(upn, windowId, groupKey)).map((r) => r.studentNumber))

  const errors: MathSaveResult['errors'] = []
  let saved = 0
  for (const e of entries) {
    if (!allowed.has(e.studentNumber)) {
      errors.push({ studentNumber: e.studentNumber, mathTaskKey: e.mathTaskKey, message: 'Not in your roster for this window/group — not saved.' })
      continue
    }
    try {
      await execProc('usp_UpsertMathAssessment', {
        StudentNumber: e.studentNumber,
        AssessmentWindowID: windowId,
        MathTaskKey: e.mathTaskKey,
        Result: e.result, // '0' | '1' | null (clear)
        AssessmentDate: assessmentDate,
        CallerUPN: upn,
      })
      saved++
    } catch (err) {
      errors.push({ studentNumber: e.studentNumber, mathTaskKey: e.mathTaskKey, message: toUserMessage(err) })
    }
  }

  // The roster URL is keyed on the CYCLE now (/enter/cycle/<cycleGroupId>/<subject>/<groupKey>) and
  // the action only knows the window, so revalidate the /enter subtree rather than a path that no
  // longer resolves — this also refreshes the cycle card's progress count on the way back out.
  revalidatePath('/enter', 'layout')
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
  subject: 'Reading' | 'Writing' = 'Reading',
  language: WritingLanguage = 'English',
): Promise<IppSaveResult> {
  const upn = await getCurrentUpn()
  // SCOPE GATE (once for the batch): only students on this caller's RLS-scoped roster. Writing is
  // dual-language, so scope to the confirmed track's roster (language is ignored for Reading).
  const roster = subject === 'Writing'
    ? await getTeacherRosterWriting(upn, windowId, groupKey, language)
    : await getTeacherRoster(upn, windowId, groupKey)
  const allowed = new Set(roster.map((r) => r.studentKey))

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
        Subject: subject,
        ProgramFamily: e.programFamily,
        IsIPP: e.isIPP ? 1 : 0,
        CallerUPN: upn,
      })
      saved++
    } catch (err) {
      errors.push({ studentKey: e.studentKey, message: toUserMessage(err) })
    }
  }
  return { saved, errors }
}
