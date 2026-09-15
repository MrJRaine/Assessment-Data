'use client'

import { useMemo, useState, type ReactNode } from 'react'
import { CardLink } from '@/components/ui'
import type { TeacherGroup } from '@/lib/data'

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

export default function GroupCards({
  groups,
  hrefBase,
  metaSuffix = 'entered',
}: {
  groups: TeacherGroup[]
  hrefBase: string
  metaSuffix?: string
}) {
  const taught = groups.filter((g) => g.scope === 'Taught')
  const oversight = groups.filter((g) => g.scope === 'Oversight')

  const card = (g: TeacherGroup) => (
    <CardLink
      key={`${g.scope}-${g.groupType}-${g.key}`}
      href={`${hrefBase}/${g.key}`}
      title={g.label}
      desc={g.schoolName ?? undefined}
      meta={`${g.enteredCount}/${g.applicableCount} ${metaSuffix}`}
    />
  )

  return (
    <>
      {taught.length > 0 && (
        <section>
          <h2 className="section-heading">My classes</h2>
          <div className="card-grid">{taught.map(card)}</div>
        </section>
      )}

      {oversight.length > 0 && <Oversight groups={oversight} card={card} showHeading={taught.length > 0} />}
    </>
  )
}

function Oversight({
  groups,
  card,
  showHeading,
}: {
  groups: TeacherGroup[]
  card: (g: TeacherGroup) => ReactNode
  showHeading: boolean
}) {
  const hasSections = useMemo(() => groups.some((g) => g.groupType === 'Section'), [groups])
  const schools = useMemo(
    () => [...new Set(groups.map((g) => g.schoolName).filter((s): s is string => !!s))].sort(),
    [groups],
  )
  const grades = useMemo(
    () => [...new Set(groups.map((g) => g.grade).filter((g): g is string => !!g))].sort(
      (a, b) => (GRADE_ORDER[a] ?? 99) - (GRADE_ORDER[b] ?? 99),
    ),
    [groups],
  )
  const multiSchool = schools.length > 1

  const [lens, setLens] = useState<'Homeroom' | 'Section'>('Homeroom')
  const [shownGrades, setShownGrades] = useState<Set<string>>(() => new Set(grades))
  const [shownSchools, setShownSchools] = useState<Set<string>>(() => new Set(schools))
  const [schoolsOpen, setSchoolsOpen] = useState(false)

  const toggle = (set: Set<string>, v: string, setter: (s: Set<string>) => void) => {
    const next = new Set(set)
    if (next.has(v)) next.delete(v)
    else next.add(v)
    setter(next)
  }

  const visible = groups.filter(
    (g) =>
      g.groupType === lens &&
      (g.grade == null || shownGrades.has(g.grade)) &&
      (!multiSchool || (g.schoolName != null && shownSchools.has(g.schoolName))),
  )

  return (
    <section className="window-section">
      {showHeading && <h2 className="section-heading">All groups</h2>}

      {/* Homeroom | Section lens toggle (Section only offered when there are HS sections) */}
      {hasSections && (
        <div className="subject-toggle" role="tablist">
          <button type="button" role="tab" className={lens === 'Homeroom' ? 'toggle-on' : ''} onClick={() => setLens('Homeroom')}>
            Homerooms
          </button>
          <button type="button" role="tab" className={lens === 'Section' ? 'toggle-on' : ''} onClick={() => setLens('Section')}>
            Sections
          </button>
        </div>
      )}

      {/* Grade filter */}
      {grades.length > 1 && (
        <>
          <p className="filter-label">Grades</p>
          <div className="grade-chips">
            {grades.map((g) => (
              <button key={g} className={`grade-chip${shownGrades.has(g) ? ' on' : ''}`} onClick={() => toggle(shownGrades, g, setShownGrades)}>
                {gradeLabel(g)}
              </button>
            ))}
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
        <p className="muted" style={{ marginTop: '1rem' }}>No {lens === 'Section' ? 'sections' : 'homerooms'} match the current filters.</p>
      ) : (
        <div className="card-grid">{visible.map(card)}</div>
      )}
    </section>
  )
}
