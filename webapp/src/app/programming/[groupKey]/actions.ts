'use server'

import { getCurrentUpn } from '@/lib/auth'
import { execProc } from '@/lib/db'
import { getProgrammingRoster } from '@/lib/data'
import { toUserMessage } from '@/lib/errors'
import { revalidatePath } from 'next/cache'

export type ProgrammingKind = 'IPP' | 'Adaptation'

export interface ProgrammingSaveEntry {
  studentKey: string
  subject: string
  programFamily: string
  kind: ProgrammingKind
  value: boolean
}

export interface ProgrammingSaveResult {
  saved: number
  errors: { studentKey: string; message: string }[]
}

/**
 * Bulk-save IPP + Adaptation confirmations from the Programming roster. UPN is resolved server-side
 * (@CallerUPN, never trusted from the client). Each entry is scope-gated against the group roster
 * (via the @UPN TVF) AND must correspond to an existing fact row for that kind — the procs update a
 * seeded row, they don't create one. The FI 4-way sends two entries (English + French Immersion).
 */
export async function saveProgramming(
  groupKey: string,
  entries: ProgrammingSaveEntry[],
): Promise<ProgrammingSaveResult> {
  const upn = await getCurrentUpn()

  // Scope + existence gate: build the set of (student|subject|family) rows the caller may edit,
  // separately per kind (an IPP row and an Adaptation row are gated independently).
  const roster = await getProgrammingRoster(upn, groupKey)
  const allowIPP = new Set<string>()
  const allowAdaptation = new Set<string>()
  for (const r of roster) {
    const k = `${r.studentKey}|${r.subject}|${r.programFamily}`
    if (r.ippExists) allowIPP.add(k)
    if (r.adaptationExists) allowAdaptation.add(k)
  }

  const errors: ProgrammingSaveResult['errors'] = []
  let saved = 0
  for (const e of entries) {
    const k = `${e.studentKey}|${e.subject}|${e.programFamily}`
    const allowed = e.kind === 'IPP' ? allowIPP.has(k) : allowAdaptation.has(k)
    if (!allowed) {
      errors.push({ studentKey: e.studentKey, message: 'Out of your scope — not saved.' })
      continue
    }
    try {
      if (e.kind === 'IPP') {
        await execProc('usp_UpsertStudentIPP', {
          StudentKey: e.studentKey,
          Subject: e.subject,
          ProgramFamily: e.programFamily,
          IsIPP: e.value ? 1 : 0,
          CallerUPN: upn,
        })
      } else {
        await execProc('usp_UpsertStudentAdaptation', {
          StudentKey: e.studentKey,
          Subject: e.subject,
          ProgramFamily: e.programFamily,
          HasAdaptation: e.value ? 1 : 0,
          CallerUPN: upn,
        })
      }
      saved++
    } catch (err) {
      errors.push({ studentKey: e.studentKey, message: toUserMessage(err) })
    }
  }
  revalidatePath(`/programming/${groupKey}`)
  return { saved, errors }
}
