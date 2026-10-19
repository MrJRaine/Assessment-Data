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

/** Resolve an email so a SysAdmin can add them to the override list.
 *  Default (allowExternal=false): require a current staff record — an unknown email is rejected so a typo
 *  is caught.
 *  allowExternal=true (the "not in the system" checkbox): skip the lookup and add the email as given — a
 *  coach already excluded from active staff by the merge write rule (so no active DimStaff row), or
 *  someone not yet in PowerSchool, must still be addable. The override is keyed by email and takes effect
 *  on the next ingest that includes them. */
export async function findStaff(
  email: string,
  allowExternal = false,
): Promise<{ ok: boolean; staff?: { email: string; name: string }; known?: boolean; message?: string }> {
  try {
    await assertSysAdmin()
    const e = email?.trim()
    if (!e) throw new UserError('Enter a staff email to search.')
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e)) throw new UserError('Enter a valid email address.')
    if (allowExternal) return { ok: true, staff: { email: e.toLowerCase(), name: e }, known: false }
    const staff = await lookupStaffByEmail(e)
    if (!staff) {
      return { ok: false, message: 'No current staff member found with that email. Tick “not in the system” to add them anyway.' }
    }
    return { ok: true, staff, known: true }
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
