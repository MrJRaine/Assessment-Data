'use client'

import Link from 'next/link'
import { Fragment, useMemo, useState, type ReactNode } from 'react'
import type { RWMStudent } from '@/lib/data'
import { gradeLabel, gradeRank, gradeSpanLabel, demoPass, type SummarizeBy, type Tri, type DemoFilter } from '../rollupModel'
import { heatClass, fmtPct } from '../math/mathModel' // shared heat scale + 2-dp % (cross-report consistency)
import { SCORE_HEX } from './RWMCohortView'

// RWM oversight roll-up (user ask 2026-11-10): School → Grade|Homeroom (same toggle as the other
// summary trees, TCRCE all-schools row for Regional Analysts). Columns = COUNTS of students at each
// RWM score (0–3 of Reading/Writing/Math at Meeting or exceeding) + "% in all 3" (score-3 students
// over the row's students). Built entirely client-side from the same cohort the Student list uses —
// no extra warehouse reads; a node expands to its own students inline for the same reason.
// The filter section (2026-11-10) mirrors the Reading/Writing trees' (Grade / Gender / Self-ID) and
// also hosts the two RWM scoring toggles from the Student list: Math blanks (excluded vs count-as-0,
// which re-scores) and "All 3 areas only" (evidence in every area).

type Row = RWMStudent & { score: number; mathMeets: boolean; complete: boolean }

interface Node {
  id: string
  label: string
  sub: string | null
  grades: string[]
  students: Row[]
}

const TCRCE_ID = '__TCRCE__'

const toRows = (cohort: RWMStudent[], blankMode: 'exclude' | 'zero'): Row[] =>
  cohort.map((s) => {
    const pct = blankMode === 'zero' ? s.mathRollupPctZero : s.mathRollupPct
    const mathMeets = pct != null && pct >= 0.75
    return {
      ...s, mathMeets,
      score: (s.readingMeeting ? 1 : 0) + (s.writingMeeting ? 1 : 0) + (mathMeets ? 1 : 0),
      complete: s.hasReading && s.hasWriting && s.hasMath,
    }
  })

function tallyScores(rows: Row[]) {
  const c = [0, 0, 0, 0]
  for (const r of rows) c[r.score]++
  return { c, total: rows.length, pctAll3: rows.length ? c[3] / rows.length : null }
}

function childrenOf(students: Row[], schoolId: string, by: SummarizeBy): Node[] {
  const m = new Map<string, Row[]>()
  for (const s of students) {
    const k = by === 'Grade' ? (s.grade ?? '?') : (s.homeroom ?? '')
    m.set(k, [...(m.get(k) ?? []), s])
  }
  const nodes: Node[] = [...m.entries()].map(([k, studs]) => {
    const grades = [...new Set(studs.map((s) => s.grade ?? '?'))].sort((a, b) => gradeRank(a) - gradeRank(b))
    return by === 'Grade'
      ? { id: `G:${schoolId}:${k}`, label: gradeLabel(k), sub: null, grades, students: studs }
      : { id: `H:${schoolId}:${k}`, label: k ? `Homeroom ${k}` : 'No homeroom', sub: gradeSpanLabel(grades), grades, students: studs }
  })
  return nodes.sort(
    (a, b) => gradeRank(a.grades[0]) - gradeRank(b.grades[0]) || a.label.localeCompare(b.label, undefined, { numeric: true }),
  )
}

function CountCells({ t }: { t: ReturnType<typeof tallyScores> }) {
  return (
    <>
      {[0, 1, 2, 3].map((n) => (
        <td className="rn" key={n}>{t.c[n] === 0 ? <span className="muted">0</span> : t.c[n]}</td>
      ))}
      <td className={`rpct ${t.pctAll3 == null ? 'none' : heatClass(t.pctAll3)}`}
          title={`${t.c[3]} of ${t.total} students Meeting or exceeding in all of Reading, Writing and Math`}>
        {fmtPct(t.pctAll3)}
      </td>
    </>
  )
}

// Area pill, same wording/classes as the Student-list cells.
function Area({ meeting, has }: { meeting: boolean; has: boolean }) {
  if (!has) return <span className="rwm-area none">no result</span>
  return meeting ? <span className="rwm-area yes">Meeting or exceeding</span> : <span className="rwm-area no">Not yet</span>
}

