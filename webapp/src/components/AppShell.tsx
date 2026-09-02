import { cookies } from 'next/headers'
import Nav from './Nav'
import AuthArea from './AuthArea'
import PostLoginRefresh from './PostLoginRefresh'
import DevImpersonationBar from './DevImpersonationBar'
import { getCurrentUpn, DEV_IMPERSONATE_COOKIE } from '@/lib/auth'
import { getCallerCapabilities, getImpersonationTargets, type ImpersonationTarget } from '@/lib/data'

// App chrome: brand + primary nav + identity widget, wrapping each page's content.
export default async function AppShell({ children }: { children: React.ReactNode }) {
  // Resolve the caller's app capabilities once for the chrome. Cycles + Ingest are gated by the
  // StaffAppAccess allowlist (their pages and actions enforce it server-side); hide those nav items
  // for anyone without the capability so they aren't dead ends. "/" is public, so an unauthenticated
  // visitor (entra mode) has no UPN -> default to no capabilities.
  let caps = { isSysAdmin: false, canManageCycles: false, canRunIngest: false }
  let authed = false
  let currentUpn: string | null = null
  try {
    const upn = await getCurrentUpn() // throws when not signed in (entra) -> caught below
    authed = true
    currentUpn = upn
    caps = await getCallerCapabilities(upn)
  } catch {
    caps = { isSysAdmin: false, canManageCycles: false, canRunIngest: false }
    authed = false
    currentUpn = null
  }

  // Only meaningful in entra mode (dev has a fixed DEV_FAKE_UPN — nothing to refresh for).
  const entraMode = (process.env.AUTH_MODE ?? 'dev') === 'entra'

  // Dev-only impersonation bar: switch the effective UPN to any synthetic teacher/admin for
  // making how-to docs. Never rendered in entra/live mode.
  const devMode = !entraMode
  let impersonationTargets: ImpersonationTarget[] = []
  let impersonating = false
  if (devMode) {
    try {
      impersonating = Boolean((await cookies()).get(DEV_IMPERSONATE_COOKIE)?.value?.trim())
    } catch {
      impersonating = false
    }
    try {
      impersonationTargets = await getImpersonationTargets()
    } catch {
      impersonationTargets = [] // synthetic warehouse unreachable — free-text UPN still works
    }
  }

  return (
    <>
      {/* Above the header so it sits outside the app chrome -- keeps the header-and-below area
          clean for how-to-doc screenshots (crop this bar out and the shot looks like production). */}
      {devMode && (
        <DevImpersonationBar
          current={currentUpn}
          defaultUpn={process.env.DEV_FAKE_UPN ?? null}
          impersonating={impersonating}
          targets={impersonationTargets}
        />
      )}
      <header className="header">
        <div className="brand">
          {/* TCRCE logo at webapp/public/logo.png */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="Tri-County Regional Centre for Education" className="brand-logo" />
          <span className="brand-app">Short Cycles of Response</span>
        </div>
        <Nav showCycles={caps.canManageCycles} showIngest={caps.canRunIngest} />
        <div className="auth">
          <AuthArea />
        </div>
      </header>
      <main className="container">{children}</main>
      {entraMode && <PostLoginRefresh authed={authed} />}
    </>
  )
}
