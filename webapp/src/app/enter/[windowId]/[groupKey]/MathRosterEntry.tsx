'use client'

import { useMemo, useState, useTransition } from 'react'
import type { MathRosterRow } from '@/lib/data'
import { saveMathAssessments, type MathEntry } from './actions'

// Cell state: '1' can-do · '0' cannot · 'clear' explicit blank · 'ipp' the IPP default (no stored mark).
type Mark = '1' | '0' | 'clear' | 'ipp'

interface Task {
  mathTaskKey: string
  unitName: string
  unitOrder: number
  questionNumber: string
  displayOrder: number
  outcomeCode: string | null
  description: string
  answerKey: string | null
}
interface Unit { name: string; order: number; tasks: Task[] }
interface Student { studentKey: string; studentNumber: string; name: string; mathIPP: boolean }
interface Grade { grade: string; order: number; label: string; students: Student[]; units: Unit[] }

const GRADE_ORDER: Record<string, number> = { P: 0, PP: -1, '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6 }
const gradeLabel = (g: string) => (g === 'P' ? 'Primary' : g === 'PP' ? 'Pre-Primary' : `Grade ${g}`)
const rk = (studentKey: string, taskKey: string) => `${studentKey}:${taskKey}`

function buildGrades(rows: MathRosterRow[]): Grade[] {
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
        questionNumber: r.questionNumber,
        displayOrder: r.displayOrder ?? 0,
        outcomeCode: r.outcomeCode,
        description: r.description,
        answerKey: r.answerKey,
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

function initialMarks(rows: MathRosterRow[]): Record<string, Mark> {
  const m: Record<string, Mark> = {}
  for (const r of rows) {
    const key = rk(r.studentKey, r.mathTaskKey)
    if (r.existingResult === true) m[key] = '1'
    else if (r.existingResult === false) m[key] = '0'
    else m[key] = r.mathIPPStatus === true ? 'ipp' : 'clear'
  }
  return m
}

export default function MathRosterEntry({
  windowId,
  groupKey,
  rows,
}: {
  windowId: string
  groupKey: string
  rows: MathRosterRow[]
}) {
  const grades = useMemo(() => buildGrades(rows), [rows])
  const baseMarks = useMemo(() => initialMarks(rows), [rows])
  const studentNumberByKey = useMemo(() => {
    const m: Record<string, string> = {}
    for (const r of rows) m[r.studentKey] = r.studentNumber
    return m
  }, [rows])

  const [marks, setMarks] = useState<Record<string, Mark>>(baseMarks)
  const [committed, setCommitted] = useState<Record<string, Mark>>(baseMarks)
  const [shownGrades, setShownGrades] = useState<Set<string>>(() => new Set(grades.map((g) => g.grade)))
  const [shownStu, setShownStu] = useState<Set<string>>(
    () => new Set(grades.flatMap((g) => g.students.map((s) => s.studentKey))),
  )
  const [collapsedUnits, setCollapsedUnits] = useState<Set<string>>(new Set())
  const [collapsedGrades, setCollapsedGrades] = useState<Set<string>>(new Set())
  const [deselected, setDeselected] = useState<Set<string>>(new Set())
  const [editMode, setEditMode] = useState(false)
  const [pickerOpen, setPickerOpen] = useState(false)
  const [saving, startSave] = useTransition()
  const [result, setResult] = useState<{ saved: number; errors: { studentNumber: string; mathTaskKey: string; message: string }[] } | null>(null)

  const multi = grades.length > 1
  const activeTasks = (u: Unit) => u.tasks.filter((t) => !deselected.has(t.mathTaskKey))
  const shownStudents = (g: Grade) => g.students.filter((s) => shownStu.has(s.studentKey))

  const cellMark = (studentKey: string, taskKey: string): Mark => marks[rk(studentKey, taskKey)] ?? 'clear'

  function cycle(studentKey: string, taskKey: string, ipp: boolean) {
    const key = rk(studentKey, taskKey)
    setMarks((prev) => {
      const v = prev[key] ?? (ipp ? 'ipp' : 'clear')
      const next: Mark = ipp
        ? v === 'ipp' ? '1' : v === '1' ? '0' : v === '0' ? 'clear' : 'ipp'
        : v === 'clear' ? '1' : v === '1' ? '0' : 'clear'
      return { ...prev, [key]: next }
    })
  }

  // --- summaries (IPP + clear excluded) ---
  function taskPct(g: Grade, taskKey: string): number | null {
    let scored = 0, ones = 0
    for (const s of shownStudents(g)) {
      const v = cellMark(s.studentKey, taskKey)
      if (v === '1' || v === '0') { scored++; if (v === '1') ones++ }
    }
    return scored === 0 ? null : ones / scored
  }
  function heatClass(p: number | null) {
    return p == null ? 'none' : p > 0.8 ? 'h4' : p >= 0.65 ? 'h3' : p >= 0.5 ? 'h2' : 'h1'
  }
  function unitBand(s: Student, u: Unit): { cls: string; label: string; partial: boolean } {
    const tasks = activeTasks(u)
    let inScope = 0, filled = 0, ones = 0, ippCount = 0
    for (const t of tasks) {
      const v = cellMark(s.studentKey, t.mathTaskKey)
      if (v === 'ipp') { ippCount++; continue } // IPP excluded from tally AND the 80% denominator
      inScope++
      if (v === '1' || v === '0') { filled++; if (v === '1') ones++ }
    }
    // All IPP -> plain IPP flag; no in-scope task scored -> —; too few scored -> Incomplete.
    if (inScope === 0) return { cls: 'bipp', label: 'IPP', partial: false }
    if (filled === 0) return { cls: 'inc', label: '—', partial: false }
    if (filled / inScope < 0.8) return { cls: 'inc', label: 'Incomplete', partial: false }
    // A calculated level that omitted some tasks as IPP -> flag it partial (purple ring).
    const partial = ippCount > 0
    const avg = ones / filled
    if (avg < 0.5) return { cls: 'b1', label: 'Emerging', partial } // <50%
    if (avg < 0.75) return { cls: 'b2', label: 'Developing', partial } // 50 to <75%
    if (avg < 0.9) return { cls: 'b3', label: 'Meeting', partial } // 75 to <90%
    return { cls: 'b4', label: 'In-depth', partial } // >=90%
  }

  // --- dirty + save ---
  const dirtyKeys = Object.keys(marks).filter((k) => marks[k] !== committed[k])
  const totalTasks = grades.reduce((a, g) => a + g.units.reduce((b, u) => b + u.tasks.length, 0), 0)
  const selTasks = totalTasks - deselected.size

  function save() {
    const entries: MathEntry[] = dirtyKeys.map((k) => {
      const [studentKey, mathTaskKey] = k.split(':')
      const v = marks[k]
      return {
        studentNumber: studentNumberByKey[studentKey],
        mathTaskKey,
        result: v === '1' ? '1' : v === '0' ? '0' : null, // 'clear'/'ipp' -> null
      }
    })
    startSave(async () => {
      const res = await saveMathAssessments(windowId, groupKey, entries)
      setResult(res)
      // Clear dirty for cells that saved (everything not in the error list), matched by student+task.
      const failed = new Set(res.errors.map((e) => `${e.studentNumber}:${e.mathTaskKey}`))
      setCommitted((prev) => {
        const nextC = { ...prev }
        for (const k of dirtyKeys) {
          const [studentKey, taskKey] = k.split(':')
          if (!failed.has(`${studentNumberByKey[studentKey]}:${taskKey}`)) nextC[k] = marks[k]
        }
        return nextC
      })
    })
  }

  const toggleIn = (set: Set<string>, val: string) => {
    const next = new Set(set)
    next.has(val) ? next.delete(val) : next.add(val)
    return next
  }
  function setUnitSel(u: Unit, select: boolean) {
    setDeselected((prev) => {
      const next = new Set(prev)
      for (const t of u.tasks) select ? next.delete(t.mathTaskKey) : next.add(t.mathTaskKey)
      return next
    })
  }
  function setGradeSel(g: Grade, select: boolean) {
    setDeselected((prev) => {
      const next = new Set(prev)
      for (const u of g.units) for (const t of u.tasks) select ? next.delete(t.mathTaskKey) : next.add(t.mathTaskKey)
      return next
    })
  }

  const singleGrade = grades.length === 1
  const pageControls = (
    <>
      <span className="muted">
        {editMode ? (
          <><strong>Editing checklist</strong> — untick tasks to hide them (resets next session)</>
        ) : selTasks < totalTasks ? (
          <>showing <strong>{selTasks}</strong> of {totalTasks} tasks · <button className="linkbtn" onClick={() => setDeselected(new Set())}>Show all tasks</button></>
        ) : (
          <>all <strong>{totalTasks}</strong> tasks shown</>
        )}
      </span>
      <span className="spacer" />
      <button className={`btn-ghost${editMode ? ' editing' : ''}`} onClick={() => setEditMode((e) => !e)}>
        {editMode ? 'Done editing' : 'Edit checklist'}
      </button>
      <button className="btn" disabled={saving || dirtyKeys.length === 0} onClick={save}>
        {saving ? 'Saving…' : dirtyKeys.length > 0 ? `Save ${dirtyKeys.length} change${dirtyKeys.length === 1 ? '' : 's'}` : 'Save'}
      </button>
    </>
  )

  return (
    <div className="math-entry">
      {/* grade filter */}
      {multi && (
        <>
          <p className="filter-label">Grades in this homeroom</p>
          <div className="grade-chips">
            {grades.map((g) => (
              <button
                key={g.grade}
                className={`grade-chip${shownGrades.has(g.grade) ? ' on' : ''}`}
                onClick={() => setShownGrades((s) => toggleIn(s, g.grade))}
              >
                {g.label} <span className="c">· {g.students.length}</span>
              </button>
            ))}
          </div>
        </>
      )}

      {/* student filter */}
      <div className="mfilter">
        <button className="mfilter-summary" onClick={() => setPickerOpen((o) => !o)}>
          <span className="chev">{pickerOpen ? '▾' : '▸'}</span> Students{' '}
          <span className="muted">
            ({[...shownStu].length} of {grades.reduce((a, g) => a + g.students.length, 0)} shown)
          </span>
        </button>
        {pickerOpen && (
          <div className="mfilter-body">
            <div className="mfilter-actions">
              <button className="btn-ghost" onClick={() => setShownStu(new Set(grades.flatMap((g) => shownGrades.has(g.grade) ? g.students.map((s) => s.studentKey) : [])))}>Select all</button>
              <button className="btn-ghost" onClick={() => setShownStu(new Set())}>Clear all</button>
              <span className="muted small">Show just the small group you pulled to assess.</span>
            </div>
            {grades.filter((g) => shownGrades.has(g.grade)).map((g) => (
              <div key={g.grade}>
                <div className="pick-grade">{g.label}</div>
                <div className="chips">
                  {g.students.map((s) => (
                    <label key={s.studentKey} className="schip">
                      <input
                        type="checkbox"
                        checked={shownStu.has(s.studentKey)}
                        onChange={() => setShownStu((set) => toggleIn(set, s.studentKey))}
                      />
                      {s.name}
                    </label>
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* page controls: their own toolbar only when there are multiple grades;
          for a single-grade homeroom they sit on the grade heading line below. */}
      {!singleGrade && <div className="mtoolbar">{pageControls}</div>}

      {saving && (
        <div className="loading"><span className="spinner" /> Saving changes…</div>
      )}
      {result && !saving && (
        <p className="save-result">
          Saved {result.saved}
          {result.errors.length > 0 && <span className="err"> · {result.errors.length} failed</span>}
        </p>
      )}
      {result && result.errors.length > 0 && !saving && (
        <ul className="save-errors">
          {result.errors.map((e, i) => (
            <li key={i}>{e.message}</li>
          ))}
        </ul>
      )}

      {/* legend */}
      {!editMode && (
        <div className="mlegend">
          <span className="grp"><strong>Achievement Level</strong></span>
          <span className="grp"><span className="mband b1">Emerging</span>&lt;50%</span>
          <span className="grp"><span className="mband b2">Developing</span>50–&lt;75%</span>
          <span className="grp"><span className="mband b3">Meeting</span>75–&lt;90%</span>
          <span className="grp"><span className="mband b4">In-depth</span>≥90%</span>
          <span className="grp"><span className="partial-swatch" /> Some tasks omitted</span>
          <span className="grp"><strong>Class %</strong>
            <span className="sw h1" /> &lt;50 <span className="sw h2" /> 50–64 <span className="sw h3" /> 65–80 <span className="sw h4" /> &gt;80
          </span>
        </div>
      )}

      {/* grade sections */}
      {grades.filter((g) => shownGrades.has(g.grade)).map((g) => {
        const cols = shownStudents(g)
        const gColl = collapsedGrades.has(g.grade)
        return (
          <section className="mgrade" key={g.grade}>
            <div
              className={`mghead${multi ? ' clickable' : ''}`}
              onClick={multi ? () => setCollapsedGrades((s) => toggleIn(s, g.grade)) : undefined}
            >
              {multi && <span className="gchev">{gColl ? '▸' : '▾'}</span>}
              <h3>{g.label}</h3>
              <span className="gc">· {cols.length} of {g.students.length} students shown{editMode ? ' · choose tasks' : ''}</span>
              {singleGrade && <div className="mghead-controls">{pageControls}</div>}
            </div>

            {gColl ? null : editMode ? (
              <div className="checklist">
                <div className="cl-gradebar">
                  <span><strong>{g.units.reduce((a, u) => a + u.tasks.filter((t) => !deselected.has(t.mathTaskKey)).length, 0)}</strong> / {g.units.reduce((a, u) => a + u.tasks.length, 0)} tasks selected</span>
                  <span className="right">
                    <button className="linkbtn" onClick={() => setGradeSel(g, true)}>Select all</button> ·{' '}
                    <button className="linkbtn" onClick={() => setGradeSel(g, false)}>Clear all</button>
                  </span>
                </div>
                {g.units.map((u) => (
                  <div key={u.name}>
                    <div className="cl-unit">
                      <span>{u.name}<span className="cl-count">{u.tasks.filter((t) => !deselected.has(t.mathTaskKey)).length}/{u.tasks.length}</span></span>
                      <span className="cl-ctl">
                        <button className="linkbtn" onClick={() => setUnitSel(u, true)}>Select all</button> ·{' '}
                        <button className="linkbtn" onClick={() => setUnitSel(u, false)}>Clear all</button>
                      </span>
                    </div>
                    {u.tasks.map((t) => {
                      const off = deselected.has(t.mathTaskKey)
                      return (
                        <label className={`cl-task${off ? ' off' : ''}`} key={t.mathTaskKey}>
                          <input type="checkbox" checked={!off} onChange={() => setDeselected((s) => toggleIn(s, t.mathTaskKey))} />
                          <span className="q">{t.questionNumber}</span>
                          <span className="desc">{t.description}</span>
                          {t.answerKey && <span className="cl-ans">{t.answerKey}</span>}
                        </label>
                      )
                    })}
                  </div>
                ))}
              </div>
            ) : (
              <div className="mscroll">
                <table className="mgrid">
                  <thead>
                    <tr>
                      <th className="col-task">Task</th>
                      <th className="col-pct">Class %</th>
                      {cols.map((s) => (
                        <th className="stu" key={s.studentKey}>{s.name}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {g.units.map((u) => {
                      const uColl = collapsedUnits.has(`${g.grade}:${u.name}`)
                      const tasks = activeTasks(u)
                      return (
                        <FragmentUnit key={u.name}>
                          <tr className="unitrow">
                            <th className="col-task" onClick={() => setCollapsedUnits((s) => toggleIn(s, `${g.grade}:${u.name}`))}>
                              <span className="chev">{uColl ? '▸' : '▾'}</span>
                              <span className="uname">{u.name} · {tasks.length} tasks</span>
                            </th>
                            <td className="col-pct" />
                            {cols.map((s) => {
                              const b = unitBand(s, u)
                              return <td className="stu" key={s.studentKey}><span className={`mband ${b.cls}${b.partial ? ' partial-ipp' : ''}`}>{b.label}</span></td>
                            })}
                          </tr>
                          {!uColl && tasks.map((t) => {
                            const p = taskPct(g, t.mathTaskKey)
                            const hc = heatClass(p)
                            return (
                              <tr className={hc} key={t.mathTaskKey}>
                                <th className="col-task" scope="row">
                                  <span className="q">{t.questionNumber}</span> <span className="desc">{t.description}</span>
                                  <span className="meta">
                                    {t.answerKey && <span className="ans">{t.answerKey}</span>}
                                    {t.outcomeCode && <span className="code">{t.outcomeCode}</span>}
                                  </span>
                                </th>
                                <td className={`col-pct ${hc}`}>{p == null ? '—' : Math.round(p * 100)}</td>
                                {cols.map((s) => {
                                  const v = cellMark(s.studentKey, t.mathTaskKey)
                                  const cls = v === '1' ? 'yes' : v === '0' ? 'no' : v === 'ipp' ? 'ipp' : 'blank'
                                  const glyph = v === '1' ? '✓' : v === '0' ? '✗' : v === 'ipp' ? 'IPP' : ''
                                  return (
                                    <td className="cell stu" key={s.studentKey}>
                                      <button
                                        className={`mtoggle ${cls}`}
                                        onClick={() => cycle(s.studentKey, t.mathTaskKey, s.mathIPP)}
                                        aria-label={`${t.questionNumber} ${s.name}`}
                                      >
                                        {glyph}
                                      </button>
                                    </td>
                                  )
                                })}
                              </tr>
                            )
                          })}
                        </FragmentUnit>
                      )
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </section>
        )
      })}
    </div>
  )
}

// tbody can't take a <> fragment key cleanly across rows in some setups; a keyed wrapper keeps it valid.
function FragmentUnit({ children }: { children: React.ReactNode }) {
  return <>{children}</>
}
