'use client'

import Link from 'next/link'
import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { CardLink } from '@/components/ui'
import type { TeacherGroup } from '@/lib/data'

// Persist the oversight lens/grade/school filters for the tab session, so an analyst who
// filters to a school, opens a group, and hits Back doesn't lose their selection. sessionStorage
// (not a cookie): per-tab, survives navigation, clears when the tab closes, no server round-trip.
const FILTER_KEY = 'oversightGroupFilters'
type PersistedFilters = { lens?: 'Homeroom' | 'Section' | 'Grade'; grades?: string[]; schools?: string[] }
function readPersistedFilters(): PersistedFilters {
  try {
    const raw = sessionStorage.getItem(FILTER_KEY)
    return raw ? (JSON.parse(raw) as PersistedFilters) : {}
  } catch {
    return {}
  }
}
// Restore a saved selection, but only for values still present; fall back to "all" if the saved
// set would hide everything (e.g. a different cycle's grades), so we never restore an empty screen.
function restoreSet(available: string[], saved?: string[]): Set<string> {
  if (!saved) return new Set(available)
  const keep = available.filter((v) => saved.includes(v))
  return new Set(keep.length ? keep : available)
}

/**
 * Shared choose-a-group picker (Data Entry now; Programming reuses it in Phase 2).
 * Two sections driven by the group Scope:
 *   - "My classes" (Scope='Taught') — the caller's OWN homerooms/sections, always shown.
 *     A dual-role admin who teaches gets these too (the teacher rule fires for all roles).
 *   - "All groups" (Scope='Oversight') — above-teacher only: a [Homeroom | Section] lens
 *     toggle over full P-RG, a grade filter, and the collapsible school filter.
 * Generic via `hrefBase` (client builds `${hrefBase}/${key}`) + `metaSuffix`, so no
 * server->client function props are needed.
 */

const GRADE_ORDER: Record<string, number> = {
  PP: -1, P: 0, '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6,
  '7': 7, '8': 8, '9': 9, '10': 10, '11': 11, '12': 12, RG: 13,
}
const gradeLabel = (g: string) => (g === 'P' ? 'Primary' : g === 'PP' ? 'Pre-Primary' : /^\d+$/.test(g) ? `Gr ${g}` : g)

/**
 * `mode` picks how the groups are organised:
 *   'lens'   — Programming: Homeroom / Section / Grade views of the same students (the toggle).
 *   'course' — Data Entry: every group IS a mapped course section, so there is nothing to toggle
 *              between. Cards are headed by the course's LANGUAGE instead, which is how the
 *              English/French split is expressed now that the language comes from the course
 *              rather than a toggle. The lens filter would hide every card here (groupType is
 *              always 'Course'), so course mode bypasses it.
 */
export default function GroupCards({
  groups,
  hrefBase,
  metaSuffix = 'entered',
  metaMode = 'progress',
  mode = 'lens',
  subject,
}: {
  groups: TeacherGroup[]
  hrefBase: string
  metaSuffix?: string
  metaMode?: 'progress' | 'count' // 'count' = just "N students" (reports pickers have no progress)
  mode?: 'lens' | 'course'
  subject?: string // entry subject; 'math' switches the card meta to "N/M started · K done"
}) {
  const isMath = (subject ?? '').toLowerCase() === 'math' // route passes 'Math' (from AssessmentType)
  const taught = groups.filter((g) => g.scope === 'Taught')
  const oversight = groups.filter((g) => g.scope === 'Oversight')

  // Carry the group's own metadata (windows, label, language, school) on the link so the roster page
  // can SKIP the ~1s getTeacherGroups round-trip it would otherwise fire just to re-resolve them.
  // Safe: the roster TVF still authorizes by section, so a spoofed/stale param returns no students,
  // never someone else's. Combined-roster links (below) deliberately omit these and fall back.
  const cardHref = (g: TeacherGroup) => {
    const qs = new URLSearchParams()
    if (g.windowIds?.length) qs.set('w', g.windowIds.join(','))
    qs.set('label', g.label)
    if (g.language) qs.set('lang', g.language)
    if (g.schoolName) qs.set('school', g.schoolName)
    return `${hrefBase}/${encodeURIComponent(g.key)}?${qs.toString()}`
  }

  const card = (g: TeacherGroup) => (
    <CardLink
      key={`${g.scope}-${g.groupType}-${g.key}`}
      href={cardHref(g)}
      title={g.label}
      // Oversight cards say WHOSE class this is — the whole point of showing someone else's section.
      desc={[g.scope === 'Oversight' ? g.teacherNames : null, g.schoolName].filter(Boolean).join(' · ') || undefined}
      meta={
        isMath
          ? `${g.enteredCount}/${g.applicableCount} started · ${g.doneCount} done`
          : metaMode === 'count'
            ? `${g.applicableCount} ${metaSuffix}`
            : `${g.enteredCount}/${g.applicableCount} ${metaSuffix}`
      }
    />
  )

  return (
    <>
      {taught.length > 0 && (
        <section>
          <h2 className="section-heading">My classes</h2>
          {mode === 'course' ? <ByLanguage groups={taught} card={card} hrefBase={hrefBase} isMath={isMath} /> : <div className="card-grid">{taught.map(card)}</div>}
        </section>
      )}

      {oversight.length > 0 && (
        <Oversight groups={oversight} card={card} showHeading={taught.length > 0} mode={mode} hrefBase={hrefBase} isMath={isMath} />
      )}
    </>
  )
}

