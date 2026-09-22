import 'server-only'
import { cookies } from 'next/headers'
import { auth } from '@/auth'
import { authMode } from './authMode'
import { getCallerCapabilities } from './data'

/** Cookie that overrides the EFFECTIVE UPN so an operator can view the app as another user. Honoured
 *  ungated in dev mode (local synthetic), and in entra mode ONLY when impersonation is enabled AND the
 *  real signed-in user is a sysadmin (see getCurrentUpn) -- a forged cookie otherwise has zero effect. */
export const DEV_IMPERSONATE_COOKIE = 'dev_impersonate_upn'

/** Cookie remembering that the sysadmin collapsed the impersonation bar (so it stays out of screenshots
 *  across navigations). Read server-side by AppShell to render collapsed with no flash. */
export const IMPERSONATE_BAR_COLLAPSED_COOKIE = 'impersonate_bar_collapsed'

/**
 * Is impersonation available on this deployment?
 *  - dev mode:   always (local synthetic, no real data).
 *  - entra mode: only when ALLOW_IMPERSONATION=true (set on the dev container). Off on live unless
 *                explicitly enabled, so this can never appear in production by default.
 */
export function impersonationEnabled(): boolean {
  return authMode() === 'dev' || process.env.ALLOW_IMPERSONATION === 'true'
}

/**
 * The REAL signed-in identity, NEVER overridden by the impersonation cookie. Dev mode has no real
 * sign-in, so DEV_FAKE_UPN is treated as the real identity there. Used to gate impersonation (only a
 * real sysadmin may do it) and to label the bar. Returns null when not signed in (entra, public page).
 */
export async function getRealUpn(): Promise<string | null> {
  if (authMode() === 'dev') {
    return process.env.DEV_FAKE_UPN ?? null
  }
  const session = await auth()
  const user = session?.user as { upn?: string; email?: string } | undefined
  return user?.upn ?? user?.email ?? null
}

/** Whether a UPN is an app sysadmin (StaffAppAccess.IsSysAdmin). Cached (see getCallerCapabilities);
 *  pass { fresh: true } where the answer AUTHORIZES an action. Never throws -> false on error. */
export async function isSysAdmin(upn: string, opts: { fresh?: boolean } = {}): Promise<boolean> {
  try {
    return (await getCallerCapabilities(upn, opts)).isSysAdmin
  } catch {
    return false
  }
}

/**
 * Resolve the EFFECTIVE UPN — what every data query runs as. Two modes via AUTH_MODE:
 *  - 'dev'   : the impersonation cookie if set, else DEV_FAKE_UPN (ungated -- local synthetic only).
 *  - 'entra' : the validated Entra session UPN, UNLESS impersonation is enabled AND the real user is a
 *              sysadmin AND the cookie names someone else -> then the impersonated UPN. The sysadmin
 *              check is server-side against StaffAppAccess, so a forged cookie from a non-sysadmin is
 *              ignored (fail-closed). Only checked when a cookie is present, so the normal path pays
 *              no extra query.
 *
 * The resolved UPN flows into db.queryAsUser() / the @UPN TVFs the secured logic filters on.
 */
export async function getCurrentUpn(): Promise<string> {
  if (authMode() === 'dev') {
    const override = (await cookies()).get(DEV_IMPERSONATE_COOKIE)?.value?.trim()
    const upn = override && override.length > 0 ? override : process.env.DEV_FAKE_UPN
    if (!upn) throw new Error('AUTH_MODE=dev requires DEV_FAKE_UPN to be set')
    return upn
  }

  const realUpn = await getRealUpn()
  if (!realUpn) throw new Error('No authenticated user (AUTH_MODE=entra) -- sign in required')

  if (process.env.ALLOW_IMPERSONATION === 'true') {
    const override = (await cookies()).get(DEV_IMPERSONATE_COOKIE)?.value?.trim()
    if (override && override.length > 0 && override.toLowerCase() !== realUpn.toLowerCase()) {
      if (await isSysAdmin(realUpn)) return override
    }
  }
  return realUpn
}
