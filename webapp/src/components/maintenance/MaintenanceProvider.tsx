'use client'

import { createContext, useCallback, useContext, useEffect, useRef, useState, useTransition } from 'react'
import { clearMaintenance } from '@/app/admin/maintenance/actions'

// Staged maintenance lifecycle, keyed off SERVER time (each client offsets its own clock).
//   none          — no window (or too far out to matter)
//   warn          — window approaching; entry still open, "will lock at T-5"
//   lockAfterSave — T-5..T-3: inputs lock AFTER the teacher's next save; Save still works; new loads redirect
//   fullLock      — T-3..T-1: inputs fully locked; heads-up that unsaved work auto-saves at T-1
//   autoSave      — T-1..T: trigger the quiet auto-save
//   down          — past T: server restarting
export type MaintenanceStage = 'none' | 'warn' | 'lockAfterSave' | 'fullLock' | 'autoSave' | 'down'

// Seconds-to-T thresholds (tunable).
const WARN_LEAD_MAX = 20 * 60 // start showing the banner at T-20
const T_LOCK_AFTER_SAVE = 5 * 60 // T-5
const T_FULL_LOCK = 3 * 60 // T-3
const T_AUTO_SAVE = 60 // T-1

function stageFor(secondsRemaining: number | null): MaintenanceStage {
  if (secondsRemaining == null || secondsRemaining > WARN_LEAD_MAX) return 'none'
  if (secondsRemaining > T_LOCK_AFTER_SAVE) return 'warn'
  if (secondsRemaining > T_FULL_LOCK) return 'lockAfterSave'
  if (secondsRemaining > T_AUTO_SAVE) return 'fullLock'
  if (secondsRemaining > 0) return 'autoSave'
  return 'down'
}

export interface MaintenanceState {
  stage: MaintenanceStage
  secondsRemaining: number | null // to T, server-corrected
  maintenanceAt: string | null // ISO UTC
  message: string | null
}

const Ctx = createContext<MaintenanceState>({ stage: 'none', secondsRemaining: null, maintenanceAt: null, message: null })

export function useMaintenance(): MaintenanceState {
  return useContext(Ctx)
}

export default function MaintenanceProvider({
  children,
  isSysAdmin = false,
  authSlot = null,
}: {
  children: React.ReactNode
  isSysAdmin?: boolean
  authSlot?: React.ReactNode // AuthArea (sign in / sign out), rendered on the down overlay
}) {
  // Raw window from the server + the clock offset measured at fetch time.
  const windowRef = useRef<{ atMs: number | null; message: string | null; offsetMs: number }>({
    atMs: null,
    message: null,
    offsetMs: 0,
  })
  const [state, setState] = useState<MaintenanceState>({
    stage: 'none',
    secondsRemaining: null,
    maintenanceAt: null,
    message: null,
  })

  const recompute = useCallback(() => {
    const { atMs, message, offsetMs } = windowRef.current
    if (atMs == null) {
      setState((s) => (s.stage === 'none' ? s : { stage: 'none', secondsRemaining: null, maintenanceAt: null, message: null }))
      return
    }
    const serverNowMs = Date.now() + offsetMs
    const secondsRemaining = Math.round((atMs - serverNowMs) / 1000)
    const stage = stageFor(secondsRemaining)
    setState({ stage, secondsRemaining, maintenanceAt: new Date(atMs).toISOString(), message })
  }, [])

  // Returns whether the status was actually refreshed, so the caller can retry SOON on failure
  // instead of waiting out a long (hidden-tab) interval and blowing past the warning window.
  const poll = useCallback(async (): Promise<boolean> => {
    try {
      const res = await fetch('/api/status', { cache: 'no-store' })
      if (!res.ok) return false
      const data: { maintenanceAt: string | null; serverNow: string; message: string | null } = await res.json()
      const offsetMs = new Date(data.serverNow).getTime() - Date.now()
      windowRef.current = {
        atMs: data.maintenanceAt ? new Date(data.maintenanceAt).getTime() : null,
        message: data.message,
        offsetMs,
      }
      recompute()
      return true
    } catch {
      /* transient — keep the last known state */
      return false
    }
  }, [recompute])

  // Poll on mount; cadence tightens as T nears. A 1s ticker drives the countdown + stage transitions
  // between polls (so the lock fires on time without waiting for the next fetch).
  useEffect(() => {
    let stopped = false
    poll()
    const tick = setInterval(() => {
      if (!stopped) recompute()
    }, 1000)
    // A HIDDEN tab polls rarely. Safe because polling only DISCOVERS a newly-set/cleared window —
    // once a window is known, the 1s ticker above drives every stage (lock, auto-save, overlay)
    // locally with no network. Worst case a hidden tab learns 8 min late, which still clears the
    // T-1 auto-save provided maintenance is scheduled >= 10 min out (the admin screen warns when
    // it isn't). Browsers throttle background timers anyway, so this mostly stops pointless wake-ups.
    const HIDDEN_MS = 480_000 // 8 min
    const RETRY_MS = 30_000 // a failed poll must NOT wait out a full hidden interval
    let pollTimer: ReturnType<typeof setTimeout>
    const isHidden = () => typeof document !== 'undefined' && document.hidden
    const schedule = (overrideDelay?: number) => {
      clearTimeout(pollTimer)
      const s = windowRef.current.atMs == null ? null : Math.round((windowRef.current.atMs - (Date.now() + windowRef.current.offsetMs)) / 1000)
      const visibleDelay = s != null && s <= 6 * 60 ? 4000 : 8000 // 4s when close, else 8s
      const delay = overrideDelay ?? (isHidden() ? HIDDEN_MS : visibleDelay)
      pollTimer = setTimeout(async () => {
        if (stopped) return
        const ok = await poll()
        schedule(ok ? undefined : RETRY_MS)
      }, delay)
    }
    schedule()

    // Coming back to the tab: refresh immediately so the teacher never sees a stale state (and a
    // cleared window lifts at once), then resume the normal visible cadence.
    const onVisibility = () => {
      if (stopped || isHidden()) {
        schedule() // went hidden — fall back to the slow cadence right away
        return
      }
      void poll().then(() => {
        if (!stopped) schedule()
      })
    }
    document.addEventListener('visibilitychange', onVisibility)

    return () => {
      stopped = true
      clearInterval(tick)
      clearTimeout(pollTimer)
      document.removeEventListener('visibilitychange', onVisibility)
    }
  }, [poll, recompute])

  // Sysadmin escape hatch: clear the window from wherever you are — including the locked/down screen,
  // where the nav is covered. Optimistically drop the local window so it lifts instantly for the
  // sysadmin; the server row is nulled and every other client picks it up on the next poll.
  const [clearing, startClear] = useTransition()
  const clearNow = useCallback(() => {
    startClear(async () => {
      try {
        const res = await clearMaintenance()
        if (res.ok) {
          windowRef.current = { atMs: null, message: null, offsetMs: windowRef.current.offsetMs }
          recompute()
        }
      } catch {
        /* leave state as-is; the poller will reconcile */
      }
    })
  }, [recompute])

  const admin = isSysAdmin ? { onClear: clearNow, clearing } : null

  return (
    <Ctx.Provider value={state}>
      <MaintenanceBanner state={state} admin={admin} />
      {children}
      {/* Past T: cover the app with a fixed overlay rather than unmounting it (avoids tearing down a
          grid mid auto-save). The poller keeps trying; the overlay lifts when a sysadmin EXPLICITLY
          clears the window — there is no auto-expire, so a long maintenance job is never cut short. */}
      {state.stage === 'down' ? <MaintenanceDown message={state.message} admin={admin} authSlot={authSlot} /> : null}
    </Ctx.Provider>
  )
}

