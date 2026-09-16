'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { useMaintenance } from './MaintenanceProvider'

/**
 * Maintenance-aware entry lock for the reading / writing / math grids.
 * Returns `inputsLocked` (thread into input `disabled`) and `markSaved` (call after a successful
 * save so the T-5 "lock after next save" stage actually locks). Also fires a QUIET one-shot auto-save
 * at T-1 if there are unsaved changes, and installs a beforeunload guard while dirty.
 *
 * Save itself is never blocked (the banner locks INPUT, not Save) so staged edits can still flush.
 */
export function useEntryLock({ dirty, onSave }: { dirty: boolean; onSave: () => void }) {
  const { stage } = useMaintenance()
  const [lockedAfterSave, setLockedAfterSave] = useState(false)
  const autoSavedRef = useRef(false)

  const inputsLocked =
    stage === 'fullLock' ||
    stage === 'autoSave' ||
    stage === 'down' ||
    (stage === 'lockAfterSave' && lockedAfterSave)

  // Reset when the window clears / hasn't reached the lock stages.
  useEffect(() => {
    if (stage === 'none' || stage === 'warn') {
      setLockedAfterSave(false)
      autoSavedRef.current = false
    }
  }, [stage])

  // Quiet auto-save at T-1 — fire once if there's unsaved work.
  useEffect(() => {
    if (stage === 'autoSave' && dirty && !autoSavedRef.current) {
      autoSavedRef.current = true
      onSave()
    }
  }, [stage, dirty, onSave])

  // beforeunload guard while there are unsaved changes (belt + suspenders with the auto-save).
  useEffect(() => {
    if (!dirty) return
    const handler = (e: BeforeUnloadEvent) => {
      e.preventDefault()
      e.returnValue = ''
    }
    window.addEventListener('beforeunload', handler)
    return () => window.removeEventListener('beforeunload', handler)
  }, [dirty])

  // Call after a successful save: at T-5 (lockAfterSave) the next save is what locks input.
  const markSaved = useCallback(() => {
    setLockedAfterSave((prev) => prev || stage === 'lockAfterSave')
  }, [stage])

  return { inputsLocked, markSaved }
}
