'use server'

import { getCurrentUpn } from '@/lib/auth'
import { getCallerCapabilities } from '@/lib/data'
import { execProc } from '@/lib/db'
import { toUserMessage } from '@/lib/errors'
import { revalidatePath } from 'next/cache'

export interface MaintActionResult {
  ok: boolean
  error?: string
}

// UTC 'YYYY-MM-DD HH:MM:SS' for the VARCHAR proc param (CAST to DATETIME2 in-proc).
function toSqlUtc(d: Date): string {
  return d.toISOString().slice(0, 19).replace('T', ' ')
}

// Full maintenance-page access = CanMaintain (Technology Services) OR sysadmin. (1.3.0 — was sysadmin-only.)
async function assertMaintainer(): Promise<string> {
  const upn = await getCurrentUpn()
  // fresh: authorization must never come from a cached capability — see lib/identityCache.
  const caps = await getCallerCapabilities(upn, { fresh: true })
  if (!caps.canMaintain && !caps.isSysAdmin) throw new Error('Not authorized.')
  return upn
}

/** Schedule the swap `minutes` from now (server clock) with an optional custom message. */
export async function startMaintenance(minutes: number, message: string): Promise<MaintActionResult> {
  let upn: string
  try {
    upn = await assertMaintainer()
  } catch {
    return { ok: false, error: 'Not authorized.' }
  }
  const m = Math.round(Number(minutes))
  if (!Number.isFinite(m) || m < 1 || m > 240) return { ok: false, error: 'Choose between 1 and 240 minutes.' }
  const at = new Date(Date.now() + m * 60_000)
  try {
    await execProc('usp_SetMaintenanceWindow', {
      MaintenanceAt: toSqlUtc(at),
      Message: message.trim() || null,
      CallerUPN: upn,
      Scope: 'manual',
    })
    revalidatePath('/admin/maintenance')
    return { ok: true }
  } catch (e) {
    return { ok: false, error: toUserMessage(e) }
  }
}

/** Cancel a scheduled window / post "all clear" after a swap. The window is LOCKED to whoever opened it
 *  (or any sysadmin) — a non-owner gets a friendly "locked by …" message from usp_ClearMaintenanceWindow. */
export async function clearMaintenance(): Promise<MaintActionResult> {
  let upn: string
  try {
    upn = await assertMaintainer()
  } catch {
    return { ok: false, error: 'Not authorized.' }
  }
  try {
    await execProc('usp_ClearMaintenanceWindow', { CallerUPN: upn })
    revalidatePath('/admin/maintenance')
    return { ok: true }
  } catch (e) {
    return { ok: false, error: toUserMessage(e) }
  }
}
