import Link from 'next/link'
import Nav from './Nav'
import AuthArea from './AuthArea'
import PostLoginRefresh from './PostLoginRefresh'
import VersionFooter from './VersionFooter'
import MaintenanceProvider from './maintenance/MaintenanceProvider'
import { getCurrentUpn } from '@/lib/auth'
import { authMode } from '@/lib/authMode'
import { getCallerCapabilities } from '@/lib/data'

// App chrome: brand + primary nav + identity widget, wrapping each page's content.
export default async function AppShell({ children }: { children: React.ReactNode }) {
  // Resolve the caller's app capabilities once for the chrome. Cycles + Ingest are gated by the
  // StaffAppAccess allowlist (their pages and actions enforce it server-side); hide those nav items
  // for anyone without the capability so they aren't dead ends. "/" is public, so an unauthenticated
  // visitor (entra mode) has no UPN -> default to no capabilities.
  let caps = { isSysAdmin: false, canManageCycles: false, canRunIngest: false }
  let authed = false
  let capsError = false
  try {
    const upn = await getCurrentUpn() // throws when not signed in (entra) -> caught below
    authed = true
    // Resolve caps in its OWN try so a transient caps-query failure can't flip the user to signed-out
    // (which would also hide the non-gated nav). getCallerCapabilities already retries a cold pool;
    // if it still fails, flag it so the client does a bounded refresh rather than stranding the nav.
    try {
      caps = await getCallerCapabilities(upn)
    } catch {
      capsError = true
    }
  } catch {
    authed = false
  }

  // Only meaningful in entra mode (dev has a fixed DEV_FAKE_UPN — nothing to refresh for).
  const entraMode = authMode() === 'entra'

  return (
    <>
      <MaintenanceProvider isSysAdmin={caps.isSysAdmin} canRunIngest={caps.canRunIngest} authSlot={<AuthArea />}>
      <header className="header">
        {/* The brand lockup is the way home — standard convention, and the only home affordance now
            that the landing page has no nav entry of its own. */}
        <Link href="/" className="brand" aria-label="The SCoR Dashboard — home">
          {/* TCRCE logo at webapp/public/logo.png */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="Tri-County Regional Centre for Education" className="brand-logo" />
          <span className="brand-app">The SCoR Dashboard</span>
        </Link>
        <Nav showCycles={caps.canManageCycles} showIngest={caps.canRunIngest} showMaintenance={caps.isSysAdmin} showStaffAccess={caps.isSysAdmin} />
        <div className="auth">
          <AuthArea />
        </div>
      </header>
      <main className="container">{children}</main>
      <VersionFooter />
      <PostLoginRefresh authed={authed} capsError={capsError} enablePostLogin={entraMode} />
      </MaintenanceProvider>
    </>
  )
}
