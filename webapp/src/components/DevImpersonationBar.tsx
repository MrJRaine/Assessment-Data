'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { setImpersonation, clearImpersonation } from './dev/impersonate-actions'
import type { ImpersonationTarget } from '@/lib/data'

/**
 * DEV-ONLY impersonation bar. Lets a developer run the app as any synthetic teacher/admin/analyst
 * while making how-to docs, without editing DEV_FAKE_UPN and restarting the container. Only
 * rendered in dev mode (see AppShell); the server actions and getCurrentUpn are both hard-gated to
 * dev, so this is inert on the entra/live path.
 */
export default function DevImpersonationBar({
  current,
  defaultUpn,
  impersonating,
  targets,
}: {
  current: string | null
  defaultUpn: string | null
  impersonating: boolean
  targets: ImpersonationTarget[]
}) {
  const router = useRouter()
  const [pending, startTransition] = useTransition()
  const [custom, setCustom] = useState('')

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

  return (
    <div className="dev-impersonate">
      <span className="dev-impersonate-tag">DEV</span>
      <span className="dev-impersonate-label">
        Viewing as <strong>{current ?? '—'}</strong>
        {impersonating ? (
          <span className="dev-impersonate-badge">impersonating</span>
        ) : (
          <span className="muted"> (default)</span>
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
          Reset to default{defaultUpn ? ` (${defaultUpn})` : ''}
        </button>
      )}

      {pending && (
        <span className="dev-impersonate-pending">
          <span className="spinner" />
          Switching…
        </span>
      )}
    </div>
  )
}
