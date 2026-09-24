'use client'

import Link from 'next/link'
import { useMemo, useState } from 'react'
import type { RWMStudent } from '@/lib/data'

// RWM = a 0–3 score per Primary–6 student: how many of Reading / Writing / Math they're currently
// meeting or exceeding. Cohort-wide (like the Reading/Writing report), IPP-in-any students already
// excluded by the TVF. Faceted grade / program / school / score filters that live-trim each other.

const GRADE_ORDER: Record<string, number> = { PP: -1, P: 0, '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6 }
const gradeLabel = (g: string) => (g === 'P' ? 'Primary' : g === 'PP' ? 'Pre-Primary' : `Grade ${g}`)
const SCORE_HEX: Record<number, string> = { 0: '#b23347', 1: '#c07d16', 2: '#2f8f4e', 3: '#0092c9' }

// Meeting pill for one area: ✓ meeting / — not meeting / no result yet.
function AreaCell({ meeting, has }: { meeting: boolean; has: boolean }) {
  if (!has) return <span className="rwm-area none">no result</span>
  return meeting
    ? <span className="rwm-area yes">Meeting+</span>
    : <span className="rwm-area no">Not yet</span>
}

export default function RWMCohortView({ cohort }: { cohort: RWMStudent[] }) {
  const allGrades = useMemo(
    () => [...new Set(cohort.map((s) => s.grade).filter((g): g is string => !!g))]
      .sort((a, b) => (GRADE_ORDER[a] ?? 99) - (GRADE_ORDER[b] ?? 99)),
    [cohort],
  )
  const allPrograms = useMemo(
    () => [...new Set(cohort.map((s) => s.programFamily).filter((p): p is string => !!p))].sort(),
    [cohort],
  )
  const allSchools = useMemo(
    () => [...new Set(cohort.map((s) => s.schoolName).filter((s): s is string => !!s))].sort(),
    [cohort],
  )

  const [grades, setGrades] = useState<Set<string>>(new Set())
  const [programs, setPrograms] = useState<Set<string>>(new Set())
  const [schools, setSchools] = useState<Set<string>>(new Set())
  const [scores, setScores] = useState<Set<number>>(new Set())

  // A student matches every filter EXCEPT the one named — so each facet's chip list can be trimmed to
  // what's still reachable given the other active filters (live-trim), without a facet hiding itself.
  const matchExcept = (s: RWMStudent, except: string) =>
    (except === 'grade' || grades.size === 0 || (s.grade != null && grades.has(s.grade))) &&
    (except === 'prog' || programs.size === 0 || (s.programFamily != null && programs.has(s.programFamily))) &&
    (except === 'sch' || schools.size === 0 || (s.schoolName != null && schools.has(s.schoolName))) &&
    (except === 'score' || scores.size === 0 || scores.has(s.rwmScore))

  const facetGrades = useMemo(
    () => allGrades.filter((g) => cohort.some((s) => s.grade === g && matchExcept(s, 'grade'))),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [allGrades, cohort, programs, schools, scores],
  )
  const facetPrograms = useMemo(
    () => allPrograms.filter((p) => cohort.some((s) => s.programFamily === p && matchExcept(s, 'prog'))),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [allPrograms, cohort, grades, schools, scores],
  )
  const facetSchools = useMemo(
    () => allSchools.filter((sc) => cohort.some((s) => s.schoolName === sc && matchExcept(s, 'sch'))),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [allSchools, cohort, grades, programs, scores],
  )

  const filtered = useMemo(
    () => cohort.filter((s) => matchExcept(s, '')),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [cohort, grades, programs, schools, scores],
  )

  // Distribution donut over the filtered set, bucketed by 0–3.
  const donut = useMemo(() => {
    const counts: Record<number, number> = { 0: 0, 1: 0, 2: 0, 3: 0 }
    for (const s of filtered) counts[s.rwmScore]++
    const total = filtered.length
    let acc = 0
    const slices = [3, 2, 1, 0].map((score) => {
      const count = counts[score]
      const startPct = total ? (acc / total) * 100 : 0
      acc += count
      const endPct = total ? (acc / total) * 100 : 0
      return { score, color: SCORE_HEX[score], count, pct: total ? (count / total) * 100 : 0, startPct, endPct }
    })
    const gradient = total
      ? slices.filter((s) => s.count > 0).map((s) => `${s.color} ${s.startPct.toFixed(2)}% ${s.endPct.toFixed(2)}%`).join(', ')
      : 'var(--border) 0% 100%'
    return { slices, total, gradient }
  }, [filtered])

  const toggle = <T,>(set: Set<T>, v: T, setter: (s: Set<T>) => void) => {
    const next = new Set(set)
    next.has(v) ? next.delete(v) : next.add(v)
    setter(next)
  }
  const reset = () => { setGrades(new Set()); setPrograms(new Set()); setSchools(new Set()); setScores(new Set()) }
  const anyFilter = grades.size || programs.size || schools.size || scores.size

  return (
    <>
      <div className="filter-bar">
        <div className="filter-group">
          <label>Grade</label>
          <div className="grade-chips">
            {facetGrades.map((g) => (
              <button key={g} className={`grade-chip${grades.has(g) ? ' on' : ''}`} onClick={() => toggle(grades, g, setGrades)}>{gradeLabel(g)}</button>
            ))}
          </div>
        </div>
        {allPrograms.length > 1 && (
          <div className="filter-group">
            <label>Program</label>
            <div className="grade-chips">
              {facetPrograms.map((p) => (
                <button key={p} className={`grade-chip${programs.has(p) ? ' on' : ''}`} onClick={() => toggle(programs, p, setPrograms)}>{p}</button>
              ))}
            </div>
          </div>
        )}
        {allSchools.length > 1 && (
          <div className="filter-group">
            <label>School</label>
            <div className="grade-chips">
              {facetSchools.map((sc) => (
                <button key={sc} className={`grade-chip${schools.has(sc) ? ' on' : ''}`} onClick={() => toggle(schools, sc, setSchools)}>{sc}</button>
              ))}
            </div>
          </div>
        )}
        <div className="filter-group">
          <label>RWM score</label>
          <div className="grade-chips">
            {[0, 1, 2, 3].map((n) => (
              <button
                key={n}
                className={`grade-chip${scores.has(n) ? ' on' : ''}`}
                onClick={() => toggle(scores, n, setScores)}
                style={scores.has(n) ? { background: SCORE_HEX[n], borderColor: SCORE_HEX[n], color: '#fff' } : undefined}
              >
                {n} / 3
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="cohort-bar">
        <span className="muted">{filtered.length} of {cohort.length} students</span>
        {anyFilter ? <button className="btn-ghost" onClick={reset}>Reset filters</button> : null}
      </div>

      <div className="cohort-charts">
        <div className="chart-card">
          <div className="chart-title">RWM score distribution</div>
          <div className="donut-wrap">
            <div className="donut" style={{ background: `conic-gradient(${donut.gradient})` }}>
              <div className="donut-hole">
                <div className="donut-total">{donut.total}</div>
                <div className="donut-label">STUDENTS</div>
              </div>
            </div>
            <ul className="donut-legend">
              {donut.slices.map((s) => (
                <li key={s.score}>
                  <span className="swatch" style={{ background: s.color }} />
                  <span className="legend-name">{s.score} of 3 meeting+</span>
                  <span className="legend-val">{s.pct.toFixed(1)}% · {s.count}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>

      {filtered.length === 0 ? (
        <div className="notice notice-empty"><div className="notice-title">No students match the current filters.</div></div>
      ) : (
        <table className="grid">
          <thead>
            <tr>
              <th>Student</th>
              <th>Grade</th>
              <th>Program</th>
              <th>School</th>
              <th>Reading</th>
              <th>Writing</th>
              <th>Math</th>
              <th>RWM</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((s) => (
              <tr key={s.studentKey}>
                <td><Link href={`/reports/rwm/${s.studentKey}`}>{s.fullName}</Link></td>
                <td>{gradeLabel(s.grade ?? '—')}</td>
                <td>{s.programFamily ?? '—'}</td>
                <td>{s.schoolAbbrev ?? s.schoolName ?? '—'}</td>
                <td><AreaCell meeting={s.readingMeeting} has={s.hasReading} /></td>
                <td><AreaCell meeting={s.writingMeeting} has={s.hasWriting} /></td>
                <td><AreaCell meeting={s.mathMeeting} has={s.hasMath} /></td>
                <td>
                  <span className="rwm-score" style={{ background: SCORE_HEX[s.rwmScore] }}>{s.rwmScore}</span>
                  <span className="muted"> / 3</span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  )
}
