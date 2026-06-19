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

// Read failed (e.g. the bridge views are not deployed yet, or a transient connection error).
export function ErrorNote({ message }: { message: string }) {
  return (
    <div className="notice notice-error">
      <div className="notice-title">Couldn&apos;t load data</div>
      <div className="muted">{message}</div>
    </div>
  )
}

export function CardLink({ href, title, meta }: { href: string; title: string; meta?: string }) {
  return (
    <Link href={href} className="card card-link">
      <div className="card-title">{title}</div>
      {meta ? <div className="muted">{meta}</div> : null}
    </Link>
  )
}
