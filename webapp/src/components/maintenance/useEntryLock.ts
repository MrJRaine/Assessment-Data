'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { useMaintenance, useMaintenanceControls } from './MaintenanceProvider'

// Sticky "locked after save" flag, keyed by the window's T so it persists across navigation (same
// section or between sections) for the rest of THAT window, and a past window never locks a new one.
const LOCK_KEY = 'maintLockedAfterSave'

/**
 * Maintenance-aware entry lock for the reading / writing / math / programming grids.
 * Returns `inputsLocked` (thread into input `disabled`) and `markSaved` (call after a successful
 * save so the T-5 "lock after next save" stage actually locks — and STAYS locked across navigation
 * for the rest of the window). Also fires a QUIET one-shot auto-save at T-1 if there are unsaved
 * changes, and installs a beforeunload guard while dirty. Save itself is never blocked.
 */
export function useEntryLock({ dirty, onSave }: { dirty: boolean; onSave: () => void }) {
  const { stage, maintenanceAt } = useMaintenance()
  const { registerUnsavedEntry } = useMaintenanceControls()
  const [lockedAfterSave, setLockedAfterSave] = useState(false)
  const autoSavedRef = useRef(false)

  // Restore the sticky flag on mount / when the window changes; clear it when the window ends.
  useEffect(() => {
    if (stage === 'none' || stage === 'warn') {
      setLockedAfterSave(false)
      autoSavedRef.current = false
      try {
        sessionStorage.removeItem(LOCK_KEY)
      } catch {
        /* private mode — nothing to clear */
      }
      return
    }
    try {
      if (maintenanceAt && sessionStorage.getItem(LOCK_KEY) === maintenanceAt) setLockedAfterSave(true)
    } catch {
      /* ignore */
    }
  }, [stage, maintenanceAt])

  const inputsLocked =
    stage === 'fullLock' ||
    stage === 'autoSave' ||
    stage === 'down' ||
    (stage === 'lockAfterSave' && lockedAfterSave)

  // Quiet auto-save at T-1 — fire once if there's unsaved work. Best-effort (never crash the page).
  useEffect(() => {
    if (stage === 'autoSave' && dirty && !autoSavedRef.current) {
      autoSavedRef.current = true
      try {
        onSave()
      } catch {
        /* auto-save is a safety net; a failure must not take down the app */
      }
    }
  }, [stage, dirty, onSave])

  // beforeunload guard while there are unsaved changes.
  useEffect(() => {
    if (!dirty) return
    const handler = (e: BeforeUnloadEvent) => {
      e.preventDefault()
      e.returnValue = ''
    }
    window.addEventListener('beforeunload', handler)
    return () => window.removeEventListener('beforeunload', handler)
  }, [dirty])

  // Tell the maintenance provider this tab is holding unsaved entry work. That keeps the background
  // maintenance heartbeat (and therefore the T-1 auto-save) alive for THIS tab even when it's hidden,
  // while tabs with nothing to save let the provider drop the heartbeat. Registered only while dirty;
  // the returned release fn decrements on save/clean or unmount.
  useEffect(() => {
    if (!dirty) return
    return registerUnsavedEntry()
  }, [dirty, registerUnsavedEntry])

  // Call after a successful save: from T-5 on, the next save locks input — and it stays locked in
  // every section for the rest of the window (persisted, so navigating away/back can't re-open it).
  const markSaved = useCallback(() => {
    if (stage === 'lockAfterSave' || stage === 'fullLock' || stage === 'autoSave') {
      setLockedAfterSave(true)
      try {
        if (maintenanceAt) sessionStorage.setItem(LOCK_KEY, maintenanceAt)
      } catch {
        /* ignore */
      }
    }
  }, [stage, maintenanceAt])

  return { inputsLocked, markSaved }
}
