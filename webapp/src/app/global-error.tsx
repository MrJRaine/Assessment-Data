'use client'

/**
 * Global error boundary — the last resort if an error escapes even the root layout (where the
 * normal error.tsx cannot render). Must bring its own <html>/<body>. Same purpose as error.tsx:
 * show a real message + Try again instead of Next.js's blank built-in fallback.
 */
export default function GlobalError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: 'Lato, system-ui, sans-serif', margin: 0 }}>
        <div style={{ maxWidth: 560, margin: '4rem auto', padding: '0 1rem', textAlign: 'center' }}>
          <h2 style={{ marginBottom: '0.5rem' }}>Something went wrong</h2>
          <p style={{ color: '#555', lineHeight: 1.5 }}>
            The app hit an unexpected error. If you were part-way through entering data that had not
            been saved, please re-check that screen — it may not have been kept.
          </p>
          <button onClick={reset} style={{ marginTop: '1rem', padding: '0.5rem 1rem', cursor: 'pointer' }}>
            Try again
          </button>
        </div>
      </body>
    </html>
  )
}
