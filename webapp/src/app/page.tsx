import { auth, signIn, signOut } from '@/auth'
import { getReadiness } from '@/lib/readiness'

export const dynamic = 'force-dynamic'

function Row({ label, ok, value }: { label: string; ok: boolean; value?: string }) {
  return (
    <li style={{ margin: '0.35rem 0' }}>
      <span style={{ fontFamily: 'monospace', color: ok ? '#1a7f37' : '#9a6700' }}>
        {ok ? '[OK]' : '[--]'}
      </span>{' '}
      {label}
      {value ? `: ${value}` : ''}
    </li>
  )
}

const btn: React.CSSProperties = {
  padding: '0.5rem 0.9rem',
  border: '1px solid #0078d4',
  borderRadius: 4,
  background: '#0078d4',
  color: '#fff',
  cursor: 'pointer',
}

export default async function Home() {
  const session = await auth()
  const user = session?.user as ({ upn?: string; email?: string; name?: string } | undefined)
  const r = getReadiness()

  return (
    <main
      style={{
        fontFamily: 'system-ui, sans-serif',
        maxWidth: 680,
        margin: '4rem auto',
        padding: '0 1rem',
        lineHeight: 1.5,
      }}
    >
      <h1 style={{ fontSize: '1.5rem' }}>Assessment Data Platform &mdash; web app</h1>

      <section style={{ margin: '1.5rem 0', padding: '1rem', border: '1px solid #e1e4e8', borderRadius: 6 }}>
        <h2 style={{ fontSize: '1rem', marginTop: 0 }}>Access control</h2>
        {user ? (
          <>
            <p>
              Signed in as <strong>{user.upn ?? user.email}</strong>
              {user.name ? ` (${user.name})` : ''}.
            </p>
            <form
              action={async () => {
                'use server'
                await signOut()
              }}
            >
              <button style={{ ...btn, background: '#6e7781', borderColor: '#6e7781' }}>Sign out</button>
            </form>
          </>
        ) : (
          <>
            <p>Not signed in.</p>
            <form
              action={async () => {
                'use server'
                await signIn('microsoft-entra-id')
              }}
            >
              <button style={btn}>Sign in with Microsoft</button>
            </form>
          </>
        )}
      </section>

      <p>Readiness:</p>
      <ul style={{ listStyle: 'none', padding: 0 }}>
        <Row label="Fabric connection configured" ok={r.fabricConfigured} />
        <Row label="Auth mode" ok value={r.authMode} />
        <Row label="Entra configured" ok={r.entraConfigured} />
        <Row label="Data region (PIIDPA)" ok={r.regionCompliant} value={r.region} />
      </ul>

      <p style={{ color: '#666', fontSize: '0.9rem' }}>
        Next: confirm a Fabric read/write as the signed-in user, then bind the first screen.
      </p>
    </main>
  )
}
