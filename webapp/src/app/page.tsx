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

export default function Home() {
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
      <p>Container skeleton is running. Readiness:</p>
      <ul style={{ listStyle: 'none', padding: 0 }}>
        <Row label="Fabric connection configured" ok={r.fabricConfigured} />
        <Row label="Auth mode" ok value={r.authMode} />
        <Row label="Entra configured" ok={r.entraConfigured} />
        <Row label="Data region (PIIDPA)" ok={r.regionCompliant} value={r.region} />
      </ul>
      <p style={{ color: '#666', fontSize: '0.9rem' }}>
        Next: wire Entra (OBO), bind the first screen to a secured view, deploy to a Canadian region.
      </p>
    </main>
  )
}
