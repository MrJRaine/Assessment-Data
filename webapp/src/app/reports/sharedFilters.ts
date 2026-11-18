'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import type { Tri } from './rollupModel'

// ── Shared report filters (user ask 2026-11-18) ───────────────────────────────────────────────────
// ONE saved filter set per browser tab (sessionStorage — clears when the tab closes), read and
// written by every report tree (Reading / Writing / RWM / Math) and the Reading/Writing Student
// list, so a selection carries across cycle changes AND across reports. Before this the trees held
// their filters in component state only, and every cycle change remounts them (key={cycle}) — so the
// selection reverted to defaults.
//
// What carries (ruled 2026-11-18): Grade range, Gender, both Self-ID filters — everywhere. Language of
// Assessment — Reading/Writing only (Math/RWM have none). Blanks mode — Math/RWM only (a scoring mode:
// "Reset filters" never touches it). The filter panel's open/closed state rides along.
//
// A report can only APPLY what it can show, so each one reads the saved values through its own
// options without overwriting them:
//  • Grade — a bound is saved ONLY when it differs from the report's own extreme (null = "no bound"),
//    then snapped into each report's available grades (Math is P–5, Writing runs further). Picking
//    Grade 7–9 in Writing and opening Math shows Math's nearest grade; going back restores 7–9.
//  • Gender / Self-ID — applied only when this report's feed offers that filter group; otherwise the
//    saved value waits untouched (a hidden filter must never silently narrow the data).

const KEY = 'reportFilters'
export type SharedLang = 'All' | 'EN' | 'FR'
export type SharedBlank = 'exclude' | 'zero'
export interface SharedFilters {
  gradeMin?: number | null
  gradeMax?: number | null
  gender?: string
  african?: Tri
  indigenous?: Tri
  lang?: SharedLang
  blankMode?: SharedBlank
  open?: boolean
}

export function readSharedFilters(): SharedFilters {
  try {
    const raw = sessionStorage.getItem(KEY)
    const p = raw ? (JSON.parse(raw) as SharedFilters) : {}
    return p && typeof p === 'object' ? p : {}
  } catch {
    return {} // private mode / blocked storage — filters just won't carry
  }
}

export function writeSharedFilters(patch: SharedFilters): void {
  try {
    sessionStorage.setItem(KEY, JSON.stringify({ ...readSharedFilters(), ...patch }))
  } catch {
    /* private mode / storage blocked — filters just won't carry */
  }
}

const isTri = (v: unknown): v is Tri => v === 'All' || v === 'Yes' || v === 'No'

/** Snap a saved lower bound into this report's available grade ranks (ascending). */
export function snapMin(saved: number | null | undefined, ranks: number[]): number {
  if (ranks.length === 0) return 0
  if (saved == null) return ranks[0]
  return ranks.find((r) => r >= saved) ?? ranks[ranks.length - 1]
}
/** Snap a saved upper bound into this report's available grade ranks (ascending). */
export function snapMax(saved: number | null | undefined, ranks: number[]): number {
  if (ranks.length === 0) return 0
  if (saved == null) return ranks[ranks.length - 1]
  return [...ranks].reverse().find((r) => r <= saved) ?? ranks[0]
}

/**
 * The shared filter state, resolved against ONE report's options.
 * @param ranks      this report's available grade ranks, ascending
 * @param genderOpts this report's gender options ([] / one value = the group isn't offered)
 * @param hasSelfID  whether this report's feed carries the Self-ID columns
 */
export function useSharedFilters(ranks: number[], genderOpts: string[], hasSelfID: boolean) {
  const [saved, setSaved] = useState<SharedFilters>({})
  // Restore once on mount (client-only → no SSR hydration mismatch).
  useEffect(() => { setSaved(readSharedFilters()) }, [])
  const update = useCallback((patch: SharedFilters) => {
    setSaved((prev) => ({ ...prev, ...patch }))
    writeSharedFilters(patch)
  }, [])

  const minAvail = ranks.length ? ranks[0] : 0
  const maxAvail = ranks.length ? ranks[ranks.length - 1] : 0
  const gradeMinRank = snapMin(saved.gradeMin, ranks)
  const gradeMaxRank = snapMax(saved.gradeMax, ranks)
  const genderOffered = genderOpts.length > 1
  const gender = genderOffered && saved.gender && genderOpts.includes(saved.gender) ? saved.gender : 'All'
  const african: Tri = hasSelfID && isTri(saved.african) ? saved.african : 'All'
  const indigenous: Tri = hasSelfID && isTri(saved.indigenous) ? saved.indigenous : 'All'
  const lang: SharedLang = saved.lang === 'EN' || saved.lang === 'FR' ? saved.lang : 'All'
  const blankMode: SharedBlank = saved.blankMode === 'zero' ? 'zero' : 'exclude'
  const filtersOpen = saved.open === true

  return useMemo(() => ({
    gradeMinRank, gradeMaxRank, gender, african, indigenous, lang, blankMode, filtersOpen,
    minAvail, maxAvail,
    // A bound equal to this report's extreme is "no bound" — saved as null so it doesn't follow the
    // viewer into a report with a wider grade span as a real filter.
    setGradeMinRank: (v: number) => update({ gradeMin: v === minAvail ? null : v }),
    setGradeMaxRank: (v: number) => update({ gradeMax: v === maxAvail ? null : v }),
    setGender: (v: string) => update({ gender: v }),
    setAfrican: (v: Tri) => update({ african: v }),
    setIndigenous: (v: Tri) => update({ indigenous: v }),
    setLang: (v: SharedLang) => update({ lang: v }),
    setBlankMode: (v: SharedBlank) => update({ blankMode: v }),
    setFiltersOpen: (v: boolean) => update({ open: v }),
    /** True when a demographic filter is narrowing THIS report (language / blanks not included). */
    anyDemo: gradeMinRank !== minAvail || gradeMaxRank !== maxAvail || gender !== 'All' || african !== 'All' || indigenous !== 'All',
    /** Clears the demographic filters everywhere. Language and Blanks are the caller's to reset or keep. */
    resetDemo: () => update({ gradeMin: null, gradeMax: null, gender: 'All', african: 'All', indigenous: 'All' }),
  }), [gradeMinRank, gradeMaxRank, gender, african, indigenous, lang, blankMode, filtersOpen, minAvail, maxAvail, update])
}
