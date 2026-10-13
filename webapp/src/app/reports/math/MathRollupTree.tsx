'use client'

import { Fragment, useMemo, useState } from 'react'
import Link from 'next/link'
import type { MathCohortRow, MathRollupRow } from '@/lib/data'
import {
  type BlankMode, type Grade, type Mark, type Tally, type Unit,
  GRADE_ORDER, gradeLabel, heatClass, rk, buildGrades, buildMarks, countUnit, unitStat, meanOf,
  emptyTally, unitBucket, overallBucket, pctMeeting, tallyTitle, fmtPct,
} from './mathModel'
import { BandCell, TaskCell } from './mathCells'
import { loadMathGroup } from './actions'

// ── Reports > Math OVERSIGHT roll-up tree (math-reports #2, Phase 1). Replaces the card picker for
// Administrator / SpecialistTeacher / RegionalAnalyst; teachers keep the cards.
//
//   School → [Summarize by: Grade | Homeroom] → per-grade block (students as rows)
//
// School and Grade/Homeroom rows share one set of columns: Overall + one per unit, pooled by unit
// NAME across grades (tasks differ by grade, unit names line up). Each cell = % of students at
// Meeting or In-depth, out of students WITH a level; IPP / No data / Incomplete are left out of the
// % and listed in the hover. Expanding a Grade/Homeroom row loads that group's matrix on demand and
// shows one block per grade, with that grade's own unit columns that expand into task columns.

type SummarizeBy = 'Grade' | 'Homeroom'

interface UnitCounts { order: number; taskCount: number; scored: number; canDo: number }
interface TreeStudent {
  key: string
  grade: string
  homeroom: string | null
  homeroomKey: string | null
  schoolId: string
  ipp: boolean
  units: Map<string, UnitCounts>
}
interface School { id: string; name: string; students: TreeStudent[] }
interface ChildNode {
  id: string
  label: string
  sub: string | null
  groupKey: string | null // tvf_StudentCohortMath key; null = can't open (no homeroom)
  grades: string[]
  students: TreeStudent[]
}
interface Summary { n: number; overall: Tally; units: Record<string, Tally> }
type BlockState = { status: 'loading' } | { status: 'done'; rows: MathCohortRow[] } | { status: 'error'; message: string }

function summarize(students: TreeStudent[], unitNames: string[], blankMode: BlankMode): Summary {
  const overall = emptyTally()
  const units: Record<string, Tally> = {}
  for (const name of unitNames) units[name] = emptyTally()
  for (const s of students) {
    const avgs: (number | null)[] = []
    for (const [name, c] of s.units) {
      // An IPP student's unmarked task is an IPP cell (not in scope) — same rule as the matrix.
      const ippCells = s.ipp ? c.taskCount - c.scored : 0
      const st = unitStat({ inScope: c.taskCount - ippCells, filled: c.scored, ones: c.canDo, ipp: ippCells }, blankMode)
      units[name][unitBucket(st)]++
      avgs.push(st.avg)
    }
    overall[overallBucket(meanOf(avgs), s.ipp)]++
  }
  return { n: students.length, overall, units }
}

const tallyTotal = (t: Tally) => t.b1 + t.b2 + t.b3 + t.b4 + t.inc + t.ipp + t.none

function RollupCell({ t, sticky }: { t: Tally; sticky?: boolean }) {
  if (tallyTotal(t) === 0) {
    return <td className={`rpct none${sticky ? ' col-pct' : ''}`} title="No students here have this unit">—</td>
  }
  const p = pctMeeting(t)
  return (
    <td className={`rpct ${heatClass(p)}${sticky ? ' col-pct' : ''}`} title={tallyTitle(t)}>
      {fmtPct(p)}
    </td>
  )
}

