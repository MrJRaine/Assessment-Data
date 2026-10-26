'use client'

import { Fragment, useState, type ReactNode } from 'react'
import {
  type Counts, type RollupSchool, type RollupStudent, type SummarizeBy, type LangFilter,
  type Measure, type MeasureStat,
  tally, pctOf, childrenOf, gradeLabel, gradeRank,
} from './rollupModel'
import { heatClass, fmtPct } from './math/mathModel' // shared heat scale + % format (cross-subject consistency)

type MeasureMode = 'pct' | 'mean'

// Heat bucket for a 1–4 MEAN score by the writing achievement cut scores (Not Yet < 1.75 < Approaching
// < 2.75 < Meeting < 3.50 <= Exceeding) — so a Mean of ~2 reads as Approaching, not "<50" red.
const meanHeat = (m: number): string => (m >= 3.5 ? 'h4' : m >= 2.75 ? 'h3' : m >= 1.75 ? 'h2' : 'h1')

type BlockState<T> = { status: 'loading' } | { status: 'done'; rows: T[] } | { status: 'error'; message: string }

function StudentsCell({ c }: { c: Counts }) {
  const title = `EN ${c.studentsEN} · FR ${c.studentsFR} · no result ${c.studentsNone}\n(a student assessed in both languages is counted once here)`
  return <td className="rn" title={title}>{c.students}</td>
}
function ResultsCell({ c }: { c: Counts }) {
  return <td className="rn" title={`EN ${c.resultsEN} · FR ${c.resultsFR}`}>{c.results}</td>
}
function MeetCell({ c }: { c: Counts }) {
  const p = pctOf(c.meet, c.band)
  if (p == null) {
    const t = c.ippExcluded > 0 ? `No results with a benchmark level here (${c.ippExcluded} IPP excluded)` : 'No results with a level here'
    return <td className="rpct none" title={t}>—</td>
  }
  const ippNote = c.ippExcluded > 0 ? `\n${c.ippExcluded} IPP result${c.ippExcluded === 1 ? '' : 's'} excluded` : ''
  const title = `Meeting/Exceeding ${c.meet} of ${c.band} results with a level\nEN ${c.meetEN}/${c.bandEN} · FR ${c.meetFR}/${c.bandFR}${ippNote}`
  return <td className={`rpct ${heatClass(p)}`} title={title}>{fmtPct(p)}</td>
}
// One rolled-up measure cell, rendered as either % Meeting/Exceeding or the Mean score (toggle). Mean is
// heat-coloured by normalising the 1–4 scale to 0..1 so it uses the same heat ramp as the %.
function MeasureCell({ stat, mode }: { stat: MeasureStat; mode: MeasureMode }) {
  if (mode === 'mean') {
    const m = stat.count > 0 ? stat.sum / stat.count : null
    if (m == null) {
      const t = stat.ippExcluded > 0 ? `No scored results here (${stat.ippExcluded} IPP excluded)` : 'No scored results here'
      return <td className="rpct none" title={t}>—</td>
    }
    const ippNote = stat.ippExcluded > 0 ? `\n${stat.ippExcluded} IPP excluded` : ''
    const meanEN = stat.countEN > 0 ? (stat.sumEN / stat.countEN).toFixed(2) : '—'
    const meanFR = stat.countFR > 0 ? (stat.sumFR / stat.countFR).toFixed(2) : '—'
    const enfr = `\nEN ${meanEN} (${stat.countEN}) · FR ${meanFR} (${stat.countFR})`
    return <td className={`rpct ${meanHeat(m)}`} title={`Mean ${m.toFixed(2)} over ${stat.count} scored${enfr}${ippNote}`}>{m.toFixed(2)}</td>
  }
  const p = pctOf(stat.meet, stat.band)
  if (p == null) {
    const t = stat.ippExcluded > 0 ? `No results with a level here (${stat.ippExcluded} IPP excluded)` : 'No results with a level here'
    return <td className="rpct none" title={t}>—</td>
  }
  const ippNote = stat.ippExcluded > 0 ? `\n${stat.ippExcluded} IPP excluded` : ''
  const enfr = `\nEN ${stat.meetEN}/${stat.bandEN} · FR ${stat.meetFR}/${stat.bandFR}`
  return <td className={`rpct ${heatClass(p)}`} title={`Meeting/Exceeding ${stat.meet} of ${stat.band}${enfr}${ippNote}`}>{fmtPct(p)}</td>
}