type AdminClear = { onClear: () => void; clearing: boolean } | null

function MaintenanceDown({
  message,
  admin,
  authSlot,
}: {
  message: string | null
  admin: AdminClear
  authSlot: React.ReactNode
}) {
  return (
    <div className="maint-down-screen" role="alert">
      <div className="maint-down-card">
        <h1>We&rsquo;ll be right back</h1>
        <p>{message || 'The Short Cycles of Response app is being updated. Please check back in a few minutes — this page will return automatically.'}</p>
        {admin ? (
          <button className="btn" style={{ marginTop: '1.25rem' }} disabled={admin.clearing} onClick={admin.onClear}>
            {admin.clearing ? 'Clearing…' : 'Clear maintenance now'}
          </button>
        ) : null}
        {/* Identity controls so a non-sysadmin (or signed-out) sysadmin can switch accounts to clear
            it — otherwise the overlay would trap them with no way to reach sign-in. */}
        <div className="maint-down-auth">
          {authSlot}
          {!admin ? <span className="muted small">Sign in as a system administrator to clear maintenance.</span> : null}
        </div>
      </div>
    </div>
  )
}

function fmtClock(iso: string | null): string {
  if (!iso) return ''
  try {
    return new Intl.DateTimeFormat('en-CA', {
      hour: 'numeric',
      minute: '2-digit',
      timeZone: 'America/Halifax',
    }).format(new Date(iso))
  } catch {
    return ''
  }
}

function mmss(total: number): string {
  const s = Math.max(0, total)
  const m = Math.floor(s / 60)
  const r = s % 60
  return `${m}:${String(r).padStart(2, '0')}`
}

function MaintenanceBanner({ state, admin }: { state: MaintenanceState; admin: AdminClear }) {
  const { stage, secondsRemaining, maintenanceAt, message } = state
  if (stage === 'none') return null

  const at = fmtClock(maintenanceAt)
  const countdown = secondsRemaining != null ? mmss(secondsRemaining) : ''

  let text: string
  let tone: 'warn' | 'lock' | 'down' = 'warn'
  switch (stage) {
    case 'warn':
      text = `Scheduled maintenance at ${at} — data entry will lock a few minutes beforehand. Now is a good time to save your work. (${countdown})`
      tone = 'warn'
      break
    case 'lockAfterSave':
      text = `Maintenance at ${at}. Inputs will lock after your next save — save when you're ready. (${countdown})`
      tone = 'warn'
      break
    case 'fullLock':
      text = `Data entry is paused for maintenance at ${at}. Anything unsaved will be saved for you before the restart. (${countdown})`
      tone = 'lock'
      break
    case 'autoSave':
      text = `Saving your work and restarting for maintenance… (${countdown})`
      tone = 'down'
      break
    default: // down
      text = message || 'The server is restarting for maintenance. Please try again in a few minutes.'
      tone = 'down'
  }

  return (
    <div className={`maint-banner maint-${tone}`} role="alert">
      {message && stage !== 'down' ? <strong>{message} </strong> : null}
      {text}
      {admin ? (
        <button className="maint-clear-btn" disabled={admin.clearing} onClick={admin.onClear}>
          {admin.clearing ? 'Clearing…' : 'Clear now'}
        </button>
      ) : null}
    </div>
  )
}
