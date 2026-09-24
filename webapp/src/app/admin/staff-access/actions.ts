'use server'

import { getCurrentUpn } from '@/lib/auth'
import { getCallerCapabilities } from '@/lib/data'
import { execProc } from '@/lib/db'
import { toUserMessage, UserError } from '@/lib/errors'
import { invalidateAllIdentities } from '@/lib/identityCache'
import { revalidatePath } from 'next/cache'

// Changing app access is SysAdmin-only, re-checked server-side (fresh — never a cached capability) so
// a crafted request can't grant itself power. usp_SetStaffAppAccess ALSO re-checks; this is the outer gate.
async function assertSysAdmin(): Promise<string> {
  const upn = await getCurrentUpn()
  const caps = await getCallerCapabilities(upn, { fresh: true })
  if (!caps.isSysAdmin) {
    throw new UserError('Only a system administrator can change staff access.')
  }
  return upn
}

export interface StaffAccessUpdate {
  email: string
  isSysAdmin: boolean
  canManageCycles: boolean
  canRunIngest: boolean
  canOverrideMath: boolean
  canOverrideLiteracy: boolean
}

/** Upsert one staff member's five app-capability flags (via usp_SetStaffAppAccess). */
export async function setStaffAccess(u: StaffAccessUpdate): Promise<{ ok: boolean; message?: string }> {
  try {
    const upn = await assertSysAdmin()
    if (!u.email?.trim()) throw new UserError('A staff email is required.')
    await execProc('usp_SetStaffAppAccess', {
      TargetEmail: u.email.trim(),
      IsSysAdmin: u.isSysAdmin,
      CanManageCycles: u.canManageCycles,
      CanRunIngest: u.canRunIngest,
      CanOverrideMath: u.canOverrideMath,
      CanOverrideLiteracy: u.canOverrideLiteracy,
      CallerUPN: upn,
    })
    // The target's capabilities changed — clear the identity caches so their nav/gates refresh within
    // the hour TTL instead of after it. Rare action, so the full clear is cheap.
    invalidateAllIdentities()
    revalidatePath('/admin/staff-access')
    return { ok: true }
  } catch (e) {
    return { ok: false, message: toUserMessage(e) }
  }
}