/**
 * Course sections grouped under a language heading, mirroring how /enter heads its cards by subject.
 * A single-language set gets no heading (nothing to distinguish). Sections whose course has no
 * language on file fall under "Other" rather than vanishing.
 */
function ByLanguage({
  groups,
  card,
  hrefBase,
  isMath = false,
}: {
  groups: TeacherGroup[]
  card: (g: TeacherGroup) => ReactNode
  hrefBase: string
  isMath?: boolean
}) {
  const langs = [...new Set(groups.map((g) => g.language ?? 'Other'))].sort()
  return (
    <>
      {langs.map((lang) => (
        <LanguageBlock
          key={lang}
          // A single-language set still gets a block, just no heading — nothing to distinguish.
          heading={langs.length > 1 ? lang : null}
          groups={groups.filter((g) => (g.language ?? 'Other') === lang)}
          card={card}
          hrefBase={hrefBase}
          isMath={isMath}
        />
      ))}
    </>
  )
}

/**
 * One language's course sections, with opt-in multi-select.
 *
 * Multi-select is scoped to a single language BLOCK by construction: a teacher with an ELA and an
 * FLA section can't combine them, because the entry language comes from the course and one roster
 * can only be in one language. Selecting several opens them as a combined roster — the teacher who
 * takes three Primary FLA sections marks all of them in one pass instead of three.
 */
