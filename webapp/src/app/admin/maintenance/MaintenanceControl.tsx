'use client'

import { useRouter } from 'next/navigation'
import { useState, useTransition } from 'react'
import { startMaintenance, clearMaintenance } from './actions'

// All quick picks are >= SHORT_NOTICE_MIN, so the short-notice warning only ever fires from the
// custom field (5 min was dropped — it's below the safe threshold for background tabs).
const QUICK = [10, 15, 30, 60]
// Below this many minutes, a tab sitting in the BACKGROUND may not learn about the window in time to
// run its 1-minute-before auto-save: hidden tabs poll every ~8 min, and browsers throttle background
// timers further. Deliberately NOT enforced (testing needs short windows) — the sysadmin is warned and
// asked to confirm instead. See memory project_perf_qol_backlog / the MaintenanceProvider comment.
const SHORT_NOTICE_MIN = 10

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
  const [confirmShort, setConfirmShort] = useState(false)

  const active = current.maintenanceAt != null
  const shortNotice = minutes < SHORT_NOTICE_MIN

  // Changing the lead time re-arms the warning, so a confirmation can't carry over to a new value.
  function pickMinutes(m: number) {
    setMinutes(m)
    setConfirmShort(false)
  }

  function schedule() {
    setError(null)
    if (shortNotice && !confirmShort) {
      setConfirmShort(true) // warn first; the sysadmin must explicitly accept the risk
      return
    }
    setConfirmShort(false)
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
            <button key={m} className={`grade-chip${minutes === m ? ' on' : ''}`} disabled={busy} onClick={() => pickMinutes(m)}>
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
              onChange={(e) => pickMinutes(Math.max(1, Math.min(240, Number(e.target.value) || 1)))}
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
          <button className="btn" onClick={schedule} disabled={busy || confirmShort}>
            {busy ? 'Working…' : active ? 'Reschedule' : `Start countdown (${minutes} min)`}
          </button>
          {active ? (
            <button className="btn-ghost" onClick={clear} disabled={busy}>
              Cancel / all clear
            </button>
          ) : null}
        </div>

        {confirmShort ? (
          <div className="notice notice-error" style={{ marginTop: '0.75rem' }}>
            <div className="notice-title">
              Less than {SHORT_NOTICE_MIN} minutes’ notice — unsaved work could be lost
            </div>
            <div>
              A tab sitting in the <strong>background</strong> only checks for maintenance every few minutes, and
              browsers slow background tabs down further. With {minutes} minute{minutes === 1 ? '' : 's'}’ notice, a
              teacher who has unsaved entries on a background tab may not get the automatic save before the swap — and
              that work would be lost. Tabs they’re actively using are fine.
            </div>
            <div className="actions" style={{ marginTop: '0.6rem' }}>
              <button className="btn" onClick={schedule} disabled={busy}>
                {busy ? 'Working…' : `Schedule anyway (${minutes} min)`}
              </button>
              <button className="btn-ghost" onClick={() => setConfirmShort(false)} disabled={busy}>
                Back
              </button>
            </div>
          </div>
        ) : null}

        {error ? <p className="save-errors" style={{ color: 'var(--danger)' }}>{error}</p> : null}
      </div>

      <p className="muted small" style={{ marginTop: '1rem' }}>
        The countdown is server-synced, so every open tab locks at the same real time regardless of their laptop clock.
        The app stays down until you <strong>explicitly</strong> clear it — it will <strong>not</strong> come back on its
        own, so a long job (a batch of SQL deploys, say) can’t be interrupted by teachers writing against a half-migrated
        warehouse. When everything is done, click <strong>Cancel / all clear</strong> to bring it back. You can also clear
        from the banner or the maintenance screen itself if you’re locked out.
      </p>
    </div>
  )
}
