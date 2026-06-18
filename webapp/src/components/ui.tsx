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

export function CardLink({ href, title, meta }: { href: string; title: string; meta?: string }) {
  return (
    <Link href={href} className="card card-link">
      <div className="card-title">{title}</div>
      {meta ? <div className="muted">{meta}</div> : null}
    </Link>
  )
}
