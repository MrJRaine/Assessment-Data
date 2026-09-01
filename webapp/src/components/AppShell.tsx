import Nav from './Nav'
import AuthArea from './AuthArea'
import { getCurrentUpn } from '@/lib/auth'
import { getCallerAccessLevel } from '@/lib/data'

// App chrome: brand + primary nav + identity widget, wrapping each page's content.
export default async function AppShell({ children }: { children: React.ReactNode }) {
  // Resolve the caller's role once for the chrome. Cycles + Ingest are RegionalAnalyst-only (their
  // pages and actions enforce it server-side); hide those nav items for everyone else so they aren't dead ends.
  // "/" is public, so an unauthenticated visitor (entra mode) has no UPN -> default to not-analyst.
  let isAnalyst = false
  try {
    isAnalyst = (await getCallerAccessLevel(await getCurrentUpn())) === 'RegionalAnalyst'
  } catch {
    isAnalyst = false
  }

  return (
    <>
      <header className="header">
        <div className="brand">
          {/* TCRCE logo at webapp/public/logo.png */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="Tri-County Regional Centre for Education" className="brand-logo" />
          <span className="brand-app">Data Platform</span>
        </div>
        <Nav showAnalyst={isAnalyst} />
        <div className="auth">
          <AuthArea />
        </div>
      </header>
      <main className="container">{children}</main>
    </>
  )
}
