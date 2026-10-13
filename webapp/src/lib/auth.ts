import 'server-only'
import { auth } from '@/auth'

/**
 * Resolve the current user's UPN (SERVER-ONLY) from the validated Auth.js session (Microsoft Entra
 * sign-in) -- the UPN lifted onto the session in `src/auth.ts`. Entra is the ONLY auth path in dev
 * and live; the dev-auth bypass exists solely on the dev-impersonation branch.
 *
 * The resolved UPN flows into db.queryAsUser() as the @UPN parameter the secured views filter on.
 */
export async function getCurrentUpn(): Promise<string> {
  const session = await auth()
  const user = session?.user as { upn?: string; email?: string } | undefined
  const upn = user?.upn ?? user?.email
  if (!upn) throw new Error('No authenticated user -- sign in required')
  return upn
}