export default function MathRollupTree({ rows, cycle }: { rows: MathRollupRow[]; cycle: string | null }) {
  const { schools, unitNames } = useMemo(() => {
    const byKey = new Map<string, TreeStudent>()
    const unitOrder = new Map<string, number>()
    const schoolNames = new Map<string, string>()
    for (const r of rows) {
      let s = byKey.get(r.studentKey)
      if (!s) {
        s = {
          key: r.studentKey, grade: r.grade, homeroom: r.homeroom, homeroomKey: r.homeroomKey,
          schoolId: r.schoolId, ipp: r.mathIPP, units: new Map(),
        }
        byKey.set(r.studentKey, s)
        schoolNames.set(r.schoolId, r.schoolName ?? r.schoolId)
      }
      if (r.unitName) {
        s.units.set(r.unitName, { order: r.unitOrder, taskCount: r.taskCount, scored: r.scoredCount, canDo: r.canDoCount })
        unitOrder.set(r.unitName, Math.min(unitOrder.get(r.unitName) ?? Infinity, r.unitOrder))
      }
    }
    const unitNames = [...unitOrder.keys()].sort(
      (a, b) => unitOrder.get(a)! - unitOrder.get(b)! || a.localeCompare(b, undefined, { numeric: true }),
    )
    const bySchool = new Map<string, School>()
    for (const s of byKey.values()) {
      let sch = bySchool.get(s.schoolId)
      if (!sch) {
        sch = { id: s.schoolId, name: schoolNames.get(s.schoolId) ?? s.schoolId, students: [] }
        bySchool.set(s.schoolId, sch)
      }
      sch.students.push(s)
    }
    const schools = [...bySchool.values()].sort((a, b) => a.name.localeCompare(b.name))
    return { schools, unitNames }
  }, [rows])

  const [summarizeBy, setSummarizeBy] = useState<SummarizeBy>('Grade')
  const [blankMode, setBlankMode] = useState<BlankMode>('exclude')
  // A school admin with one school lands with it open; everyone else starts fully collapsed.
  const [openSchools, setOpenSchools] = useState<Set<string>>(
    () => new Set(schools.length === 1 ? [schools[0].id] : []),
  )
  const [openNodes, setOpenNodes] = useState<Set<string>>(() => new Set())
  const [blocks, setBlocks] = useState<Record<string, BlockState>>({})

  function childrenOf(sch: School): ChildNode[] {
    const groups = new Map<string, TreeStudent[]>()
    for (const s of sch.students) {
      const k = summarizeBy === 'Grade' ? s.grade : s.homeroomKey ?? ''
      groups.set(k, [...(groups.get(k) ?? []), s])
    }
    const nodes: ChildNode[] = [...groups.entries()].map(([k, students]) => {
      const grades = [...new Set(students.map((s) => s.grade))].sort((a, b) => (GRADE_ORDER[a] ?? 99) - (GRADE_ORDER[b] ?? 99))
      if (summarizeBy === 'Grade') {
        return { id: `G:${sch.id}:${k}`, label: gradeLabel(k), sub: null, groupKey: `GRADE:${sch.id}:${k}`, grades, students }
      }
      const hr = students[0].homeroom
      return {
        id: `H:${sch.id}:${k}`,
        label: k && hr ? `Homeroom ${hr}` : 'No homeroom',
        sub: grades.map(gradeLabel).join(', '),
        groupKey: k || null,
        grades,
        students,
      }
    })
    return nodes.sort((a, b) => {
      const ga = GRADE_ORDER[a.grades[0]] ?? 99
      const gb = GRADE_ORDER[b.grades[0]] ?? 99
      return ga - gb || a.label.localeCompare(b.label, undefined, { numeric: true })
    })
  }

  const toggleSchool = (id: string) =>
    setOpenSchools((prev) => {
      const next = new Set(prev)
      next.has(id) ? next.delete(id) : next.add(id)
      return next
    })

  function toggleNode(node: ChildNode) {
    const opening = !openNodes.has(node.id)
    setOpenNodes((prev) => {
      const next = new Set(prev)
      opening ? next.add(node.id) : next.delete(node.id)
      return next
    })
    const gk = node.groupKey
    if (opening && gk && !blocks[gk]) {
      setBlocks((prev) => ({ ...prev, [gk]: { status: 'loading' } }))
      loadMathGroup(gk, cycle)
        .then((res) =>
          setBlocks((prev) => ({
            ...prev,
            [gk]: res.error ? { status: 'error', message: res.error } : { status: 'done', rows: res.rows },
          })),
        )
        .catch(() =>
          setBlocks((prev) => ({ ...prev, [gk]: { status: 'error', message: 'Could not load this group. Please retry.' } })),
        )
    }
  }

  const colCount = 3 + unitNames.length
  const noHomeroomCount = schools.reduce((n, sch) => n + sch.students.filter((s) => !s.homeroomKey).length, 0)

  return (
    <div className="math-entry">
      <div className="mtoolbar">
        <span className="muted">Summarize by</span>
        <div className="subject-toggle" style={{ margin: 0 }}>
          {(['Grade', 'Homeroom'] as SummarizeBy[]).map((m) => (
            <button key={m} className={summarizeBy === m ? 'toggle-on' : ''} onClick={() => setSummarizeBy(m)}>
              {m}
            </button>
          ))}
        </div>
        <span className="spacer" />
        <button className="btn-ghost" onClick={() => setBlankMode((m) => (m === 'exclude' ? 'zero' : 'exclude'))}>
          Blanks: {blankMode === 'exclude' ? 'excluded' : 'count as 0'}
        </button>
      </div>

      <div className="mlegend">
        <span className="grp"><strong>% Meeting or In-depth</strong></span>
        <span className="grp">
          <span className="sw h1" /> &lt;50 <span className="sw h2" /> 50–64 <span className="sw h3" /> 65–80 <span className="sw h4" /> &gt;80
        </span>
        <span className="grp">Out of students with a level. IPP, No data and Incomplete are left out — hover a cell for the counts.</span>
      </div>
      {summarizeBy === 'Homeroom' && noHomeroomCount > 0 ? (
        <p className="muted small" style={{ margin: '0 0 .7rem' }}>
          {noHomeroomCount} student{noHomeroomCount === 1 ? ' has' : 's have'} no homeroom in PowerSchool. They are
          counted under &ldquo;No homeroom&rdquo;; to see their task results, use Summarize by Grade.
        </p>
      ) : null}

      <div className="mtree-wrap">
        <table className="mgrid mtree">
          <thead>
            <tr>
              <th className="col-task">School</th>
              <th className="rn">Students</th>
              <th className="rpct-h">Overall</th>
              {unitNames.map((u) => <th className="rpct-h" key={u}>{u}</th>)}
            </tr>
          </thead>
          <tbody>
            {schools.map((sch) => {
              const open = openSchools.has(sch.id)
              const s = summarize(sch.students, unitNames, blankMode)
              return (
                <Fragment key={sch.id}>
                  <tr className="tnode lvl1">
                    <th className="col-task" onClick={() => toggleSchool(sch.id)}>
                      <span className="tchev">{open ? '▾' : '▸'}</span>{sch.name}
                    </th>
                    <td className="rn">{s.n}</td>
                    <RollupCell t={s.overall} />
                    {unitNames.map((u) => <RollupCell key={u} t={s.units[u]} />)}
                  </tr>
                  {open && childrenOf(sch).map((node) => {
                    const nOpen = openNodes.has(node.id)
                    const ns = summarize(node.students, unitNames, blankMode)
                    return (
                      <Fragment key={node.id}>
                        <tr className="tnode lvl2">
                          <th className="col-task" onClick={() => toggleNode(node)}>
                            <span className="tchev">{nOpen ? '▾' : '▸'}</span>{node.label}
                            {node.sub ? <span className="tsub">{node.sub}</span> : null}
                          </th>
                          <td className="rn">{ns.n}</td>
                          <RollupCell t={ns.overall} />
                          {unitNames.map((u) => <RollupCell key={u} t={ns.units[u]} />)}
                        </tr>
                        {nOpen ? (
                          <tr className="blockrow">
                            <td colSpan={colCount}>
                              <div className="blockwrap">
                                <GroupBlock
                                  node={node}
                                  state={node.groupKey ? blocks[node.groupKey] : undefined}
                                  blankMode={blankMode}
                                  cycle={cycle}
                                />
                              </div>
                            </td>
                          </tr>
                        ) : null}
                      </Fragment>
                    )
                  })}
                </Fragment>
              )
            })}
          </tbody>
        </table>
      </div>
    </div>
  )
}