// Generic School → Grade/Homeroom → (expand) student-detail roll-up. The subject wrapper supplies the
// pre-built schools, a per-group loader, and how to render one group's student detail.
// Grade-grouped children of a set of students (used by the TCRCE all-schools row — grade only, no homeroom).
function gradeGroups(students: RollupStudent[]): { grade: string; students: RollupStudent[] }[] {
  const m = new Map<string, RollupStudent[]>()
  for (const s of students) m.set(s.grade, [...(m.get(s.grade) ?? []), s])
  return [...m.entries()]
    .map(([grade, studs]) => ({ grade, students: studs }))
    .sort((a, b) => gradeRank(a.grade) - gradeRank(b.grade))
}

const TCRCE_ID = '__TCRCE__'

export function RollupTree<T>({
  schools, cycle, loadGroup, renderDetail, toolbarExtra, viewToggle, measures, showAll = false,
}: {
  schools: RollupSchool[]
  cycle: string | null
  loadGroup: (groupKey: string, cycle: string | null) => Promise<{ rows: T[]; error: string | null }>
  // summarizeBy lets the detail drop the column already given by the node (a Grade node's drill shows
  // Homeroom, a Homeroom node's drill shows Grade — neither repeats School).
  renderDetail: (rows: T[], lang: LangFilter, summarizeBy: SummarizeBy) => ReactNode
  toolbarExtra?: ReactNode // extra control in the toolbar (e.g. the writing COIL/IOLC toggle)
  viewToggle?: ReactNode // page-level Summary/Student-list switch, rendered inline at the start of the toolbar
  // Per-node measure columns. When supplied (writing = 4 traits + avg), they REPLACE the single
  // % Meeting/Exceeding column and a %/Mean toggle appears. When omitted (reading), the single
  // benchmark-% column (with EN/FR hover) is used.
  measures?: Measure[]
  showAll?: boolean // region-wide caller → show the TCRCE all-schools roll-up row (grade-only)
}) {
  const [summarizeBy, setSummarizeBy] = useState<SummarizeBy>('Grade')
  const [lang, setLang] = useState<LangFilter>('All')
  const [measureMode, setMeasureMode] = useState<MeasureMode>('pct')
  const [openSchools, setOpenSchools] = useState<Set<string>>(
    () => new Set(schools.length === 1 ? [schools[0].id] : []),
  )
  const [openNodes, setOpenNodes] = useState<Set<string>>(() => new Set())
  const [blocks, setBlocks] = useState<Record<string, BlockState<T>>>({})

  const toggleSchool = (id: string) =>
    setOpenSchools((prev) => {
      const next = new Set(prev)
      next.has(id) ? next.delete(id) : next.add(id)
      return next
    })

  function toggleNode(id: string, groupKey: string | null) {
    const opening = !openNodes.has(id)
    setOpenNodes((prev) => {
      const next = new Set(prev)
      opening ? next.add(id) : next.delete(id)
      return next
    })
    if (opening && groupKey && !blocks[groupKey]) {
      setBlocks((prev) => ({ ...prev, [groupKey]: { status: 'loading' } }))
      loadGroup(groupKey, cycle)
        .then((res) =>
          setBlocks((prev) => ({
            ...prev,
            [groupKey]: res.error ? { status: 'error', message: res.error } : { status: 'done', rows: res.rows },
          })),
        )
        .catch(() =>
          setBlocks((prev) => ({ ...prev, [groupKey]: { status: 'error', message: 'Could not load this group. Please retry.' } })),
        )
    }
  }

  const noHomeroomCount = schools.reduce((n, sch) => n + sch.students.filter((s) => !s.homeroomKey).length, 0)

  // Measure columns: writing supplies 4 traits + avg (with a %/Mean toggle); reading uses the single
  // benchmark % column.
  const measureCount = measures ? measures.length : 1
  const measureHead: ReactNode = measures
    ? measures.map((m) => <th className="rpct-h" key={m.key}>{m.label}</th>)
    : <th className="rpct-h">% Meeting/Exceeding</th>
  const measureCells = (students: RollupStudent[]): ReactNode =>
    measures
      ? measures.map((m) => <MeasureCell key={m.key} stat={m.compute(students, lang)} mode={measureMode} />)
      : <MeetCell c={tally(students, lang)} />

  if (schools.length === 0) {
    return (
      <div className="notice notice-empty">
        <div className="notice-title">No students in your scope for this cycle.</div>
      </div>
    )
  }

  return (
    <div className="math-entry">
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
        <span className="mtoolbar-pair">
          <span className="muted">Language of Assessment</span>
          <div className="subject-toggle" style={{ margin: 0 }}>
            {([['All', 'All'], ['EN', 'English'], ['FR', 'French']] as [LangFilter, string][]).map(([v, label]) => (
              <button key={v} className={lang === v ? 'toggle-on' : ''} onClick={() => setLang(v)}>
                {label}
              </button>
            ))}
          </div>
        </span>
        {measures ? (
          <span className="mtoolbar-pair">
            <span className="muted">Show</span>
            <div className="subject-toggle" style={{ margin: 0 }}>
              <button className={measureMode === 'pct' ? 'toggle-on' : ''} onClick={() => setMeasureMode('pct')}>% Meeting/Exceeding</button>
              <button className={measureMode === 'mean' ? 'toggle-on' : ''} onClick={() => setMeasureMode('mean')}>Mean score</button>
            </div>
          </span>
        ) : null}
        {toolbarExtra ? <><span className="spacer" />{toolbarExtra}</> : null}
      </div>

      {measures && measureMode === 'mean' ? (
        <div className="mlegend">
          <span className="grp"><strong>Mean score (1–4)</strong></span>
          <span className="grp">
            <span className="sw h1" /> &lt;1.75 <span className="sw h2" /> 1.75–2.74 <span className="sw h3" /> 2.75–3.49 <span className="sw h4" /> &ge;3.5
          </span>
          <span className="grp">Mean of the 1–4 scores (SCR / not-assessed excluded). IPP / No data excluded.</span>
        </div>
      ) : (
        <div className="mlegend">
          <span className="grp"><strong>% Meeting or Exceeding</strong></span>
          <span className="grp">
            <span className="sw h1" /> &lt;50 <span className="sw h2" /> 50–64 <span className="sw h3" /> 65–80 <span className="sw h4" /> &gt;80
          </span>
          <span className="grp">Out of results with a level. IPP / No data excluded — hover any figure for the EN/FR breakdown.</span>
        </div>
      )}
      {summarizeBy === 'Homeroom' && noHomeroomCount > 0 ? (
        <p className="muted small" style={{ margin: '0 0 .7rem' }}>
          {noHomeroomCount} student{noHomeroomCount === 1 ? ' has' : 's have'} no homeroom in PowerSchool; they are grouped
          under &ldquo;No homeroom&rdquo; and can&apos;t be opened (use Summarize by Grade to see them).
        </p>
      ) : null}

      <div className="mtree-wrap">
        <table className="mgrid mtree">
          <thead>
            <tr>
              <th className="col-task">School</th>
              <th className="rn">Students</th>
              <th className="rn">Results</th>
              {measureHead}
            </tr>
          </thead>
          <tbody>
            {showAll && schools.length > 1
              ? (() => {
                  const allStudents = schools.flatMap((s) => s.students)
                  const tOpen = openSchools.has(TCRCE_ID)
                  const tc = tally(allStudents, lang)
                  if (lang !== 'All' && tc.students === 0) return null
                  return (
                    <Fragment key={TCRCE_ID}>
                      <tr className="tnode lvl1 tcrce">
                        <th className="col-task" onClick={() => toggleSchool(TCRCE_ID)}>
                          <span className="tchev">{tOpen ? '▾' : '▸'}</span>TCRCE<span className="tsub">all schools</span>
                        </th>
                        <StudentsCell c={tc} />
                        <ResultsCell c={tc} />
                        {measureCells(allStudents)}
                      </tr>
                      {tOpen
                        ? gradeGroups(allStudents).map((g) => {
                            const gc = tally(g.students, lang)
                            if (lang !== 'All' && gc.students === 0) return null
                            // TCRCE grade row → expands to a per-SCHOOL breakdown of that grade (counts
                            // only — kept compact; to reach students, open that school in the per-school
                            // tree below).
                            const gradeNodeId = `${TCRCE_ID}:G:${g.grade}`
                            const gOpen = openNodes.has(gradeNodeId)
                            const schoolsForGrade = schools
                              .map((sch) => ({ sch, students: sch.students.filter((s) => s.grade === g.grade) }))
                              .filter((x) => x.students.length > 0)
                            return (
                              <Fragment key={gradeNodeId}>
                                <tr className="tnode lvl2">
                                  <th className="col-task" onClick={() => toggleNode(gradeNodeId, null)}>
                                    <span className="tchev">{gOpen ? '▾' : '▸'}</span>{gradeLabel(g.grade)}
                                  </th>
                                  <StudentsCell c={gc} />
                                  <ResultsCell c={gc} />
                                  {measureCells(g.students)}
                                </tr>
                                {gOpen
                                  ? schoolsForGrade.map(({ sch, students }) => {
                                      const sc = tally(students, lang)
                                      if (lang !== 'All' && sc.students === 0) return null
                                      // Leaf row: counts only. No student drill here (reach students via
                                      // the per-school tree below) — keeps the TCRCE section compact.
                                      return (
                                        <tr className="tnode lvl3" key={`${gradeNodeId}:${sch.id}`}>
                                          <th className="col-task">
                                            <span className="tchev" style={{ visibility: 'hidden' }}>▸</span>{sch.name}
                                          </th>
                                          <StudentsCell c={sc} />
                                          <ResultsCell c={sc} />
                                          {measureCells(students)}
                                        </tr>
                                      )
                                    })
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
              const c = tally(sch.students, lang)
              if (lang !== 'All' && c.students === 0) return null
              return (
                <Fragment key={sch.id}>
                  <tr className="tnode lvl1">
                    <th className="col-task" onClick={() => toggleSchool(sch.id)}>
                      <span className="tchev">{open ? '▾' : '▸'}</span>{sch.name}
                    </th>
                    <StudentsCell c={c} />
                    <ResultsCell c={c} />
                    {measureCells(sch.students)}
                  </tr>
                  {open
                    ? childrenOf(sch, summarizeBy).map((node) => {
                        const nc = tally(node.students, lang)
                        if (lang !== 'All' && nc.students === 0) return null
                        const nOpen = openNodes.has(node.id)
                        const block = node.groupKey ? blocks[node.groupKey] : undefined
                        return (
                          <Fragment key={node.id}>
                            <tr className="tnode lvl2">
                              <th className="col-task" onClick={() => node.groupKey && toggleNode(node.id, node.groupKey)}>
                                <span className="tchev">{node.groupKey ? (nOpen ? '▾' : '▸') : ''}</span>{node.label}
                                {node.sub ? <span className="tsub">{node.sub}</span> : null}
                              </th>
                              <StudentsCell c={nc} />
                              <ResultsCell c={nc} />
                              {measureCells(node.students)}
                            </tr>
                            {nOpen && node.groupKey ? (
                              <tr className="blockrow">
                                <td colSpan={3 + measureCount}>
                                  <div className="blockwrap">
                                    {!block || block.status === 'loading' ? (
                                      <p className="muted small" style={{ margin: 0 }}>Loading students…</p>
                                    ) : block.status === 'error' ? (
                                      <div className="notice notice-error">
                                        <div className="notice-title">Couldn&apos;t load this group</div>
                                        <div className="muted">{block.message}</div>
                                      </div>
                                    ) : (
                                      renderDetail(block.rows, lang, summarizeBy)
                                    )}
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
    </div>
  )
}