// One opened node's students, inline (the rows are already on the client — no fetch). The node
// pins one axis, so the second column shows the OTHER one (Grade node → Homeroom, and vice versa).
function NodeDetail({ node, summarizeBy }: { node: Node; summarizeBy: SummarizeBy }) {
  const demoAxis = summarizeBy === 'Grade' ? 'Homeroom' : 'Grade'
  const sorted = [...node.students].sort(
    (a, b) => a.lastName.localeCompare(b.lastName) || a.firstName.localeCompare(b.firstName),
  )
  return (
    <div className="mscroll">
      <table className="mgrid">
        <thead>
          <tr>
            <th className="col-task">Student</th>
            <th className="stu">{demoAxis}</th>
            <th className="stu">Reading</th>
            <th className="stu">Writing</th>
            <th className="stu">Math</th>
            <th className="stu">RWM</th>
          </tr>
        </thead>
        <tbody>
          {sorted.map((s) => (
            <tr key={s.studentKey}>
              <th className="col-task" scope="row">
                <Link href={`/reports/rwm/${s.studentKey}`} className="back-link">{s.lastName}, {s.firstName}</Link>
              </th>
              <td className="stu">{demoAxis === 'Homeroom' ? (s.homeroom ?? '—') : s.grade ? gradeLabel(s.grade) : '—'}</td>
              <td className="stu"><Area meeting={s.readingMeeting} has={s.hasReading} /></td>
              <td className="stu"><Area meeting={s.writingMeeting} has={s.hasWriting} /></td>
              <td className="stu"><Area meeting={s.mathMeets} has={s.hasMath} /></td>
              <td className="stu">
                <span className="rwm-score" style={{ background: SCORE_HEX[s.score] }}>{s.score}</span>
                <span className="muted"> / 3</span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export default function RWMRollupTree({
  cohort, showAll, viewToggle,
}: { cohort: RWMStudent[]; showAll?: boolean; viewToggle?: ReactNode }) {
  // ── Filter section (2026-11-10): demographics (as on the Reading/Writing trees) + the two RWM
  // scoring toggles from the Student list. Math blanks re-SCORES (pct source flips); the rest FILTER.
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [blankMode, setBlankMode] = useState<'exclude' | 'zero'>('exclude')
  const [completeOnly, setCompleteOnly] = useState(false)
  const gradeOpts = useMemo(
    () => [...new Set(cohort.map((s) => s.grade).filter((g): g is string => !!g))].sort((a, b) => gradeRank(a) - gradeRank(b)),
    [cohort],
  )
  const minRankAvail = gradeOpts.length ? gradeRank(gradeOpts[0]) : 0
  const maxRankAvail = gradeOpts.length ? gradeRank(gradeOpts[gradeOpts.length - 1]) : 0
  const [gradeMinRank, setGradeMinRank] = useState(minRankAvail)
  const [gradeMaxRank, setGradeMaxRank] = useState(maxRankAvail)
  const [gender, setGender] = useState('All')
  const [african, setAfrican] = useState<Tri>('All')
  const [indigenous, setIndigenous] = useState<Tri>('All')
  const genderOpts = useMemo(
    () => [...new Set(cohort.map((s) => s.gender).filter(Boolean) as string[])].sort(),
    [cohort],
  )
  const hasSelfID = useMemo(
    () => cohort.some((s) => s.selfIDAfrican != null || s.selfIDIndigenous != null),
    [cohort],
  )
  const demo: DemoFilter = { gradeMinRank, gradeMaxRank, gender, african, indigenous }
  const anyFilter =
    gradeMinRank !== minRankAvail || gradeMaxRank !== maxRankAvail ||
    gender !== 'All' || african !== 'All' || indigenous !== 'All' || completeOnly
  const resetFilters = () => {
    setGradeMinRank(minRankAvail)
    setGradeMaxRank(maxRankAvail)
    setGender('All')
    setAfrican('All')
    setIndigenous('All')
    setCompleteOnly(false)
    // blankMode is a scoring MODE, not a filter — Reset leaves it alone (same as the Student list).
  }

  const rows = useMemo(() => {
    const pass = demoPass(demo)
    return toRows(cohort, blankMode).filter((s) => pass(s) && (!completeOnly || s.complete))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cohort, blankMode, completeOnly, gradeMinRank, gradeMaxRank, gender, african, indigenous])
  const schools = useMemo(() => {
    const bySchool = new Map<string, { id: string; name: string; students: Row[] }>()
    for (const s of rows) {
      const id = s.schoolId ?? '?'
      let sch = bySchool.get(id)
      if (!sch) {
        sch = { id, name: s.schoolName ?? id, students: [] }
        bySchool.set(id, sch)
      }
      sch.students.push(s)
    }
    return [...bySchool.values()].sort((a, b) => a.name.localeCompare(b.name))
  }, [rows])

  const [summarizeBy, setSummarizeBy] = useState<SummarizeBy>('Grade')
  const [openSchools, setOpenSchools] = useState<Set<string>>(() => new Set(schools.length === 1 ? [schools[0].id] : []))
  const [openNodes, setOpenNodes] = useState<Set<string>>(() => new Set())

  const toggleSchool = (id: string) =>
    setOpenSchools((prev) => {
      const next = new Set(prev)
      next.has(id) ? next.delete(id) : next.add(id)
      return next
    })
  const toggleNode = (id: string) =>
    setOpenNodes((prev) => {
      const next = new Set(prev)
      next.has(id) ? next.delete(id) : next.add(id)
      return next
    })

  // Page-top donut: the score distribution over everything the tree currently shows — rows are
  // already filtered, so the display always represents the data displayed (user rule 2026-11-10).
  const donut = useMemo(() => {
    const t = tallyScores(rows)
    let acc = 0
    const slices = [0, 1, 2, 3].map((score) => {
      const count = t.c[score]
      const startPct = t.total ? (acc / t.total) * 100 : 0
      acc += count
      const endPct = t.total ? (acc / t.total) * 100 : 0
      return { score, color: SCORE_HEX[score], count, pct: t.total ? (count / t.total) * 100 : 0, startPct, endPct }
    })
    const gradient = t.total
      ? slices.filter((s) => s.count > 0).map((s) => `${s.color} ${s.startPct.toFixed(2)}% ${s.endPct.toFixed(2)}%`).join(', ')
      : 'var(--border) 0% 100%'
    return { slices, total: t.total, gradient }
  }, [rows])

  return (
    <div className="math-entry">
      {/* Data display first, controls second, tree third — same order as every other report. */}
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
                  <span className="legend-name">{s.score} of 3 areas Meeting or exceeding</span>
                  <span className="legend-val">{s.pct.toFixed(1)}% · {s.count}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>

      <div className="mtoolbar">
        {viewToggle ? <span className="mtoolbar-view">{viewToggle}</span> : null}
        <span className="mtoolbar-pair">
          <span className="muted">Summarize by</span>
          <div className="subject-toggle" style={{ margin: 0 }}>
            {(['Grade', 'Homeroom'] as SummarizeBy[]).map((m) => (
              <button key={m} className={summarizeBy === m ? 'toggle-on' : ''} onClick={() => setSummarizeBy(m)}>
                {m}
              </button>
            ))}
          </div>
        </span>
        <button className="btn-ghost" onClick={() => setFiltersOpen((v) => !v)}>
          {filtersOpen ? 'Hide filters' : 'Show filters'}{!filtersOpen && anyFilter ? ' (active)' : ''}
        </button>
        {anyFilter ? <button className="btn-ghost" onClick={resetFilters}>Reset</button> : null}
        <span className="spacer" />
        {/* Close-only on purpose, matching the other trees. */}
        <button type="button" className="btn-ghost" onClick={() => { setOpenSchools(new Set()); setOpenNodes(new Set()) }}>
          Collapse all
        </button>
      </div>

      {filtersOpen ? (
        <div className="filter-bar">
          <div className="filter-group">
            <label>Grade</label>
            <div className="filter-row">
              <select value={gradeMinRank} onChange={(e) => setGradeMinRank(Number(e.target.value))}>
                {gradeOpts.map((g) => (
                  <option key={g} value={gradeRank(g)}>{gradeLabel(g)}</option>
                ))}
              </select>
              <span className="muted">to</span>
              <select value={gradeMaxRank} onChange={(e) => setGradeMaxRank(Number(e.target.value))}>
                {gradeOpts.map((g) => (
                  <option key={g} value={gradeRank(g)}>{gradeLabel(g)}</option>
                ))}
              </select>
            </div>
          </div>

          {genderOpts.length > 1 ? (
            <div className="filter-group">
              <label>Gender</label>
              <select value={gender} onChange={(e) => setGender(e.target.value)}>
                <option value="All">All</option>
                {genderOpts.map((g) => (
                  <option key={g} value={g}>{g}</option>
                ))}
              </select>
            </div>
          ) : null}

          {hasSelfID ? (
            <>
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
            </>
          ) : null}

          <div className="filter-group">
            <label>Math blanks</label>
            <div
              className="subject-toggle"
              style={{ margin: 0 }}
              title="How un-recorded Math tasks affect the roll-up (Reading/Writing are unaffected)"
            >
              <button className={blankMode === 'exclude' ? 'toggle-on' : ''} onClick={() => setBlankMode('exclude')}>Excluded</button>
              <button className={blankMode === 'zero' ? 'toggle-on' : ''} onClick={() => setBlankMode('zero')}>Count as 0</button>
            </div>
          </div>

          <div className="filter-group">
            <label>Students</label>
            <div
              className="subject-toggle"
              style={{ margin: 0 }}
              title="Show only students with a result in Reading, Writing, AND Math"
            >
              <button className={!completeOnly ? 'toggle-on' : ''} onClick={() => setCompleteOnly(false)}>All</button>
              <button className={completeOnly ? 'toggle-on' : ''} onClick={() => setCompleteOnly(true)}>All 3 areas only</button>
            </div>
          </div>
        </div>
      ) : null}

      <div className="mlegend">
        <span className="grp"><strong>Students per RWM score</strong></span>
        <span className="grp">
          {[0, 1, 2, 3].map((n) => (
            <Fragment key={n}><span className="sw" style={{ background: SCORE_HEX[n] }} /> {n} </Fragment>
          ))}
          of 3 areas Meeting or exceeding
        </span>
        <span className="grp">% in all 3 = students Meeting or exceeding in Reading, Writing AND Math, out of the row&apos;s students.</span>
      </div>

      {rows.length === 0 ? (
        <div className="notice notice-empty">
          <div className="notice-title">No students match the current filters.</div>
        </div>
      ) : (
      <div className="mtree-wrap">
        <table className="mgrid mtree">
          <thead>
            <tr>
              <th className="col-task">School</th>
              {[0, 1, 2, 3].map((n) => (
                // .swatch (not .sw): .sw is only styled inside .mlegend; .swatch is the global one.
                <th className="rn" key={n}><span className="swatch" style={{ background: SCORE_HEX[n], marginRight: '0.3rem' }} />{n}</th>
              ))}
              <th className="rpct-h">% in all 3</th>
            </tr>
          </thead>
          <tbody>
            {showAll && schools.length > 1
              ? (() => {
                  const allStudents = schools.flatMap((s) => s.students)
                  const tOpen = openSchools.has(TCRCE_ID)
                  return (
                    <Fragment key={TCRCE_ID}>
                      <tr className="tnode lvl1 tcrce">
                        <th className="col-task" onClick={() => toggleSchool(TCRCE_ID)}>
                          <span className="tchev">{tOpen ? '▾' : '▸'}</span>TCRCE<span className="tsub">all schools</span>
                        </th>
                        <CountCells t={tallyScores(allStudents)} />
                      </tr>
                      {tOpen
                        ? childrenOf(allStudents, TCRCE_ID, 'Grade').map((g) => {
                            const gOpen = openNodes.has(g.id)
                            const schoolsForGrade = schools
                              .map((sch) => ({ sch, students: sch.students.filter((s) => (s.grade ?? '?') === g.grades[0]) }))
                              .filter((x) => x.students.length > 0)
                            return (
                              <Fragment key={g.id}>
                                <tr className="tnode lvl2">
                                  <th className="col-task" onClick={() => toggleNode(g.id)}>
                                    <span className="tchev">{gOpen ? '▾' : '▸'}</span>{g.label}
                                  </th>
                                  <CountCells t={tallyScores(g.students)} />
                                </tr>
                                {gOpen
                                  ? schoolsForGrade.map(({ sch, students }) => (
                                      <tr className="tnode lvl3" key={`${g.id}:${sch.id}`}>
                                        <th className="col-task">
                                          <span className="tchev" style={{ visibility: 'hidden' }}>▸</span>{sch.name}
                                        </th>
                                        <CountCells t={tallyScores(students)} />
                                      </tr>
                                    ))
                                  : null}
                              </Fragment>
                            )
                          })
                        : null}
                    </Fragment>
                  )
                })()
              : null}
            {schools.map((sch) => {
              const open = openSchools.has(sch.id)
              return (
                <Fragment key={sch.id}>
                  <tr className="tnode lvl1">
                    <th className="col-task" onClick={() => toggleSchool(sch.id)}>
                      <span className="tchev">{open ? '▾' : '▸'}</span>{sch.name}
                    </th>
                    <CountCells t={tallyScores(sch.students)} />
                  </tr>
                  {open
                    ? childrenOf(sch.students, sch.id, summarizeBy).map((node) => {
                        const nOpen = openNodes.has(node.id)
                        return (
                          <Fragment key={node.id}>
                            <tr className="tnode lvl2">
                              <th className="col-task" onClick={() => toggleNode(node.id)}>
                                <span className="tchev">{nOpen ? '▾' : '▸'}</span>{node.label}
                                {node.sub ? <span className="tsub">{node.sub}</span> : null}
                              </th>
                              <CountCells t={tallyScores(node.students)} />
                            </tr>
                            {nOpen ? (
                              <tr className="blockrow">
                                <td colSpan={6}>
                                  <div className="blockwrap">
                                    <NodeDetail node={node} summarizeBy={summarizeBy} />
                                  </div>
                                </td>
                              </tr>
                            ) : null}
                          </Fragment>
                        )
                      })
                    : null}
                </Fragment>
              )
            })}
          </tbody>
        </table>
      </div>
      )}
    </div>
  )
}