// ── One expanded Grade/Homeroom: a block per grade (a split homeroom shows one per grade) ──────────
function GroupBlock({
  node, state, blankMode, cycle,
}: { node: ChildNode; state: BlockState | undefined; blankMode: BlankMode; cycle: string | null }) {
  if (!node.groupKey) {
    return (
      <p className="muted small" style={{ margin: 0 }}>
        These students have no homeroom in PowerSchool, so they can&apos;t be opened as a group here. Use Summarize by
        Grade to see their task results.
      </p>
    )
  }
  if (!state || state.status === 'loading') return <p className="muted small" style={{ margin: 0 }}>Loading results…</p>
  if (state.status === 'error') {
    return (
      <div className="notice notice-error">
        <div className="notice-title">Couldn&apos;t load this group</div>
        <div className="muted">{state.message}</div>
      </div>
    )
  }
  const grades = buildGrades(state.rows)
  const marks = buildMarks(state.rows)
  const loaded = new Set(grades.map((g) => g.grade))
  const missing = node.grades.filter((g) => !loaded.has(g))
  const href = `/reports/math/${encodeURIComponent(node.groupKey)}${cycle ? `?cycle=${encodeURIComponent(cycle)}` : ''}`
  return (
    <>
      <div className="mtoolbar" style={{ marginBottom: '.4rem' }}>
        <span className="spacer" />
        <Link href={href} prefetch={false} className="small">Open the full class view (charts, tasks down) ↗</Link>
      </div>
      {missing.map((g) => (
        <p className="muted small" key={g} style={{ margin: '0 0 .5rem' }}>
          <strong>{gradeLabel(g)}:</strong> no math tasks are set up for this grade yet, so these students show as No data.
        </p>
      ))}
      {grades.map((g) => (
        <GradeBlock key={g.grade} g={g} marks={marks} blankMode={blankMode} showHead={grades.length > 1} />
      ))}
    </>
  )
}

