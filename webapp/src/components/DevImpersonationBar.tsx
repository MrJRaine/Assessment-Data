'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { setImpersonation, clearImpersonation } from './dev/impersonate-actions'
import type { ImpersonationTarget } from '@/lib/data'

const COLLAPSE_COOKIE = 'impersonate_bar_collapsed'

/**
 * Impersonation bar. A sysadmin (or any dev-mode user) can run the app as any staff member — for
 * making how-to docs or supporting a user. COLLAPSIBLE: collapsing hides it to a tiny corner dot and
 * persists (cookie), so it stays out of screenshots across navigations until expanded again.
 * Rendered only when the caller may impersonate (see AppShell); the server actions AND getCurrentUpn
 * are both gated to a real sysadmin, so this is inert for anyone else.
 */
export default function DevImpersonationBar({
  current,
  realUpn,
  impersonating,
  targets,
  initialCollapsed,
}: {
  current: string | null
  realUpn: string | null
  impersonating: boolean
  targets: ImpersonationTarget[]
  initialCollapsed: boolean
}) {
  const router = useRouter()
  const [pending, startTransition] = useTransition()
  const [custom, setCustom] = useState('')
  const [collapsed, setCollapsed] = useState(initialCollapsed)

  // Persist collapse to a cookie so AppShell renders the right state server-side next navigation
  // (no flash) and it survives page loads — the point is clean, bar-free screenshots.
  function persistCollapsed(next: boolean) {
    setCollapsed(next)
    try {
      document.cookie = `${COLLAPSE_COOKIE}=${next ? '1' : '0'}; path=/; max-age=${60 * 60 * 24 * 90}; samesite=lax`
    } catch {
      /* cookies blocked — state still applies for this view */
    }
  }

  function apply(upn: string) {
    const clean = upn.trim()
    if (!clean) return
    startTransition(async () => {
      await setImpersonation(clean)
      router.refresh()
    })
  }

  function reset() {
    startTransition(async () => {
      await clearImpersonation()
      setCustom('')
      router.refresh()
    })
  }

  if (collapsed) {
    return (
      <button
        type="button"
        className={`dev-impersonate-fab${impersonating ? ' is-impersonating' : ''}`}
        onClick={() => persistCollapsed(false)}
        aria-label={impersonating ? `Impersonating ${current} — show bar` : 'Show impersonation bar'}
        title={impersonating ? `Impersonating ${current}` : 'Impersonation'}
      >
        {impersonating ? '●' : '○'}
      </button>
    )
  }

  return (
    <div className="dev-impersonate">
      <span className="dev-impersonate-tag">VIEW AS</span>
      <span className="dev-impersonate-label">
        Viewing as <strong>{current ?? '—'}</strong>
        {impersonating ? (
          <span className="dev-impersonate-badge">impersonating</span>
        ) : (
          <span className="muted"> (you)</span>
        )}
      </span>

      <select
        className="dev-impersonate-select"
        value=""
        disabled={pending}
        onChange={(e) => {
          if (e.target.value) apply(e.target.value)
        }}
        aria-label="Impersonate a staff member"
      >
        <option value="" disabled>
          Impersonate…
        </option>
        {targets.map((t) => (
          <option key={t.upn} value={t.upn}>
            {t.fullName}
            {t.accessLevel ? ` · ${t.accessLevel}` : ''}
            {t.sections > 0 ? ` · ${t.sections} section${t.sections === 1 ? '' : 's'}` : ''} — {t.upn}
          </option>
        ))}
      </select>

      <form
        className="dev-impersonate-custom"
        onSubmit={(e) => {
          e.preventDefault()
          apply(custom)
        }}
      >
        <input
          type="text"
          placeholder="or type any UPN"
          value={custom}
          onChange={(e) => setCustom(e.target.value)}
          disabled={pending}
          className="dev-impersonate-input"
        />
        <button type="submit" className="btn-ghost" disabled={pending || !custom.trim()}>
          Go
        </button>
      </form>

      {impersonating && (
        <button type="button" className="btn-ghost" onClick={reset} disabled={pending}>
          Stop{realUpn ? ` (back to ${realUpn})` : ''}
        </button>
      )}

      {pending && (
        <span className="dev-impersonate-pending">
          <span className="spinner" />
          Switching…
        </span>
      )}

      <button
        type="button"
        className="dev-impersonate-collapse"
        onClick={() => persistCollapsed(true)}
        aria-label="Hide impersonation bar (keeps it out of screenshots)"
        title="Hide — stays hidden until you click the corner dot"
      >
        Hide ✕
      </button>
    </div>
  )
}
