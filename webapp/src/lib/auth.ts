import 'server-only'
import { cookies } from 'next/headers'
import { auth } from '@/auth'
import { authMode } from './authMode'

/** Cookie that overrides the dev UPN so a developer can impersonate any teacher/admin while
 *  making how-to docs. Read ONLY in dev mode (see getCurrentUpn) -- it is never consulted in
 *  entra mode, so setting it against a real deployment has zero effect. */
export const DEV_IMPERSONATE_COOKIE = 'dev_impersonate_upn'

/**
 * Resolve the current user's UPN (SERVER-ONLY). Two modes via AUTH_MODE:
 *  - 'dev'   : returns the dev-impersonation cookie if set, else DEV_FAKE_UPN, so the app runs
 *              end to end before Entra is wired. LOCAL ONLY -- never deploy with this.
 *  - 'entra' : reads the validated Auth.js session (Microsoft Entra sign-in) and returns
 *              the UPN lifted onto the session in `src/auth.ts`.
 *
 * The resolved UPN flows into db.queryAsUser() as the @UPN parameter the secured views
 * filter on.
 */
export async function getCurrentUpn(): Promise<string> {
  // authMode() throws if AUTH_MODE=dev without the explicit ALLOW_DEV_AUTH opt-in (fail closed).
  if (authMode() === 'dev') {
    // Dev-only impersonation: an override cookie wins over DEV_FAKE_UPN. Gated inside this
    // dev-mode branch, so it can NEVER influence the entra/live path even if a cookie is forged.
    const override = (await cookies()).get(DEV_IMPERSONATE_COOKIE)?.value?.trim()
    const upn = override && override.length > 0 ? override : process.env.DEV_FAKE_UPN
    if (!upn) throw new Error('AUTH_MODE=dev requires DEV_FAKE_UPN to be set')
    return upn
  }

  const session = await auth()
  const user = session?.user as ({ upn?: string; email?: string } | undefined)
  const upn = user?.upn ?? user?.email
  if (!upn) throw new Error('No authenticated user (AUTH_MODE=entra) -- sign in required')
  return upn
}