// ── Students as rows; this grade's units as columns, each expanding into its task columns ─────────
function GradeBlock({
  g, marks, blankMode, showHead,
}: { g: Grade; marks: Record<string, Mark>; blankMode: BlankMode; showHead: boolean }) {
  const [collapsed, setCollapsed] = useState<Set<string>>(() => new Set(g.units.map((u) => u.name)))
  const toggle = (name: string) =>
    setCollapsed((prev) => {
      const next = new Set(prev)
      next.has(name) ? next.delete(name) : next.add(name)
      return next
    })
  const mark = (studentKey: string, taskKey: string): Mark => marks[rk(studentKey, taskKey)] ?? 'blank'
  const stat = (studentKey: string, u: Unit) => unitStat(countUnit((t) => mark(studentKey, t), u), blankMode)

  // Summary row tallies: overall + per unit (students), and per task (cells).
  const overall = emptyTally()
  const unitT: Record<string, Tally> = {}
  for (const u of g.units) unitT[u.name] = emptyTally()
  for (const s of g.students) {
    const avgs = g.units.map((u) => {
      const st = stat(s.studentKey, u)
      unitT[u.name][unitBucket(st)]++
      return st.avg
    })
    overall[overallBucket(meanOf(avgs), s.mathIPP)]++
  }
  function taskSummary(taskKey: string) {
    let yes = 0, no = 0, ipp = 0, blank = 0
    for (const s of g.students) {
      const v = mark(s.studentKey, taskKey)
      if (v === '1') yes++
      else if (v === '0') no++
      else if (v === 'ipp') ipp++
      else blank++
    }
    const p = yes + no === 0 ? null : yes / (yes + no)
    return { p, title: `Can do: ${yes}\nCannot: ${no}\nIPP: ${ipp}\nNot scored: ${blank}` }
  }

  return (
    <section className="mgrade" style={{ marginBottom: '1rem' }}>
      {showHead ? (
        <div className="mghead">
          <h3>{g.label}</h3>
          <span className="gc">· {g.students.length} student{g.students.length === 1 ? '' : 's'}</span>
        </div>
      ) : null}
      <div className="mscroll">
        <table className="mgrid">
          <thead>
            <tr>
              <th className="col-task">Student</th>
              <th className="col-pct">Overall</th>
              {g.units.map((u) => {
                const coll = collapsed.has(u.name)
                return (
                  <th key={u.name} className="stu unitcol" colSpan={coll ? 1 : u.tasks.length} onClick={() => toggle(u.name)}>
                    <span className="chev">{coll ? '▸' : '▾'}</span> {u.name}
                  </th>
                )
              })}
            </tr>
            <tr>
              <th className="col-task" />
              <th className="col-pct" />
              {g.units.flatMap((u) =>
                collapsed.has(u.name)
                  ? [<th className="stu" key={`${u.name}-sum`}>Unit</th>]
                  : u.tasks.map((t) => (
                      <th
                        className="stu qcol"
                        key={t.mathTaskKey}
                        title={[t.description, t.outcomeCode].filter(Boolean).join('\n')}
                      >
                        {t.questionNumber}
                      </th>
                    )),
              )}
            </tr>
          </thead>
          <tbody>
            <tr className="sumrow">
              <th className="col-task" scope="row">
                <span className="uname">All students</span>
                <span className="tsub">units: % Meeting+ · tasks: % can do</span>
              </th>
              <RollupCell t={overall} sticky />
              {g.units.flatMap((u) => {
                if (collapsed.has(u.name)) return [<RollupCell key={`${u.name}-sum`} t={unitT[u.name]} />]
                return u.tasks.map((t) => {
                  const ts = taskSummary(t.mathTaskKey)
                  return (
                    <td key={t.mathTaskKey} className={`rpct ${heatClass(ts.p)}`} title={ts.title}>
                      {fmtPct(ts.p)}
                    </td>
                  )
                })
              })}
            </tr>
            {g.students.map((s) => {
              const avgs: (number | null)[] = []
              const cells = g.units.flatMap((u) => {
                const st = stat(s.studentKey, u)
                avgs.push(st.avg)
                if (collapsed.has(u.name)) {
                  return [
                    <td className="stu" key={`${u.name}-sum`}>
                      <BandCell avg={st.avg} ipp={st.ipp} incomplete={st.incomplete} />
                    </td>,
                  ]
                }
                return u.tasks.map((t) => (
                  <td className="cell stu" key={t.mathTaskKey}><TaskCell v={mark(s.studentKey, t.mathTaskKey)} /></td>
                ))
              })
              const r = meanOf(avgs)
              return (
                <tr key={s.studentKey}>
                  <th className="col-task" scope="row" title={s.fullName}>{s.name}</th>
                  <td className="col-pct"><BandCell avg={r} ipp={s.mathIPP && r == null} incomplete={false} /></td>
                  {cells}
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </section>
  )
}
