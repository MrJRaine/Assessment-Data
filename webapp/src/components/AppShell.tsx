import Nav from './Nav'
import AuthArea from './AuthArea'

// App chrome: brand + primary nav + identity widget, wrapping each page's content.
export default function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <>
      <header className="header">
        <div className="brand">
          {/* TCRCE logo at webapp/public/logo.png */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="Tri-County Regional Centre for Education" className="brand-logo" />
          <span className="brand-app">Data Platform</span>
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
