import Link from 'next/link'

export function PageHeader({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div className="page-header">
      <h1>{title}</h1>
      {subtitle ? <p className="muted">{subtitle}</p> : null}
    </div>
  )
}

// Amber banner marking a screen whose data wiring is still pending (Phase 3b / B3+).
export function ScaffoldNote({ children }: { children: React.ReactNode }) {
  return <div className="scaffold-note">{children}</div>
}

// Dashed box standing in for a control/region not yet bound to data.
export function Placeholder({ label }: { label: string }) {
  return <div className="placeholder">{label}</div>
}

// Neutral "nothing to show" state (e.g. a teacher with no windows/groups for the period).
export function EmptyState({ title, hint }: { title: string; hint?: string }) {
  return (
    <div className="notice notice-empty">
      <div className="notice-title">{title}</div>
      {hint ? <div className="muted">{hint}</div> : null}
    </div>
  )
}

// Read failed (e.g. a transient connection error). The raw message (SQL/driver text) is shown
// only in the explicit dev-diagnostic mode; in production it's genericized so internals don't
// leak to the browser. (Server-rendered, so AUTH_MODE is readable; on the client it's undefined
// -> falls through to the generic message, which is the safe default.)
export function ErrorNote({ message }: { message: string }) {
  const devDiag = process.env.AUTH_MODE === 'dev' && process.env.ALLOW_DEV_AUTH === 'true'
  const shown = devDiag ? message : 'Please retry; if it persists, contact your administrator.'
  return (
    <div className="notice notice-error">
      <div className="notice-title">Couldn&apos;t load data</div>
      <div className="muted">{shown}</div>
    </div>
  )
}

// Navigation/loading indicator. Rendered by route-segment loading.tsx files so a click on a
// card gives immediate feedback while the destination server-renders (the proc query runs).
export function Loading({ label = 'Loading…' }: { label?: string }) {
  return (
    <div className="loading" role="status" aria-live="polite">
      <span className="spinner" aria-hidden="true" />
      <span>{label}</span>
    </div>
  )
}

export function CardLink({
  href,
  title,
  desc,
  cta,
  meta,
}: {
  href: string
  title: string
  desc?: string
  cta?: string
  meta?: string
}) {
  return (
    <Link href={href} className="card card-link">
      <div className="card-title">{title}</div>
      {desc ? <div className="card-desc">{desc}</div> : null}
      {meta ? <div className="muted">{meta}</div> : null}
      {cta ? <div className="card-cta">{cta}&nbsp;&rsaquo;</div> : null}
    </Link>
  )
}
