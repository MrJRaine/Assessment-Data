'use client'

import Link from 'next/link'
import { useLinkStatus } from 'next/link'

// Report pages are force-dynamic, and their toggles (subject Reading/Writing/Math/RWM, the
// Summary/Student-list view switch, the cycle selector) are SAME-ROUTE soft navigations that re-run
// the server component — awaiting the TVF reads — before the page swaps. Nothing indicated that wait,
// so a click felt dead. useLinkStatus fires the instant the <Link> is clicked (transport-independent,
// like the CardLink "Opening…" overlay), so a small inline spinner appears immediately on the toggle
// the user pressed. Must be rendered as a DESCENDANT of the <Link> it reports on.

// Pending spinner alone — drop inside any <Link> that is already a client component (e.g. CycleSelector).
export function LinkSpinner() {
  const { pending } = useLinkStatus()
  if (!pending) return null
  return <span className="toggle-spin" role="status" aria-label="Loading" />
}

// A next/link that shows the inline pending spinner after its label. Usable from server components.
// prefetch is disabled because these targets are force-dynamic (a prefetch would run the page on the
// server) — matching CardLink.
export function ToggleLink({
  href,
  className,
  title,
  children,
}: {
  href: string
  className?: string
  title?: string
  children: React.ReactNode
}) {
  return (
    <Link href={href} className={className} title={title} prefetch={false}>
      {children}
      <LinkSpinner />
    </Link>
  )
}
