'use client'

import { useMemo, useState } from 'react'
import type { MathCohortRow } from '@/lib/data'

// ── Read-only math results matrix for Reports. Styled to look like the data-entry grid (same
// .mgrid / .mband / .mtoggle classes) but nothing is editable. Pulls ALL of the current year's math
// cycles as a single latest-result-per-task matrix, groups tasks by unit, and rolls up per-student
// and per-cohort averages for the colour-coding + the two charts. P-6 only (the TVF enforces it).

type Mark = '1' | '0' | 'ipp' | 'blank'
const rk = (studentKey: string, taskKey: string) => `${studentKey}:${taskKey}`

interface Task {
  mathTaskKey: string
  unitName: string
  unitOrder: number
  questionNumber: string
  displayOrder: number
  outcomeCode: string | null
  description: string
}
interface Unit { name: string; order: number; tasks: Task[] }
interface Student { studentKey: string; studentNumber: string; name: string; fullName: string; mathIPP: boolean }
interface Grade { grade: string; order: number; label: string; students: Student[]; units: Unit[] }

const GRADE_ORDER: Record<string, number> = { PP: -1, P: 0, '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6 }
const gradeLabel = (g: string) => (g === 'P' ? 'Primary' : g === 'PP' ? 'Pre-Primary' : `Grade ${g}`)

// Entry-grid achievement bands, applied to an average in [0,1].
const BAND_HEX: Record<string, string> = { b1: '#b23347', b2: '#c07d16', b3: '#2f8f4e', b4: '#0092c9' }
const BANDS: { cls: string; name: string }[] = [
  { cls: 'b1', name: 'Emerging' },
  { cls: 'b2', name: 'Developing' },
  { cls: 'b3', name: 'Meeting' },
  { cls: 'b4', name: 'In-depth' },
]
function bandForAvg(avg: number): { cls: string; label: string } {
  if (avg < 0.5) return { cls: 'b1', label: 'Emerging' } // <50%
  if (avg < 0.75) return { cls: 'b2', label: 'Developing' } // 50–<75%
  if (avg < 0.9) return { cls: 'b3', label: 'Meeting' } // 75–<90%
  return { cls: 'b4', label: 'In-depth' } // ≥90%
}
function heatClass(p: number | null) {
  return p == null ? 'none' : p > 0.8 ? 'h4' : p >= 0.65 ? 'h3' : p >= 0.5 ? 'h2' : 'h1'
}

function buildGrades(rows: MathCohortRow[]): Grade[] {
  const byGrade = new Map<string, Grade>()
  for (const r of rows) {
    const g = r.grade ?? '?'
    let grade = byGrade.get(g)
    if (!grade) {
      grade = { grade: g, order: GRADE_ORDER[g] ?? 99, label: gradeLabel(g), students: [], units: [] }
      byGrade.set(g, grade)
    }
    if (!grade.students.some((s) => s.studentKey === r.studentKey)) {
      grade.students.push({
        studentKey: r.studentKey,
        studentNumber: r.studentNumber,
        name: `${r.firstName} ${r.lastName.charAt(0)}.`,
        fullName: `${r.firstName} ${r.lastName}`,
        mathIPP: r.mathIPPStatus === true,
      })
    }
    let unit = grade.units.find((u) => u.name === (r.unitName ?? ''))
    if (!unit) {
      unit = { name: r.unitName ?? '', order: r.unitOrder ?? 0, tasks: [] }
      grade.units.push(unit)
    }
    if (!unit.tasks.some((t) => t.mathTaskKey === r.mathTaskKey)) {
      unit.tasks.push({
        mathTaskKey: r.mathTaskKey,
        unitName: r.unitName ?? '',
        unitOrder: r.unitOrder ?? 0,
        questionNumber: r.questionNumber ?? '',
        displayOrder: r.displayOrder ?? 0,
        outcomeCode: r.outcomeCode,
        description: r.description ?? '',
      })
    }
  }
  const grades = [...byGrade.values()].sort((a, b) => a.order - b.order)
  for (const g of grades) {
    g.students.sort((a, b) => a.name.localeCompare(b.name))
    g.units.sort((a, b) => a.order - b.order)
    for (const u of g.units) u.tasks.sort((a, b) => a.displayOrder - b.displayOrder)
  }
  return grades
}

function buildMarks(rows: MathCohortRow[]): Record<string, Mark> {
  const m: Record<string, Mark> = {}
  for (const r of rows) {
    const key = rk(r.studentKey, r.mathTaskKey)
    if (r.result === true) m[key] = '1'
    else if (r.result === false) m[key] = '0'
    else m[key] = r.mathIPPStatus === true ? 'ipp' : 'blank'
  }
  return m
}

// blankMode wires the "count blanks or not" decision the user asked to leave adjustable:
//  'exclude' (default) — a blank task doesn't count toward the average (denominator = filled cells).
//  'zero'              — a blank counts as a miss (denominator = every in-scope, non-IPP task).
type BlankMode = 'exclude' | 'zero'

export default function MathCohortView({ rows }: { rows: MathCohortRow[] }) {
  const grades = useMemo(() => buildGrades(rows), [rows])
  const marks = useMemo(() => buildMarks(rows), [rows])

  const [collapsedUnits, setCollapsedUnits] = useState<Set<string>>(new Set())
  const [axis, setAxis] = useState<'tasksDown' | 'studentsDown'>('tasksDown')
  const [blankMode, setBlankMode] = useState<BlankMode>('exclude')
  const [focusKey, setFocusKey] = useState<string | null>(null)

  const mark = (studentKey: string, taskKey: string): Mark => marks[rk(studentKey, taskKey)] ?? 'blank'
  const uk = (g: Grade, u: Unit) => `${g.grade}:${u.name}`
  const toggleUnit = (key: string) =>
    setCollapsedUnits((prev) => {
      const next = new Set(prev)
      next.has(key) ? next.delete(key) : next.add(key)
      return next
    })

  // ── per-student, per-unit average (blanks + IPP handled per blankMode; IPP never counts) ──────
  // Returns null when the student has no scorable data in the unit (all blank in exclude mode, or
  // all IPP). `incomplete` mirrors the entry grid's <80%-filled nudge for the DISPLAYED band only.
  function unitAvg(studentKey: string, u: Unit): { avg: number | null; ipp: boolean; incomplete: boolean } {
    let inScope = 0, filled = 0, ones = 0, ipp = 0
    for (const t of u.tasks) {
      const v = mark(studentKey, t.mathTaskKey)
      if (v === 'ipp') { ipp++; continue }
      inScope++
      if (v === '1' || v === '0') { filled++; if (v === '1') ones++ }
    }
    if (inScope === 0) return { avg: null, ipp: ipp > 0, incomplete: false } // all IPP
    const denom = blankMode === 'zero' ? inScope : filled
    if (denom === 0) return { avg: null, ipp: false, incomplete: false } // nothing scored
    return { avg: ones / denom, ipp: ipp > 0, incomplete: blankMode === 'exclude' && filled / inScope < 0.8 }
  }

  // The per-student roll-up = the mean of that student's unit averages (units with data only).
  function rollup(studentKey: string, g: Grade): number | null {
    const avgs: number[] = []
    for (const u of g.units) {
      const s = unitAvg(studentKey, u)
      if (s.avg != null) avgs.push(s.avg)
    }
    return avgs.length ? avgs.reduce((a, b) => a + b, 0) / avgs.length : null
  }

  // Class % for a single task = share of scored (1/0) cells that are 1, across the given students.
  function taskPct(students: Student[], taskKey: string): number | null {
    let scored = 0, ones = 0
    for (const s of students) {
      const v = mark(s.studentKey, taskKey)
      if (v === '1' || v === '0') { scored++; if (v === '1') ones++ }
    }
    return scored === 0 ? null : ones / scored
  }
  // Cohort roll-up for a unit = mean of the students' unit averages (colours the collapsed unit row).
  function unitCohort(students: Student[], u: Unit): number | null {
    const avgs: number[] = []
    for (const s of students) {
      const a = unitAvg(s.studentKey, u).avg
      if (a != null) avgs.push(a)
    }
    return avgs.length ? avgs.reduce((a, b) => a + b, 0) / avgs.length : null
  }

  // Per-student band cell (unit or overall roll-up).
  function bandCell(avg: number | null, ipp: boolean, incomplete: boolean) {
    if (avg == null) return <span className={`mband ${ipp ? 'bipp' : 'inc'}`}>{ipp ? 'IPP' : '—'}</span>
    if (incomplete) return <span className="mband inc">Incomplete</span>
    const b = bandForAvg(avg)
    return <span className={`mband ${b.cls}`}>{b.label}</span>
  }
  // A single task cell, drawn identically to the entry grid but not interactive.
  function taskCell(v: Mark) {
    const cls = v === '1' ? 'yes' : v === '0' ? 'no' : v === 'ipp' ? 'ipp' : 'blank'
    return (
      <span className={`mtoggle ${cls}`} aria-hidden={v === 'blank'}>
        {v === '0' ? <span className="ring" /> : v === '1' ? (
          <svg className="check" viewBox="0 0 24 24">
            <path className="edge" d="M3.6 12.6 Q8.06 14.43 9.6 19 Q13.1 10.53 20.4 5" />
            <path className="fill" d="M3.6 12.6 Q8.06 14.43 9.6 19 Q13.1 10.53 20.4 5" />
          </svg>
        ) : v === 'ipp' ? 'IPP' : ''}
      </span>
    )
  }

  // ── charts (group view): donut of overall roll-ups + stacked bars by unit name ────────────────
  const measuredStudents = useMemo(
    () => grades.flatMap((g) => g.students.filter((s) => !s.mathIPP).map((s) => ({ s, g }))),
    [grades],
  )
  const donut = useMemo(() => {
    const counts: Record<string, number> = { b1: 0, b2: 0, b3: 0, b4: 0 }
    let total = 0
    for (const { s, g } of measuredStudents) {
      const r = rollup(s.studentKey, g)
      if (r == null) continue
      counts[bandForAvg(r).cls]++
      total++
    }
    let acc = 0
    const slices = BANDS.map((b) => {
      const count = counts[b.cls]
      const startPct = total ? (acc / total) * 100 : 0
      acc += count
      const endPct = total ? (acc / total) * 100 : 0
      return { ...b, color: BAND_HEX[b.cls], count, pct: total ? (count / total) * 100 : 0, startPct, endPct }
    })
    const gradient = total
      ? slices.filter((s) => s.count > 0).map((s) => `${s.color} ${s.startPct.toFixed(2)}% ${s.endPct.toFixed(2)}%`).join(', ')
      : 'var(--border) 0% 100%'
    return { slices, total, gradient }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [measuredStudents, blankMode])

  // By-unit distribution: pool units by NAME across grades present, bucket measured students by their
  // unit band. Replaces the reading/writing "achievement by month" chart.
  const unitBars = useMemo(() => {
    const names: string[] = []
    for (const g of grades) for (const u of g.units) if (!names.includes(u.name)) names.push(u.name)
    return names.map((name) => {
      const counts: Record<string, number> = { b1: 0, b2: 0, b3: 0, b4: 0 }
      let total = 0
      for (const { s, g } of measuredStudents) {
        const u = g.units.find((x) => x.name === name)
        if (!u) continue
        const a = unitAvg(s.studentKey, u).avg
        if (a == null) continue
        counts[bandForAvg(a).cls]++
        total++
      }
      return { name, counts, total }
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [measuredStudents, blankMode])
  const unitMax = useMemo(() => Math.max(1, ...unitBars.map((u) => u.total)), [unitBars])

  const focus = focusKey ? measuredStudentsAll(grades).find((x) => x.s.studentKey === focusKey) ?? null : null

  return (
    <div className="math-entry">
      {/* Controls: axis flip + blanks handling (the blanks toggle is the wired-in GUI knob). */}
      {!focus && (
        <div className="mtoolbar">
          <span className="muted">Read-only results across this year&apos;s cycles · latest result per task</span>
          <span className="spacer" />
          <button className="btn-ghost" onClick={() => setAxis((a) => (a === 'tasksDown' ? 'studentsDown' : 'tasksDown'))}>
            {axis === 'tasksDown' ? 'Show students down ↓' : 'Show tasks down ↓'}
          </button>
          <button className="btn-ghost" onClick={() => setBlankMode((m) => (m === 'exclude' ? 'zero' : 'exclude'))}>
            Blanks: {blankMode === 'exclude' ? 'excluded' : 'count as 0'}
          </button>
        </div>
      )}

      {/* legend (shared with entry) */}
      {!focus && (
        <div className="mlegend">
          <span className="grp"><strong>Achievement Level</strong></span>
          <span className="grp"><span className="mband b1">Emerging</span>&lt;50%</span>
          <span className="grp"><span className="mband b2">Developing</span>50–&lt;75%</span>
          <span className="grp"><span className="mband b3">Meeting</span>75–&lt;90%</span>
          <span className="grp"><span className="mband b4">In-depth</span>≥90%</span>
          <span className="grp"><strong>Class %</strong>
            <span className="sw h1" /> &lt;50 <span className="sw h2" /> 50–64 <span className="sw h3" /> 65–80 <span className="sw h4" /> &gt;80
          </span>
        </div>
      )}

      {/* charts */}
      {!focus && (
        <div className="cohort-charts">
          <div className="chart-card">
            <div className="chart-title">Roll-up distribution</div>
            <div className="donut-wrap">
              <div className="donut" style={{ background: `conic-gradient(${donut.gradient})` }}>
                <div className="donut-hole">
                  <div className="donut-total">{donut.total}</div>
                  <div className="donut-label">STUDENTS</div>
                </div>
              </div>
              <ul className="donut-legend">
                {donut.slices.map((s) => (
                  <li key={s.cls}>
                    <span className="swatch" style={{ background: s.color }} />
                    <span className="legend-name">{s.name}</span>
                    <span className="legend-val">{s.pct.toFixed(1)}% · {s.count}</span>
                  </li>
                ))}
              </ul>
            </div>
            {donut.total === 0 ? <div className="muted chart-empty">No measured students with math results yet.</div> : null}
          </div>

          <div className="chart-card">
            <div className="chart-title">Achievement by unit</div>
            <div className="monthbars">
              {unitBars.map((u) => (
                <div key={u.name} className="monthbar">
                  <div className="monthbar-stack">
                    {BANDS.map((b) => {
                      const v = u.counts[b.cls]
                      if (!v) return null
                      return (
                        <div
                          key={b.cls}
                          className="monthbar-seg"
                          style={{ height: `${(v / unitMax) * 100}%`, background: BAND_HEX[b.cls] }}
                          title={`${b.name}: ${v}`}
                        />
                      )
                    })}
                  </div>
                  <div className="monthbar-label" title={u.name}>{u.name}</div>
                </div>
              ))}
            </div>
            <ul className="bar-legend">
              {BANDS.map((b) => (
                <li key={b.cls}><span className="swatch" style={{ background: BAND_HEX[b.cls] }} />{b.name}</li>
              ))}
            </ul>
          </div>
        </div>
      )}

      {/* single-student drill-down */}
      {focus ? (
        <StudentGrid
          student={focus.s}
          grade={focus.g}
          rollup={rollup(focus.s.studentKey, focus.g)}
          unitAvg={unitAvg}
          mark={mark}
          bandCell={bandCell}
          taskCell={taskCell}
          onBack={() => setFocusKey(null)}
        />
      ) : (
        grades.map((g) => {
          const students = g.students
          return (
            <section className="mgrade" key={g.grade}>
              <div className="mghead">
                <h3>{g.label}</h3>
                <span className="gc">· {students.length} student{students.length === 1 ? '' : 's'}</span>
              </div>
              {g.units.length === 0 ? (
                <div className="no-tasks"><strong>No math tasks configured for {g.label} yet.</strong></div>
              ) : axis === 'tasksDown' ? (
                <TasksDown
                  g={g} students={students} collapsed={collapsedUnits} uk={uk} toggleUnit={toggleUnit}
                  mark={mark} unitAvg={unitAvg} rollup={rollup} taskPct={taskPct} unitCohort={unitCohort}
                  bandCell={bandCell} taskCell={taskCell} onFocus={setFocusKey}
                />
              ) : (
                <StudentsDown
                  g={g} students={students} collapsed={collapsedUnits} uk={uk} toggleUnit={toggleUnit}
                  mark={mark} unitAvg={unitAvg} rollup={rollup}
                  bandCell={bandCell} taskCell={taskCell} onFocus={setFocusKey}
                />
              )}
            </section>
          )
        })
      )}
    </div>
  )
}

function measuredStudentsAll(grades: Grade[]) {
  return grades.flatMap((g) => g.students.map((s) => ({ s, g })))
}

// ── tasks-down: units/tasks as rows, students as columns (the entry-grid orientation) ────────────
function TasksDown({
  g, students, collapsed, uk, toggleUnit, mark, unitAvg, rollup, taskPct, unitCohort, bandCell, taskCell, onFocus,
}: {
  g: Grade
  students: Student[]
  collapsed: Set<string>
  uk: (g: Grade, u: Unit) => string
  toggleUnit: (key: string) => void
  mark: (s: string, t: string) => Mark
  unitAvg: (s: string, u: Unit) => { avg: number | null; ipp: boolean; incomplete: boolean }
  rollup: (s: string, g: Grade) => number | null
  taskPct: (students: Student[], t: string) => number | null
  unitCohort: (students: Student[], u: Unit) => number | null
  bandCell: (avg: number | null, ipp: boolean, incomplete: boolean) => React.ReactNode
  taskCell: (v: Mark) => React.ReactNode
  onFocus: (key: string) => void
}) {
  const overallCohort = (() => {
    const rs = students.map((s) => rollup(s.studentKey, g)).filter((v): v is number => v != null)
    return rs.length ? rs.reduce((a, b) => a + b, 0) / rs.length : null
  })()
  return (
    <div className="mscroll">
      <table className="mgrid">
        <thead>
          <tr>
            <th className="col-task">Task</th>
            <th className="col-pct">Class %</th>
            {students.map((s) => (
              <th className="stu" key={s.studentKey}>
                <button className="linkbtn" onClick={() => onFocus(s.studentKey)}>{s.name}</button>
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {/* overall roll-up row */}
          <tr className="unitrow">
            <th className="col-task"><span className="uname">Overall roll-up</span></th>
            <td className={`col-pct ${heatClass(overallCohort)}`}>{overallCohort == null ? '—' : Math.round(overallCohort * 100)}</td>
            {students.map((s) => {
              const r = rollup(s.studentKey, g)
              return <td className="stu" key={s.studentKey}>{bandCell(r, s.mathIPP && r == null, false)}</td>
            })}
          </tr>
          {g.units.map((u) => {
            const key = uk(g, u)
            const coll = collapsed.has(key)
            const cohort = unitCohort(students, u)
            return (
              <FragmentRows key={u.name}>
                <tr className="unitrow">
                  <th className="col-task" onClick={() => toggleUnit(key)} style={{ cursor: 'pointer' }}>
                    <span className="chev">{coll ? '▸' : '▾'}</span>
                    <span className="uname">{u.name} · {u.tasks.length} tasks</span>
                  </th>
                  <td className={`col-pct ${heatClass(cohort)}`}>{cohort == null ? '—' : Math.round(cohort * 100)}</td>
                  {students.map((s) => {
                    const a = unitAvg(s.studentKey, u)
                    return <td className="stu" key={s.studentKey}>{bandCell(a.avg, a.ipp, a.incomplete)}</td>
                  })}
                </tr>
                {!coll && u.tasks.map((t) => {
                  const p = taskPct(students, t.mathTaskKey)
                  const hc = heatClass(p)
                  return (
                    <tr className={hc} key={t.mathTaskKey}>
                      <th className="col-task" scope="row">
                        <span className="q">{t.questionNumber}</span> <span className="desc">{t.description}</span>
                        {t.outcomeCode && <span className="meta"><span className="code">{t.outcomeCode}</span></span>}
                      </th>
                      <td className={`col-pct ${hc}`}>{p == null ? '—' : Math.round(p * 100)}</td>
                      {students.map((s) => (
                        <td className="cell stu" key={s.studentKey}>{taskCell(mark(s.studentKey, t.mathTaskKey))}</td>
                      ))}
                    </tr>
                  )
                })}
              </FragmentRows>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

// ── students-down: students as rows, units (collapsed) / tasks (expanded) as columns ─────────────
function StudentsDown({
  g, students, collapsed, uk, toggleUnit, mark, unitAvg, rollup, bandCell, taskCell, onFocus,
}: {
  g: Grade
  students: Student[]
  collapsed: Set<string>
  uk: (g: Grade, u: Unit) => string
  toggleUnit: (key: string) => void
  mark: (s: string, t: string) => Mark
  unitAvg: (s: string, u: Unit) => { avg: number | null; ipp: boolean; incomplete: boolean }
  rollup: (s: string, g: Grade) => number | null
  bandCell: (avg: number | null, ipp: boolean, incomplete: boolean) => React.ReactNode
  taskCell: (v: Mark) => React.ReactNode
  onFocus: (key: string) => void
}) {
  // Build the column list: each unit contributes either one summary column (collapsed) or one column
  // per task (expanded). The unit header row spans its columns.
  return (
    <div className="mscroll">
      <table className="mgrid">
        <thead>
          <tr>
            <th className="col-task">Student</th>
            <th className="col-pct">Roll-up</th>
            {g.units.map((u) => {
              const coll = collapsed.has(uk(g, u))
              return (
                <th
                  key={u.name}
                  className="stu unitcol"
                  colSpan={coll ? 1 : u.tasks.length}
                  onClick={() => toggleUnit(uk(g, u))}
                  style={{ cursor: 'pointer' }}
                >
                  <span className="chev">{coll ? '▸' : '▾'}</span> {u.name}
                </th>
              )
            })}
          </tr>
          <tr>
            <th className="col-task" />
            <th className="col-pct" />
            {g.units.flatMap((u) => {
              const coll = collapsed.has(uk(g, u))
              return coll
                ? [<th className="stu" key={`${u.name}-sum`}>Unit</th>]
                : u.tasks.map((t) => <th className="stu" key={t.mathTaskKey} title={t.description}>{t.questionNumber}</th>)
            })}
          </tr>
        </thead>
        <tbody>
          {students.map((s) => {
            const r = rollup(s.studentKey, g)
            return (
              <tr key={s.studentKey}>
                <th className="col-task" scope="row">
                  <button className="linkbtn" onClick={() => onFocus(s.studentKey)}>{s.name}</button>
                </th>
                <td className="col-pct">{bandCell(r, s.mathIPP && r == null, false)}</td>
                {g.units.flatMap((u) => {
                  const coll = collapsed.has(uk(g, u))
                  if (coll) {
                    const a = unitAvg(s.studentKey, u)
                    return [<td className="stu" key={`${u.name}-sum`}>{bandCell(a.avg, a.ipp, a.incomplete)}</td>]
                  }
                  return u.tasks.map((t) => (
                    <td className="cell stu" key={t.mathTaskKey}>{taskCell(mark(s.studentKey, t.mathTaskKey))}</td>
                  ))
                })}
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

// ── one student's grid (the individual math page, reached by clicking a name) ─────────────────────
function StudentGrid({
  student, grade, rollup, unitAvg, mark, bandCell, taskCell, onBack,
}: {
  student: Student
  grade: Grade
  rollup: number | null
  unitAvg: (s: string, u: Unit) => { avg: number | null; ipp: boolean; incomplete: boolean }
  mark: (s: string, t: string) => Mark
  bandCell: (avg: number | null, ipp: boolean, incomplete: boolean) => React.ReactNode
  taskCell: (v: Mark) => React.ReactNode
  onBack: () => void
}) {
  return (
    <section className="mgrade">
      <div className="mtoolbar">
        <button className="btn-ghost" onClick={onBack}>&larr; Back to class</button>
        <span className="spacer" />
      </div>
      <div className="mghead">
        <h3>{student.fullName}</h3>
        <span className="gc">· {grade.label} · Roll-up: </span>
        {bandCell(rollup, student.mathIPP && rollup == null, false)}
      </div>
      <div className="mscroll">
        <table className="mgrid">
          <thead>
            <tr>
              <th className="col-task">Task</th>
              <th className="col-pct">Result</th>
            </tr>
          </thead>
          <tbody>
            {grade.units.map((u) => {
              const a = unitAvg(student.studentKey, u)
              return (
                <FragmentRows key={u.name}>
                  <tr className="unitrow">
                    <th className="col-task"><span className="uname">{u.name} · {u.tasks.length} tasks</span></th>
                    <td className="col-pct">{bandCell(a.avg, a.ipp, a.incomplete)}</td>
                  </tr>
                  {u.tasks.map((t) => (
                    <tr key={t.mathTaskKey}>
                      <th className="col-task" scope="row">
                        <span className="q">{t.questionNumber}</span> <span className="desc">{t.description}</span>
                        {t.outcomeCode && <span className="meta"><span className="code">{t.outcomeCode}</span></span>}
                      </th>
                      <td className="cell col-pct">{taskCell(mark(student.studentKey, t.mathTaskKey))}</td>
                    </tr>
                  ))}
                </FragmentRows>
              )
            })}
          </tbody>
        </table>
      </div>
    </section>
  )
}

function FragmentRows({ children }: { children: React.ReactNode }) {
  return <>{children}</>
}
