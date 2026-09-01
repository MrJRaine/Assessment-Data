import Nav from './Nav'
import AuthArea from './AuthArea'
import { getCurrentUpn } from '@/lib/auth'
import { getCallerCapabilities } from '@/lib/data'

// App chrome: brand + primary nav + identity widget, wrapping each page's content.
export default async function AppShell({ children }: { children: React.ReactNode }) {
  // Resolve the caller's app capabilities once for the chrome. Cycles + Ingest are gated by the
  // StaffAppAccess allowlist (their pages and actions enforce it server-side); hide those nav items
  // for anyone without the capability so they aren't dead ends. "/" is public, so an unauthenticated
  // visitor (entra mode) has no UPN -> default to no capabilities.
  let caps = { canManageCycles: false, canRunIngest: false }
  try {
    caps = await getCallerCapabilities(await getCurrentUpn())
  } catch {
    caps = { canManageCycles: false, canRunIngest: false }
  }

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
    </>
  )
}
