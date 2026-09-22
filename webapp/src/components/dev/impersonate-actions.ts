'use server'

import { cookies } from 'next/headers'
import { revalidatePath } from 'next/cache'
import { authMode } from '@/lib/authMode'
import { DEV_IMPERSONATE_COOKIE, impersonationEnabled, getRealUpn, isSysAdmin } from '@/lib/auth'

/**
 * Server actions backing the impersonation bar. Gate:
 *  - dev mode: allowed (ungated, local synthetic).
 *  - entra mode: allowed ONLY when impersonation is enabled AND the REAL signed-in user is a sysadmin.
 * The sysadmin check is re-run server-side (fresh, not cached) on EVERY call, so a non-sysadmin can
 * never set the cookie -- and getCurrentUpn also ignores the cookie unless the real user is a sysadmin
 * (defense in depth). Throws otherwise, so the action fails closed.
 */
async function assertCanImpersonate(): Promise<void> {
  if (authMode() === 'dev') return
  if (!impersonationEnabled()) {
    throw new Error('Impersonation is not enabled on this deployment')
  }
  const realUpn = await getRealUpn()
  if (!realUpn || !(await isSysAdmin(realUpn, { fresh: true }))) {
    throw new Error('Impersonation requires a sysadmin')
  }
}

export async function setImpersonation(upn: string): Promise<void> {
  await assertCanImpersonate()
  const clean = upn.trim()
  if (!clean) return
  const store = await cookies()
  store.set(DEV_IMPERSONATE_COOKIE, clean, {
    httpOnly: true,
    sameSite: 'lax',
    path: '/',
    maxAge: 60 * 60 * 8, // 8h -- a working session; self-expires so you don't stay someone else forever
  })
  revalidatePath('/', 'layout')
}

export async function clearImpersonation(): Promise<void> {
  await assertCanImpersonate()
  const store = await cookies()
  store.delete(DEV_IMPERSONATE_COOKIE)
  revalidatePath('/', 'layout')
}
