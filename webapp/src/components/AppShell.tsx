import Nav from './Nav'
import AuthArea from './AuthArea'
import PostLoginRefresh from './PostLoginRefresh'
import { getCurrentUpn } from '@/lib/auth'
import { getCallerCapabilities } from '@/lib/data'

// App chrome: brand + primary nav + identity widget, wrapping each page's content.
export default async function AppShell({ children }: { children: React.ReactNode }) {
  // Resolve the caller's app capabilities once for the chrome. Cycles + Ingest are gated by the
  // StaffAppAccess allowlist (their pages and actions enforce it server-side); hide those nav items
  // for anyone without the capability so they aren't dead ends. "/" is public, so an unauthenticated
  // visitor (entra mode) has no UPN -> default to no capabilities.
  let caps = { isSysAdmin: false, canManageCycles: false, canRunIngest: false }
  let authed = false
  try {
    const upn = await getCurrentUpn() // throws when not signed in (entra) -> caught below
    authed = true
    caps = await getCallerCapabilities(upn)
  } catch {
    caps = { isSysAdmin: false, canManageCycles: false, canRunIngest: false }
    authed = false
  }

  // Only meaningful in entra mode (dev has a fixed DEV_FAKE_UPN — nothing to refresh for).
  const entraMode = (process.env.AUTH_MODE ?? 'dev') === 'entra'

  return (
    <>
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
