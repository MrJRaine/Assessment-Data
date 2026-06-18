import 'server-only'
import { auth } from '@/auth'

/**
 * Resolve the current user's UPN (SERVER-ONLY). Two modes via AUTH_MODE:
 *  - 'dev'   : returns DEV_FAKE_UPN so the app runs end to end before Entra is wired.
 *              LOCAL ONLY -- never deploy with this.
 *  - 'entra' : reads the validated Auth.js session (Microsoft Entra sign-in) and returns
 *              the UPN lifted onto the session in `src/auth.ts`.
 *
 * The resolved UPN flows into db.queryAsUser() as the @UPN parameter the secured views
 * filter on.
 */
export async function getCurrentUpn(): Promise<string> {
  const mode = process.env.AUTH_MODE ?? 'dev'

  if (mode === 'dev') {
    const upn = process.env.DEV_FAKE_UPN
    if (!upn) throw new Error('AUTH_MODE=dev requires DEV_FAKE_UPN to be set')
    return upn
  }

  const session = await auth()
  const user = session?.user as ({ upn?: string; email?: string } | undefined)
  const upn = user?.upn ?? user?.email
  if (!upn) throw new Error('No authenticated user (AUTH_MODE=entra) -- sign in required')
  return upn
}