function LanguageBlock({
  heading,
  groups,
  card,
  hrefBase,
  isMath = false,
}: {
  heading: string | null
  groups: TeacherGroup[]
  card: (g: TeacherGroup) => ReactNode
  hrefBase: string
  isMath?: boolean
}) {
  const [picking, setPicking] = useState(false)
  const [picked, setPicked] = useState<Set<string>>(new Set())

  // Nothing to combine with — don't offer the mode at all.
  const canCombine = groups.length > 1

  const toggle = (key: string) =>
    setPicked((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })

  const stop = () => {
    setPicking(false)
    setPicked(new Set())
  }

  // Keys travel comma-joined in the existing [groupKey] segment; the roster splits them back out.
  const combinedHref = `${hrefBase}/${encodeURIComponent([...picked].join(','))}`
  const total = groups.filter((g) => picked.has(g.key)).reduce((a, g) => a + g.applicableCount, 0)

  return (
    <div className="lang-block">
      {(heading || canCombine) && (
        <div className="lang-block-head">
          {heading && <h3 className="section-subheading">{heading}</h3>}
          {canCombine &&
            (picking ? (
              <button type="button" className="btn-ghost" onClick={stop}>
                Cancel
              </button>
            ) : (
              <button type="button" className="btn-ghost" onClick={() => setPicking(true)}>
                Select Multiple Sections
              </button>
            ))}
        </div>
      )}

      {picking ? (
        <>
          <div className="card-grid">
            {groups.map((g) => (
              <label key={g.key} className={`pick-card${picked.has(g.key) ? ' on' : ''}`}>
                <input type="checkbox" checked={picked.has(g.key)} onChange={() => toggle(g.key)} />
                <span className="pick-card-body">
                  <span className="pick-card-title">{g.label}</span>
                  <span className="muted small">
                    {[g.scope === 'Oversight' ? g.teacherNames : null, g.schoolName].filter(Boolean).join(' · ')}
                  </span>
                  <span className="muted small">
                    {isMath
                      ? `${g.enteredCount}/${g.applicableCount} started · ${g.doneCount} done`
                      : `${g.enteredCount}/${g.applicableCount} done`}
                  </span>
                </span>
              </label>
            ))}
          </div>
          <div className="pick-actions">
            <button type="button" className="btn-ghost" onClick={() => setPicked(new Set(groups.map((g) => g.key)))}>
              Select all
            </button>
            <button type="button" className="btn-ghost" onClick={() => setPicked(new Set())}>
              Clear all
            </button>
            {picked.size > 0 ? (
              <Link href={combinedHref} className="btn-primary">
                Open {picked.size} {picked.size === 1 ? 'class' : 'classes'} ({total} students)
              </Link>
            ) : (
              <span className="muted small">Tick the classes you want to enter together.</span>
            )}
          </div>
        </>
      ) : (
        <div className="card-grid">{groups.map(card)}</div>
      )}
    </div>
  )
}

