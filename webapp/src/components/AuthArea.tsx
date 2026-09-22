import { auth, signIn, signOut } from '@/auth'
import { getCurrentUpn } from '@/lib/auth'

// Header identity widget. Reflects AUTH_MODE so it works before Entra is wired:
//  - dev:   shows the EFFECTIVE UPN (the dev-impersonation override if set, else DEV_FAKE_UPN),
//           so the identity widget matches who you're impersonating in screenshots/how-to docs
//  - entra: shows the EFFECTIVE UPN too (the impersonated user for a sysadmin, else the signed-in
//           user), or a sign-in button when signed out; sign-out always ends the real session
export default async function AuthArea() {
  const mode = process.env.AUTH_MODE ?? 'dev'

  if (mode === 'dev') {
    let upn = process.env.DEV_FAKE_UPN ?? 'dev user'
    try {
      upn = await getCurrentUpn() // honours the dev-impersonation cookie
    } catch {
      /* misconfigured dev mode — fall back to the env value */
    }
    return <span className="muted">{upn} (dev)</span>
  }

  const session = await auth()
  const user = session?.user as ({ upn?: string; email?: string } | undefined)

  if (user) {
    // Signed in: DISPLAY the effective UPN (getCurrentUpn honours a sysadmin's impersonation) so the
    // identity widget matches who you're viewing as in screenshots -- sign-out still ends the REAL session.
    let display = user.upn ?? user.email ?? ''
    try {
      display = await getCurrentUpn()
    } catch {
      /* keep the real session value */
    }
    return (
      <form
        className="authform"
        action={async () => {
          'use server'
          await signOut()
        }}
      >
        <span className="muted">{display}</span>
        <button className="btn-ghost">Sign out</button>
      </form>
    )
  }

  return (
    <form
      action={async () => {
        'use server'
        await signIn('microsoft-entra-id')
      }}
    >
      <button className="btn">Sign in</button>
    </form>
  )
}
