'use server'

import { getCurrentUpn } from '@/lib/auth'
import { getCallerCapabilities, lookupStaffByEmail } from '@/lib/data'
import { execProc } from '@/lib/db'
import { toUserMessage, UserError } from '@/lib/errors'
import { invalidateAllIdentities } from '@/lib/identityCache'
import { revalidatePath } from 'next/cache'
import { OVERRIDE_ROLES, type OverrideRole } from './constants'

// Role overrides are SysAdmin-only, re-checked server-side (fresh — never a cached capability) so a
// crafted request can't grant itself a role. usp_SetStaffRoleOverride ALSO re-checks; this is the outer gate.
async function assertSysAdmin(): Promise<string> {
  const upn = await getCurrentUpn()
  const caps = await getCallerCapabilities(upn, { fresh: true })
  if (!caps.isSysAdmin) {
    throw new UserError('Only a system administrator can change role overrides.')
  }
  return upn
}

export interface RoleOverrideUpdate {
  email: string
  overrideRole: OverrideRole
  notes?: string | null
  active: boolean
}

/** Find a current staff member by email so a SysAdmin can add them to the override list. */
export async function findStaff(
  email: string,
): Promise<{ ok: boolean; staff?: { email: string; name: string }; message?: string }> {
  try {
    await assertSysAdmin()
    if (!email?.trim()) throw new UserError('Enter a staff email to search.')
    const staff = await lookupStaffByEmail(email)
    if (!staff) return { ok: false, message: 'No current staff member found with that email.' }
    return { ok: true, staff }
  } catch (e) {
    return { ok: false, message: toUserMessage(e) }
  }
}

/** Upsert one staff member's role override (via usp_SetStaffRoleOverride). */
export async function setRoleOverride(u: RoleOverrideUpdate): Promise<{ ok: boolean; message?: string }> {
  try {
    const upn = await assertSysAdmin()
    if (!u.email?.trim()) throw new UserError('A staff email is required.')
    if (!OVERRIDE_ROLES.includes(u.overrideRole)) throw new UserError('Choose a valid override role.')
    await execProc('usp_SetStaffRoleOverride', {
      TargetEmail: u.email.trim(),
      OverrideRole: u.overrideRole,
      Notes: u.notes?.trim() || null,
      Active: u.active,
      CallerUPN: upn,
    })
    // The target's effective role changes on the next ingest; clear identity caches so the app's own
    // nav/gates don't serve a stale capability within the hour TTL. Rare action, full clear is cheap.
    invalidateAllIdentities()
    revalidatePath('/admin/staff-roles')
    return { ok: true }
  } catch (e) {
    return { ok: false, message: toUserMessage(e) }
  }
}
