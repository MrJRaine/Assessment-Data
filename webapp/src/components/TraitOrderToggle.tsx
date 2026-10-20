'use client'

import { useEffect, useState } from 'react'
import { DEFAULT_TRAIT_ORDER, type TraitOrderMode } from '@/lib/writingTraits'

const STORAGE_KEY = 'writingTraitOrder'

// Per-viewer writing-trait order preference (COIL by default). Persisted in localStorage so it
// survives a refresh and is shared across the writing entry grid and the writing report. Storage can
// be blocked (private mode) — every access is guarded and falls back to the default.
export function useTraitOrder(): [TraitOrderMode, (m: TraitOrderMode) => void] {
  const [mode, setMode] = useState<TraitOrderMode>(DEFAULT_TRAIT_ORDER)
  // Restore on mount only (client-only → no SSR hydration mismatch; first paint is the default).
  useEffect(() => {
    try {
      const v = localStorage.getItem(STORAGE_KEY)
      if (v === 'COIL' || v === 'IOLC') setMode(v)
    } catch {
      /* storage blocked — keep the default */
    }
  }, [])
  const set = (m: TraitOrderMode) => {
    setMode(m)
    try {
      localStorage.setItem(STORAGE_KEY, m)
    } catch {
      /* storage blocked — preference just won't persist */
    }
  }
  return [mode, set]
}

// Compact segmented control: COIL | IOLC. Reuses the app's toggle / toggle-on button styles.
export function TraitOrderToggle({ mode, onChange }: { mode: TraitOrderMode; onChange: (m: TraitOrderMode) => void }) {
  return (
    <div className="trait-order-toggle" role="group" aria-label="Writing trait order">
      <span className="trait-order-label">Trait order:</span>
      {(['COIL', 'IOLC'] as const).map((m) => (
        <button
          key={m}
          type="button"
          className={mode === m ? 'toggle-on' : 'toggle'}
          aria-pressed={mode === m}
          onClick={() => onChange(m)}
        >
          {m}
        </button>
      ))}
    </div>
  )
}