function Oversight({
  groups,
  card,
  showHeading,
  hrefBase,
  mode,
  isMath = false,
}: {
  groups: TeacherGroup[]
  card: (g: TeacherGroup) => ReactNode
  showHeading: boolean
  hrefBase: string
  mode: 'lens' | 'course'
  isMath?: boolean
}) {
  const byCourse = mode === 'course'
  const hasSections = useMemo(() => !byCourse && groups.some((g) => g.groupType === 'Section'), [groups, byCourse])
  const hasGrades = useMemo(() => !byCourse && groups.some((g) => g.groupType === 'Grade'), [groups, byCourse])
  const schools = useMemo(
    () => [...new Set(groups.map((g) => g.schoolName).filter((s): s is string => !!s))].sort(),
    [groups],
  )
  // Every grade PRESENT across the oversight groups (a split P/1 homeroom contributes both P and 1),
  // sorted by grade order — these are the filter chips.
  const grades = useMemo(
    () => [...new Set(groups.flatMap((g) => g.grades))].sort(
      (a, b) => (GRADE_ORDER[a] ?? 99) - (GRADE_ORDER[b] ?? 99),
    ),
    [groups],
  )
  const multiSchool = schools.length > 1

  const [lens, setLens] = useState<'Homeroom' | 'Section' | 'Grade'>('Homeroom')
  const [shownGrades, setShownGrades] = useState<Set<string>>(() => new Set(grades))
  const [shownSchools, setShownSchools] = useState<Set<string>>(() => new Set(schools))
  const [schoolsOpen, setSchoolsOpen] = useState(false)
  const [ready, setReady] = useState(false)

  // Restore saved filters once on mount (client-only, so no SSR hydration mismatch).
  useEffect(() => {
    const p = readPersistedFilters()
    if (p.lens === 'Section' && hasSections) setLens('Section')
    else if (p.lens === 'Grade' && hasGrades) setLens('Grade')
    if (p.grades) setShownGrades(restoreSet(grades, p.grades))
    if (p.schools) setShownSchools(restoreSet(schools, p.schools))
    setReady(true)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Persist selections after the initial restore (survives Back / re-visits this session).
  useEffect(() => {
    if (!ready) return
    try {
      sessionStorage.setItem(FILTER_KEY, JSON.stringify({ lens, grades: [...shownGrades], schools: [...shownSchools] }))
    } catch {
      /* private mode / storage blocked — filters just won't persist */
    }
  }, [ready, lens, shownGrades, shownSchools])

  const toggle = (set: Set<string>, v: string, setter: (s: Set<string>) => void) => {
    const next = new Set(set)
    if (next.has(v)) next.delete(v)
    else next.add(v)
    setter(next)
  }

  const visible = groups.filter(
    (g) =>
      // Course mode has no lens: every group is a course section, so lens-matching would hide
      // everything (groupType is always 'Course'). Grade + school filters still apply.
      (byCourse || g.groupType === lens) &&
      // Grade match: show the card if ANY grade it contains is selected (a split class surfaces
      // under each of its grades). Groups with no grade info aren't hidden by the filter. The Grade
      // lens is exempt — its filter UI is hidden, so applying it would silently drop cards.
      (lens === 'Grade' || g.grades.length === 0 || g.grades.some((gr) => shownGrades.has(gr))) &&
      (!multiSchool || (g.schoolName != null && shownSchools.has(g.schoolName))),
  )

  return (
    <section className="window-section">
      {showHeading && <h2 className="section-heading">All groups</h2>}

      {/* Lens toggle: Homerooms always; Sections when there are HS sections; Grades = whole-grade
          cohorts (per school). Only rendered when there's more than one lens to switch between. */}
      {(hasSections || hasGrades) && (
        <div className="subject-toggle" role="tablist">
          <button type="button" role="tab" className={lens === 'Homeroom' ? 'toggle-on' : ''} onClick={() => setLens('Homeroom')}>
            Homerooms
          </button>
          {hasSections && (
            <button type="button" role="tab" className={lens === 'Section' ? 'toggle-on' : ''} onClick={() => setLens('Section')}>
              Sections
            </button>
          )}
          {hasGrades && (
            <button type="button" role="tab" className={lens === 'Grade' ? 'toggle-on' : ''} onClick={() => setLens('Grade')}>
              Grades
            </button>
          )}
        </div>
      )}

      {/* Grade filter — hidden on the Grade lens, where the cards themselves are the grades. */}
      {lens !== 'Grade' && grades.length > 1 && (
        <>
          <p className="filter-label">Grades</p>
          <div className="grade-chips">
            {grades.map((g) => (
              <button key={g} className={`grade-chip${shownGrades.has(g) ? ' on' : ''}`} onClick={() => toggle(shownGrades, g, setShownGrades)}>
                {gradeLabel(g)}
              </button>
            ))}
            {/* Select/Clear inline at the row's end — saves the vertical space of a separate actions row */}
            <span className="chip-actions">
              <button type="button" className="btn-ghost" onClick={() => setShownGrades(new Set(grades))}>Select all</button>
              <button type="button" className="btn-ghost" onClick={() => setShownGrades(new Set())}>Clear all</button>
            </span>
          </div>
        </>
      )}

      {/* School filter (collapsible; only when the caller spans multiple schools) */}
      {multiSchool && (
        <div className="mfilter">
          <button className="mfilter-summary" onClick={() => setSchoolsOpen(!schoolsOpen)}>
            <span className="chev">{schoolsOpen ? '▾' : '▸'}</span> Schools{' '}
            <span className="muted">({shownSchools.size} of {schools.length} shown)</span>
          </button>
          {schoolsOpen && (
            <div className="mfilter-body">
              <div className="mfilter-actions">
                <button type="button" className="btn-ghost" onClick={() => setShownSchools(new Set(schools))}>Select all</button>
                <button type="button" className="btn-ghost" onClick={() => setShownSchools(new Set())}>Clear all</button>
                <span className="muted small">Filter the cards to one or more schools.</span>
              </div>
              <div className="chips">
                {schools.map((s) => (
                  <label key={s} className="schip">
                    <input type="checkbox" checked={shownSchools.has(s)} onChange={() => toggle(shownSchools, s, setShownSchools)} />
                    {s}
                  </label>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {visible.length === 0 ? (
        <p className="muted" style={{ marginTop: '1rem' }}>No {byCourse ? 'sections' : lens === 'Section' ? 'sections' : lens === 'Grade' ? 'grades' : 'homerooms'} match the current filters.</p>
      ) : byCourse ? (
        <ByLanguage groups={visible} card={card} hrefBase={hrefBase} isMath={isMath} />
      ) : (
        <div className="card-grid">{visible.map(card)}</div>
      )}
    </section>
  )
}
