'use client'

import Link from 'next/link'
import { useEffect, useMemo, useState } from 'react'
import type { CohortStudent, AchievementBand } from '@/lib/data'

// Distinct, order-preserving helper.
function distinct<T>(xs: T[]): T[] {
  return Array.from(new Set(xs))
}

type Tri = 'All' | 'Yes' | 'No'

// Persist the cohort filters for the tab session (sessionStorage: per-tab, survives Back /
// re-visits, clears on tab close). Read wrapped in try/catch (private mode / blocked storage).
const COHORT_FILTER_KEY = 'cohortFilters'
type CohortPersist = {
  expanded?: boolean
  gradeMin?: number
  gradeMax?: number
  gender?: string
  african?: Tri
  indigenous?: Tri
  hr?: string[]
  prog?: string[]
  sch?: string[]
  ach?: number[]
}
function readCohortFilters(): CohortPersist {
  try {
    const raw = sessionStorage.getItem(COHORT_FILTER_KEY)
    return raw ? (JSON.parse(raw) as CohortPersist) : {}
  } catch {
    return {}
  }
}

function triMatch(sel: Tri, v: boolean | null): boolean {
  if (sel === 'All') return true
  if (sel === 'Yes') return v === true
  return v === false
}

// Last 6 month buckets ending with the current month (oldest first).
function monthBuckets(now: Date): { label: string; nextMonthStart: Date }[] {
  const out: { label: string; nextMonthStart: Date }[] = []
  const fmt = new Intl.DateTimeFormat('en-CA', { month: 'short' })
  for (let i = 5; i >= 0; i--) {
    const start = new Date(now.getFullYear(), now.getMonth() - i, 1)
    const next = new Date(now.getFullYear(), now.getMonth() - i + 1, 1)
    out.push({ label: fmt.format(start), nextMonthStart: next })
  }
  return out
}

