import Nav from './Nav'
import AuthArea from './AuthArea'

// App chrome: brand + primary nav + identity widget, wrapping each page's content.
export default function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <>
      <header className="header">
        <div className="brand">Assessment Data</div>
        <Nav />
        <div className="auth">
          <AuthArea />
        </div>
      </header>
      <main className="container">{children}</main>
    </>
  )
}
