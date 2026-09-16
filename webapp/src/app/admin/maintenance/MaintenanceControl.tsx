'use client'

import { useRouter } from 'next/navigation'
import { useState, useTransition } from 'react'
import { startMaintenance, clearMaintenance } from './actions'

const QUICK = [5, 10, 15, 30]

function fmt(iso: string): string {
  try {
    return new Intl.DateTimeFormat('en-CA', {
      dateStyle: 'medium',
      timeStyle: 'short',
      timeZone: 'America/Halifax',
    }).format(new Date(iso))
  } catch {
    return iso
  }
}

export default function MaintenanceControl({
  current,
}: {
  current: { maintenanceAt: string | null; message: string | null }
}) {
  const router = useRouter()
  const [minutes, setMinutes] = useState(10)
  const [message, setMessage] = useState('')
  const [busy, start] = useTransition()
  const [error, setError] = useState<string | null>(null)

  const active = current.maintenanceAt != null

  function schedule() {
    setError(null)
    start(async () => {
      const res = await startMaintenance(minutes, message)
      if (!res.ok) setError(res.error ?? 'Could not schedule maintenance.')
      else router.refresh()
    })
  }

  function clear() {
    setError(null)
    start(async () => {
      const res = await clearMaintenance()
      if (!res.ok) setError(res.error ?? 'Could not clear maintenance.')
      else router.refresh()
    })
  }

  return (
    <div className="maint-admin">
      <div className={active ? 'maint-status maint-status-on' : 'maint-status'}>
        {active ? (
          <>
            <strong>Maintenance scheduled</strong> for <strong>{fmt(current.maintenanceAt!)}</strong>. Entry locks 5 minutes
            before; unsaved work auto-saves 1 minute before. All open tabs are counting down.
            {current.message ? <div className="muted" style={{ marginTop: '0.4rem' }}>Message: “{current.message}”</div> : null}
          </>
        ) : (
          <>No maintenance scheduled. Entry is open as normal.</>
        )}
      </div>

      <div className="maint-form">
        <p className="filter-label">Lock down in</p>
        <div className="grade-chips">
          {QUICK.map((m) => (
            <button key={m} className={`grade-chip${minutes === m ? ' on' : ''}`} disabled={busy} onClick={() => setMinutes(m)}>
              {m} min
            </button>
          ))}
          <label className="maint-custom">
            <input
              type="number"
              min={1}
              max={240}
              value={minutes}
              disabled={busy}
              onChange={(e) => setMinutes(Math.max(1, Math.min(240, Number(e.target.value) || 1)))}
            />
            <span className="muted">minutes from now</span>
          </label>
        </div>

        <p className="filter-label">Message (optional)</p>
        <input
          className="maint-msg"
          type="text"
          maxLength={200}
          placeholder="e.g. Applying a quick fix to the writing screen."
          value={message}
          disabled={busy}
          onChange={(e) => setMessage(e.target.value)}
        />

        <div className="actions" style={{ marginTop: '1rem' }}>
          <button className="btn" onClick={schedule} disabled={busy}>
            {busy ? 'Working…' : active ? 'Reschedule' : `Start countdown (${minutes} min)`}
          </button>
          {active ? (
            <button className="btn-ghost" onClick={clear} disabled={busy}>
              Cancel / all clear
            </button>
          ) : null}
        </div>
        {error ? <p className="save-errors" style={{ color: 'var(--danger)' }}>{error}</p> : null}
      </div>

      <p className="muted small" style={{ marginTop: '1rem' }}>
        The countdown is server-synced, so every open tab locks at the same real time regardless of their laptop clock.
        After the swap, click <strong>Cancel / all clear</strong> to bring the app back immediately (it also self-clears
        about 10 minutes past the scheduled time).
      </p>
    </div>
  )
}
