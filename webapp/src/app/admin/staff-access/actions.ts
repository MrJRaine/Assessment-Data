'use server'

import { getCurrentUpn } from '@/lib/auth'
import { getCallerCapabilities, lookupStaffByEmail } from '@/lib/data'
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
  canMaintain: boolean
}

/** Resolve an email so a SysAdmin can add them to the access list. A current staff record is NOT
 *  required — app capabilities (incl. Maintenance for Technology Services) are keyed purely by email,
 *  and the person may not be in PowerSchool at all. When there's no current DimStaff row we still allow
 *  the add (known:false) with the email as the display name. */
export async function findStaff(
  email: string,
): Promise<{ ok: boolean; staff?: { email: string; name: string }; known?: boolean; message?: string }> {
  try {
    await assertSysAdmin()
    const e = email?.trim()
    if (!e) throw new UserError('Enter a staff email to search.')
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e)) throw new UserError('Enter a valid email address.')
    const staff = await lookupStaffByEmail(e)
    if (staff) return { ok: true, staff, known: true }
    return { ok: true, staff: { email: e.toLowerCase(), name: e }, known: false }
  } catch (e) {
    return { ok: false, message: toUserMessage(e) }
  }
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
      CanMaintain: u.canMaintain,
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
