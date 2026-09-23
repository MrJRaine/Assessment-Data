'use client'

import { useLinkStatus } from 'next/link'

// Client-side navigation feedback that fires the INSTANT a <Link> is clicked — before the server
// responds at all. That makes it immune to reverse-proxy response buffering: on live, IIS/ARR was
// collapsing the roster's streamed Suspense "Loading roster…" fallback into one delayed response, so
// a click looked like a dead hang until the whole page dropped in. This spinner doesn't depend on the
// server streaming anything, so the card shows "Opening…" immediately regardless of the transport.
//
// Must be rendered as a descendant of the <Link> it reports on (useLinkStatus reads that context).
export function LinkPending({ label = 'Opening…' }: { label?: string }) {
  const { pending } = useLinkStatus()
  if (!pending) return null
  return (
    <span className="card-pending" role="status" aria-live="polite">
      <span className="spinner" aria-hidden="true" />
      <span>{label}</span>
    </span>
  )
}
