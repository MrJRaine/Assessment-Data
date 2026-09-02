'use server'

import { cookies } from 'next/headers'
import { revalidatePath } from 'next/cache'
import { authMode } from '@/lib/authMode'
import { DEV_IMPERSONATE_COOKIE } from '@/lib/auth'

/**
 * DEV-ONLY server actions backing the impersonation bar. Both HARD-GATE on dev mode: in entra
 * mode they throw and never touch the cookie, so this can't become a privilege-escalation path
 * on a real deployment (getCurrentUpn also ignores the cookie outside dev mode -- defense in depth).
 */
function assertDev() {
  if (authMode() !== 'dev') {
    throw new Error('Impersonation is available in dev mode only')
  }
}

export async function setImpersonation(upn: string): Promise<void> {
  assertDev()
  const clean = upn.trim()
  if (!clean) return
  const store = await cookies()
  store.set(DEV_IMPERSONATE_COOKIE, clean, {
    httpOnly: true,
    sameSite: 'lax',
    path: '/',
    maxAge: 60 * 60 * 8, // 8h -- a working session; expires on its own so you don't get stuck as someone else
  })
  revalidatePath('/', 'layout')
}

export async function clearImpersonation(): Promise<void> {
  assertDev()
  const store = await cookies()
  store.delete(DEV_IMPERSONATE_COOKIE)
  revalidatePath('/', 'layout')
}
