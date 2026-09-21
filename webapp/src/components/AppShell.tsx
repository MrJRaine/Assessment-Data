import { cookies } from 'next/headers'
import Link from 'next/link'
import Nav from './Nav'
import AuthArea from './AuthArea'
import PostLoginRefresh from './PostLoginRefresh'
import DevImpersonationBar from './DevImpersonationBar'
import VersionFooter from './VersionFooter'
import MaintenanceProvider from './maintenance/MaintenanceProvider'
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
  let capsError = false
  try {
    const upn = await getCurrentUpn() // throws when not signed in (entra) -> caught below
    authed = true
    currentUpn = upn
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
      {/* Above the header AND outside MaintenanceProvider so the maintenance overlay never covers it
          -- keeps how-to-doc shots clean AND lets a dev tester re-impersonate during a lockdown. */}
      {devMode && (
        <DevImpersonationBar
          current={currentUpn}
          defaultUpn={process.env.DEV_FAKE_UPN ?? null}
          impersonating={impersonating}
          targets={impersonationTargets}
        />
      )}
      <MaintenanceProvider isSysAdmin={caps.isSysAdmin} canRunIngest={caps.canRunIngest} authSlot={<AuthArea />}>
      <header className="header">
        {/* The brand lockup is the way home — standard convention, and the only home affordance now
            that the landing page has no nav entry of its own. */}
        <Link href="/" className="brand" aria-label="Short Cycles of Response — home">
          {/* TCRCE logo at webapp/public/logo.png */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="Tri-County Regional Centre for Education" className="brand-logo" />
          <span className="brand-app">Short Cycles of Response</span>
        </Link>
        <Nav showCycles={caps.canManageCycles} showIngest={caps.canRunIngest} showMaintenance={caps.isSysAdmin} />
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
