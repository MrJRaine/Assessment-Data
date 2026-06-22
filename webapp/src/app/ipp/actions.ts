'use server'

import { getCurrentUpn } from '@/lib/auth'
import { execProc } from '@/lib/db'
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
  const errors: IPPSaveResult['errors'] = []
  let saved = 0
  for (const e of entries) {
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
      errors.push({ studentKey: e.studentKey, message: err instanceof Error ? err.message : String(err) })
    }
  }
  revalidatePath('/ipp')
  return { saved, errors }
}