export default function CohortView({
  cohort,
  bands,
  subject = 'Reading',
}: {
  cohort: CohortStudent[]
  bands: AchievementBand[]
  subject?: 'Reading' | 'Writing'
}) {
  // Achievement bands ordered by code (1..4); used for chart colours/legend + the filter.
  const orderedBands = useMemo(
    () => [...bands].sort((a, b) => Number(a.code) - Number(b.code)),
    [bands],
  )
  const bandByCode = useMemo(() => new Map(orderedBands.map((b) => [Number(b.code), b])), [orderedBands])

  // Option lists derived from the (already RLS-scoped) cohort.
  const grades = useMemo(
    () =>
      distinct(cohort.filter((s) => s.gradeOrder != null).map((s) => `${s.gradeOrder}|${s.grade}`))
        .map((g) => {
          const [ord, label] = g.split('|')
          return { ord: Number(ord), label }
        })
        .sort((a, b) => a.ord - b.ord),
    [cohort],
  )
  const genders = useMemo(() => distinct(cohort.map((s) => s.gender).filter(Boolean) as string[]).sort(), [cohort])
  // FULL-cohort option lists — used only to validate restored filters (a saved homeroom stays valid
  // even before its school is re-selected). Display uses the faceted lists further down.
  const allHomerooms = useMemo(() => distinct(cohort.map((s) => s.homeroom).filter(Boolean) as string[]).sort(), [cohort])
  const allPrograms = useMemo(() => distinct(cohort.map((s) => s.programFamily).filter(Boolean) as string[]).sort(), [cohort])
  const allSchools = useMemo(() => {
    const seen = new Map<string, string>()
    for (const s of cohort) if (s.schoolId) seen.set(s.schoolId, s.schoolAbbreviation ?? s.schoolName ?? s.schoolId)
    return Array.from(seen, ([id, label]) => ({ id, label })).sort((a, b) => a.label.localeCompare(b.label))
  }, [cohort])

  const minOrd = grades.length ? grades[0].ord : 0
  const maxOrd = grades.length ? grades[grades.length - 1].ord : 0

  const [expanded, setExpanded] = useState(false)
  const [gradeMin, setGradeMin] = useState(minOrd)
  const [gradeMax, setGradeMax] = useState(maxOrd)
  const [gender, setGender] = useState('All')
  const [african, setAfrican] = useState<Tri>('All')
  const [indigenous, setIndigenous] = useState<Tri>('All')
  const [hr, setHr] = useState<Set<string>>(new Set())
  const [prog, setProg] = useState<Set<string>>(new Set())
  const [sch, setSch] = useState<Set<string>>(new Set())
  const [ach, setAch] = useState<Set<number>>(new Set())

  function toggle<T>(set: Set<T>, v: T, setter: (s: Set<T>) => void) {
    const next = new Set(set)
    if (next.has(v)) next.delete(v)
    else next.add(v)
    setter(next)
  }

  // School toggle: homeroom only makes sense within ONE school, so leaving the single-school state
  // (deselecting the school, or picking a second) clears any homeroom selection with it.
  function toggleSchool(id: string) {
    const next = new Set(sch)
    if (next.has(id)) next.delete(id)
    else next.add(id)
    setSch(next)
    if (next.size !== 1) setHr(new Set())
  }

  function reset() {
    setGradeMin(minOrd)
    setGradeMax(maxOrd)
    setGender('All')
    setAfrican('All')
    setIndigenous('All')
    setHr(new Set())
    setProg(new Set())
    setSch(new Set())
    setAch(new Set())
  }

  // Persist cohort filters for the tab session, so filtering the cohort, opening a student, and
  // hitting Back doesn't wipe the selection. Restore runs once on mount (client-only → no SSR
  // hydration mismatch); an empty Set means "show all", so we just intersect saved values with the
  // current options and drop anything no longer present, and clamp the grade bounds into range.
  const [ready, setReady] = useState(false)
  useEffect(() => {
    const p = readCohortFilters()
    const schoolIds = allSchools.map((s) => s.id)
    const achCodes = orderedBands.map((b) => Number(b.code))
    if (typeof p.expanded === 'boolean') setExpanded(p.expanded)
    if (typeof p.gradeMin === 'number') setGradeMin(Math.min(Math.max(p.gradeMin, minOrd), maxOrd))
    if (typeof p.gradeMax === 'number') setGradeMax(Math.min(Math.max(p.gradeMax, minOrd), maxOrd))
    if (p.gender === 'All' || (p.gender && genders.includes(p.gender))) setGender(p.gender)
    if (p.african === 'All' || p.african === 'Yes' || p.african === 'No') setAfrican(p.african)
    if (p.indigenous === 'All' || p.indigenous === 'Yes' || p.indigenous === 'No') setIndigenous(p.indigenous)
    if (p.hr) setHr(new Set(p.hr.filter((v) => allHomerooms.includes(v))))
    if (p.prog) setProg(new Set(p.prog.filter((v) => allPrograms.includes(v))))
    if (p.sch) setSch(new Set(p.sch.filter((v) => schoolIds.includes(v))))
    if (p.ach) setAch(new Set(p.ach.filter((v) => achCodes.includes(v))))
    setReady(true)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    if (!ready) return
    try {
      sessionStorage.setItem(
        COHORT_FILTER_KEY,
        JSON.stringify({ expanded, gradeMin, gradeMax, gender, african, indigenous, hr: [...hr], prog: [...prog], sch: [...sch], ach: [...ach] }),
      )
    } catch {
      /* private mode / storage blocked — filters just won't persist */
    }
  }, [ready, expanded, gradeMin, gradeMax, gender, african, indigenous, hr, prog, sch, ach])

  const oneSchool = sch.size === 1 // homeroom is only offered/applied once narrowed to one school
  // A student passes every ACTIVE filter except the named dimension — the basis for both the final
  // list (except='') and each filter's faceted options (so a filter never hides its own choices).
  const matchExcept = (s: CohortStudent, except: string) =>
    (except === 'grade' || s.gradeOrder == null || (s.gradeOrder >= gradeMin && s.gradeOrder <= gradeMax)) &&
    (except === 'gender' || gender === 'All' || s.gender === gender) &&
    (except === 'african' || triMatch(african, s.selfIDAfrican)) &&
    (except === 'indigenous' || triMatch(indigenous, s.selfIDIndigenous)) &&
    (except === 'hr' || !oneSchool || hr.size === 0 || (s.homeroom != null && hr.has(s.homeroom))) &&
    (except === 'prog' || prog.size === 0 || (s.programFamily != null && prog.has(s.programFamily))) &&
    (except === 'sch' || sch.size === 0 || (s.schoolId != null && sch.has(s.schoolId))) &&
    // Match the achievement filter only for students whose achievement is actually SHOWN. IPP /
    // unresolved-IPP students aren't measured against benchmarks (the table hides their band as
    // "IPP"/"—"), yet the TVF still computes an achievementCode from their delta — so without the
    // chartEligible guard they leaked into an achievement-level filter looking "scoreless".
    (except === 'ach' || ach.size === 0 || (s.chartEligible && s.achievementCode != null && ach.has(s.achievementCode)))

  // Live-trimmed chip options (present under the OTHER active filters). Homeroom is withheld entirely
  // until a SINGLE school is selected — region-wide it's an unusable wall of chips.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const homerooms = useMemo(
    () => (oneSchool ? distinct(cohort.filter((s) => matchExcept(s, 'hr')).map((s) => s.homeroom).filter(Boolean) as string[]).sort() : []),
    [cohort, oneSchool, gradeMin, gradeMax, gender, african, indigenous, prog, sch, ach],
  )
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const programs = useMemo(
    () => distinct(cohort.filter((s) => matchExcept(s, 'prog')).map((s) => s.programFamily).filter(Boolean) as string[]).sort(),
    [cohort, gradeMin, gradeMax, gender, african, indigenous, hr, sch, ach],
  )
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const schools = useMemo(() => {
    const seen = new Map<string, string>()
    for (const s of cohort) if (s.schoolId && matchExcept(s, 'sch')) seen.set(s.schoolId, s.schoolAbbreviation ?? s.schoolName ?? s.schoolId)
    return Array.from(seen, ([id, label]) => ({ id, label })).sort((a, b) => a.label.localeCompare(b.label))
  }, [cohort, gradeMin, gradeMax, gender, african, indigenous, hr, prog, ach])

  const filtered = useMemo(
    () => cohort.filter((s) => matchExcept(s, '')),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [cohort, gradeMin, gradeMax, gender, african, indigenous, hr, prog, sch, ach],
  )

  // Chart-eligible subset (IPP / unresolved students excluded from aggregate stats).
  const chartRows = useMemo(() => filtered.filter((s) => s.chartEligible), [filtered])

  // Donut: current achievement distribution over assessed, chart-eligible students.
  const donut = useMemo(() => {
    const assessed = chartRows.filter((s) => s.achievementCode != null)
    const counts = new Map<number, number>()
    for (const s of assessed) counts.set(s.achievementCode!, (counts.get(s.achievementCode!) ?? 0) + 1)
    const total = assessed.length
    let acc = 0
    const slices = orderedBands.map((b) => {
      const code = Number(b.code)
      const count = counts.get(code) ?? 0
      const startPct = total ? (acc / total) * 100 : 0
      acc += count
      const endPct = total ? (acc / total) * 100 : 0
      return {
        code,
        name: b.name,
        color: b.hexColor,
        count,
        pct: total ? (count / total) * 100 : 0,
        startPct,
        endPct,
      }
    })
    const gradient = total
      ? slices
          .filter((s) => s.count > 0)
          .map((s) => `${s.color} ${s.startPct.toFixed(2)}% ${s.endPct.toFixed(2)}%`)
          .join(', ')
      : 'var(--border) 0% 100%'
    return { slices, total, gradient }
  }, [chartRows, orderedBands])

  // 6-month bar: cumulative most-recent achievement as-of each month end.
  const months = useMemo(() => {
    const buckets = monthBuckets(new Date())
    const maxCode = 4
    return buckets.map((bk) => {
      const counts: Record<number, number> = {}
      for (let c = 1; c <= maxCode; c++) counts[c] = 0
      let total = 0
      for (const s of chartRows) {
        if (!s.mostRecentDate || s.achievementCode == null) continue
        if (new Date(s.mostRecentDate) < bk.nextMonthStart) {
          counts[s.achievementCode] = (counts[s.achievementCode] ?? 0) + 1
          total++
        }
      }
      return { label: bk.label, counts, total }
    })
  }, [chartRows])
  const monthMax = useMemo(() => Math.max(1, ...months.map((m) => m.total)), [months])

  return (
    <>
      <div className="cohort-bar">
        <span className="muted">{filtered.length} of {cohort.length} students match</span>
        <button className="btn-ghost" onClick={() => setExpanded((e) => !e)}>
          {expanded ? 'Hide filters' : 'Show filters'}
        </button>
        <button className="btn-ghost" onClick={reset}>
          Reset
        </button>
      </div>

      {expanded ? (
        <div className="filter-bar">
          <div className="filter-group">
            <label>Grade</label>
            <div className="filter-row">
              <select value={gradeMin} onChange={(e) => setGradeMin(Number(e.target.value))}>
                {grades.map((g) => (
                  <option key={g.ord} value={g.ord}>{g.label}</option>
                ))}
              </select>
              <span className="muted">to</span>
              <select value={gradeMax} onChange={(e) => setGradeMax(Number(e.target.value))}>
                {grades.map((g) => (
                  <option key={g.ord} value={g.ord}>{g.label}</option>
                ))}
              </select>
            </div>
          </div>

          {genders.length > 1 ? (
            <div className="filter-group">
              <label>Gender</label>
              <select value={gender} onChange={(e) => setGender(e.target.value)}>
                <option value="All">All</option>
                {genders.map((g) => (
                  <option key={g} value={g}>{g}</option>
                ))}
              </select>
            </div>
          ) : null}

          <div className="filter-group">
            <label>Self-ID African</label>
            <select value={african} onChange={(e) => setAfrican(e.target.value as Tri)}>
              <option>All</option>
              <option>Yes</option>
              <option>No</option>
            </select>
          </div>

          <div className="filter-group">
            <label>Self-ID Indigenous</label>
            <select value={indigenous} onChange={(e) => setIndigenous(e.target.value as Tri)}>
              <option>All</option>
              <option>Yes</option>
              <option>No</option>
            </select>
          </div>

          {oneSchool && homerooms.length > 0 ? (
            <div className="filter-group">
              <label>Homeroom</label>
              <div className="chips">
                {homerooms.map((h) => (
                  <button
                    key={h}
                    className={hr.has(h) ? 'chip chip-on' : 'chip'}
                    onClick={() => toggle(hr, h, setHr)}
                  >
                    {h}
                  </button>
                ))}
              </div>
            </div>
          ) : !oneSchool && allHomerooms.length > 1 && allSchools.length > 1 ? (
            <div className="filter-group">
              <label>Homeroom</label>
              <span className="muted small">Select a single school to filter by homeroom.</span>
            </div>
          ) : null}

          {programs.length > 1 || prog.size > 0 ? (
            <div className="filter-group">
              <label>Program</label>
              <div className="chips">
                {programs.map((p) => (
                  <button
                    key={p}
                    className={prog.has(p) ? 'chip chip-on' : 'chip'}
                    onClick={() => toggle(prog, p, setProg)}
                  >
                    {p}
                  </button>
                ))}
              </div>
            </div>
          ) : null}

          {schools.length > 1 || sch.size > 0 ? (
            <div className="filter-group">
              <label>School</label>
              <div className="chips">
                {schools.map((s) => (
                  <button
                    key={s.id}
                    className={sch.has(s.id) ? 'chip chip-on' : 'chip'}
                    onClick={() => toggleSchool(s.id)}
                  >
                    {s.label}
                  </button>
                ))}
              </div>
            </div>
          ) : null}

          <div className="filter-group">
            <label>Achievement</label>
            <div className="chips">
              {orderedBands.map((b) => {
                const code = Number(b.code)
                return (
                  <button
                    key={b.code}
                    className={ach.has(code) ? 'chip chip-on' : 'chip'}
                    style={ach.has(code) ? { background: b.hexColor, borderColor: b.hexColor, color: '#fff' } : undefined}
                    onClick={() => toggle(ach, code, setAch)}
                  >
                    {b.name}
                  </button>
                )
              })}
            </div>
          </div>
        </div>
      ) : null}

      <div className="cohort-charts">
        <div className="chart-card">
          <div className="chart-title">Current achievement distribution</div>
          <div className="donut-wrap">
            <div className="donut" style={{ background: `conic-gradient(${donut.gradient})` }}>
              <div className="donut-hole">
                <div className="donut-total">{donut.total}</div>
                <div className="donut-label">ASSESSED</div>
              </div>
            </div>
            <ul className="donut-legend">
              {donut.slices.map((s) => (
                <li key={s.code}>
                  <span className="swatch" style={{ background: s.color }} />
                  <span className="legend-name">{s.name}</span>
                  <span className="legend-val">{s.pct.toFixed(1)}% · {s.count}</span>
                </li>
              ))}
            </ul>
          </div>
          {donut.total === 0 ? <div className="muted chart-empty">No assessed, chart-eligible students match.</div> : null}
        </div>

        <div className="chart-card">
          <div className="chart-title">Achievement by month (last 6 months)</div>
          <div className="monthbars">
            {months.map((m) => (
              <div key={m.label} className="monthbar">
                <div className="monthbar-stack">
                  {[1, 2, 3, 4].map((c) => {
                    const v = m.counts[c] ?? 0
                    if (!v) return null
                    const band = bandByCode.get(c)
                    const h = (v / monthMax) * 100
                    return (
                      <div
                        key={c}
                        className="monthbar-seg"
                        style={{ height: `${h}%`, background: band?.hexColor ?? 'var(--border)' }}
                        title={`${band?.name ?? c}: ${v}`}
                      />
                    )
                  })}
                </div>
                <div className="monthbar-label">{m.label}</div>
              </div>
            ))}
          </div>
          <ul className="bar-legend">
            {orderedBands.map((b) => (
              <li key={b.code}>
                <span className="swatch" style={{ background: b.hexColor }} />
                {b.name}
              </li>
            ))}
          </ul>
        </div>
      </div>

      {filtered.length === 0 ? (
        <div className="notice notice-empty">
          <div className="notice-title">No students match the current filters.</div>
        </div>
      ) : (
        <table className="grid">
          <thead>
            <tr>
              <th>Student</th>
              <th>Grade</th>
              <th>Program</th>
              <th>School</th>
              <th>{subject === 'Writing' ? 'Avg' : 'Level'}</th>
              {subject === 'Reading' ? <th>Expected</th> : null}
              {subject === 'Reading' ? (
                <th>
                  Diff from<br />Prev June
                </th>
              ) : null}
              <th>Achievement</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((s) => {
              // IPP / unresolved students aren't measured against benchmarks — no achievement
              // tint or band (their reading level still shows). chartEligible = no IPP or IsIPP=0.
              const measured = s.chartEligible
              return (
                <tr key={s.studentKey} style={measured && s.achievementHexColorTint ? { background: s.achievementHexColorTint } : undefined}>
                  <td>
                    <Link href={`/reports/${s.studentKey}${subject === 'Writing' ? '?subject=writing' : ''}`} className="back-link">
                      {s.lastName}, {s.firstName}
                    </Link>
                  </td>
                  <td>{s.grade ?? '—'}</td>
                  <td>{s.programFamily ?? '—'}</td>
                  <td>{s.schoolAbbreviation ?? s.schoolId ?? '—'}</td>
                  <td>{s.mostRecentLevelCode ?? <span className="muted">—</span>}</td>
                  {subject === 'Reading' ? (
                    <td>
                      {s.expectedMin && s.expectedMax ? (
                        s.expectedMin === s.expectedMax ? s.expectedMin : `${s.expectedMin}–${s.expectedMax}`
                      ) : (
                        <span className="muted">—</span>
                      )}
                    </td>
                  ) : null}
                  {subject === 'Reading' ? (
                    <td style={{ textAlign: 'center' }}>
                      {s.diffFromPrevJune == null ? (
                        <span className="muted">—</span>
                      ) : (
                        <strong style={{ color: s.diffFromPrevJune > 0 ? '#137333' : s.diffFromPrevJune < 0 ? '#a50e0e' : 'inherit' }}>
                          {s.diffFromPrevJune > 0 ? `+${s.diffFromPrevJune}` : s.diffFromPrevJune}
                        </strong>
                      )}
                    </td>
                  ) : null}
                  <td style={measured && s.achievementHexColor ? { color: s.achievementHexColor, fontWeight: 600 } : undefined}>
                    {!measured ? (s.ippStatusReading === 'IPP' ? 'IPP' : '—') : s.achievementName ?? '—'}
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      )}
    </>
  )
}
