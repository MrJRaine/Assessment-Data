import Nav from './Nav'
import AuthArea from './AuthArea'

// App chrome: brand + primary nav + identity widget, wrapping each page's content.
export default function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <>
      <header className="header">
        <div className="brand">
          {/* Swap this file (webapp/public/logo.svg) for the official TCRCE logo. */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.svg" alt="" className="logo" width={28} height={28} />
          <span>Assessment Data</span>
        </div>
        <Nav />
        <div className="auth">
          <AuthArea />
        </div>
      </header>
      <main className="container">{children}</main>
    </>
  )
}
