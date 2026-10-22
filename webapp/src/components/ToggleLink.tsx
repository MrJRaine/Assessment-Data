'use client'

import { useRouter } from 'next/navigation'
import { useTransition, type MouseEvent, type ReactNode } from 'react'

// Click feedback for the report view toggles (subject Reading/Writing/Math/RWM, Summary/Student-list,
// the cycle selector, the student-detail subject switch). These are force-dynamic navigations that take
// a beat on the server, so without feedback a click looks like a dead/hung screen.
//
// Mechanism: we DRIVE the navigation ourselves with router.push() inside useTransition, and show a
// spinner while isPending. This deliberately avoids next/link's useLinkStatus, which regressed the
// same-route searchParam navigation (the first click's RSC landed in the router cache but the nav never
// committed, so it took a second click). router.push + useTransition commits reliably on the first click.
//
// It renders a real <a href> so the existing toggle/cycle CSS, right-click and modifier-click (open in a
// new tab) all keep working; only a plain left-click is intercepted for the soft, in-page transition.
export function ToggleLink({
  href,
  className,
  title,
  children,
}: {
  href: string
  className?: string
  title?: string
  children: ReactNode
}) {
  const router = useRouter()
  const [pending, startTransition] = useTransition()

  const onClick = (e: MouseEvent<HTMLAnchorElement>) => {
    // Let the browser handle anything that isn't a plain left-click (new tab, etc.).
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
    e.preventDefault()
    startTransition(() => router.push(href))
  }

  return (
    <a href={href} className={className} title={title} onClick={onClick} aria-busy={pending || undefined}>
      {children}
      {pending ? <span className="toggle-spin" role="status" aria-label="Loading" /> : null}
    </a>
  )
}
