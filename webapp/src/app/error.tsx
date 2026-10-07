'use client'

/**
 * Route-level error boundary. Before this existed, ANY unhandled error (e.g. a save server action
 * rejecting on a transient Fabric/token failure) fell through to Next.js's built-in fallback — a
 * near-blank page in production — AND unmounted the route, destroying a teacher's unsaved entries.
 * This at least shows a real message + a Try again (reset) instead of the blank "white window".
 *
 * NOTE: reaching this boundary still unmounts the screen, so it cannot recover in-page state on its
 * own. The save handlers now catch their own failures (so a bad save no longer lands here), and the
 * localStorage entry-draft (1.1.0) is the net for a true crash/refresh.
 */
export default function Error({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div style={{ maxWidth: 560, margin: '4rem auto', padding: '0 1rem', textAlign: 'center' }}>
      <h2 style={{ marginBottom: '0.5rem' }}>Something went wrong</h2>
      <p style={{ color: 'var(--muted, #555)', lineHeight: 1.5 }}>
        This screen hit an unexpected error. If you were part-way through entering data that had not
        been saved, please re-check that screen — it may not have been kept.
      </p>
      <button className="btn" onClick={reset} style={{ marginTop: '1rem' }}>
        Try again
      </button>
    </div>
  )
}
