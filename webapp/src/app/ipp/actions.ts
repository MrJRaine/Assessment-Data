'use server'

import { getCurrentUpn } from '@/lib/auth'
import { execProc } from '@/lib/db'
import { getStudentIPPList } from '@/lib/data'
import { toUserMessage } from '@/lib/errors'
import { revalidatePath } from 'next/cache'

export interface IPPSaveEntry {
  studentKey: string
  subject: string
  programFamily: string
  isIPP: boolean
}

export interface IPPSaveResult {
  saved: number
  errors: { studentKey: string; message: string }[]
}

/**
 * Bulk-save IPP confirmations from the /ipp management screen. UPN resolved server-side as
 * @CallerUPN (never trusted from the client); @ProgramFamily is the row's IPPProgramFamily so the
 * proc finds the matching current FactStudentIPP row. Mirrors scrIPP's ForAll save.
 */
export async function saveStudentIPPs(entries: IPPSaveEntry[]): Promise<IPPSaveResult> {
  const upn = await getCurrentUpn()
  // SCOPE GATE: verify each (student, subject, programFamily) is in the caller's RLS-scoped IPP
  // list (via the @UPN TVF) before writing — the proc itself doesn't enforce per-student RLS.
  const allowed = new Set(
    (await getStudentIPPList(upn)).map((r) => `${r.studentKey}|${r.subject}|${r.programFamily}`),
  )

  const errors: IPPSaveResult['errors'] = []
  let saved = 0
  for (const e of entries) {
    if (!allowed.has(`${e.studentKey}|${e.subject}|${e.programFamily}`)) {
      errors.push({ studentKey: e.studentKey, message: 'Out of your scope — not saved.' })
      continue
    }
    try {
      await execProc('usp_UpsertStudentIPP', {
        StudentKey: e.studentKey,
        Subject: e.subject,
        ProgramFamily: e.programFamily,
        IsIPP: e.isIPP ? 1 : 0,
        CallerUPN: upn,
      })
      saved++
    } catch (err) {
      errors.push({ studentKey: e.studentKey, message: toUserMessage(err) })
    }
  }
  revalidatePath('/ipp')
  return { saved, errors }
}
