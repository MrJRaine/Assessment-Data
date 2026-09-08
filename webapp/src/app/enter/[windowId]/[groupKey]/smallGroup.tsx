'use client'

import { useMemo, useState } from 'react'

// Small-group filtering for the data-entry grids — a grade-chip filter (when the homeroom
// spans grades) plus a collapsible student picker, so a teacher can show just the small
// group they pulled to assess. Mirrors the Math roster's filter; shared by the Reading and
// Writing grids so all three entry screens behave identically.

export interface FilterStudent {
  studentKey: string
  grade: string | null
  firstName: string
  lastName: string
}

interface GradeGroup {
  grade: string
  order: number
  label: string
  students: { studentKey: string; name: string }[]
}

const GRADE_ORDER: Record<string, number> = {
  PP: -1, P: 0, '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6,
  '7': 7, '8': 8, '9': 9, '10': 10, '11': 11, '12': 12, RG: 13,
}
const gradeLabel = (g: string) =>
  g === 'P' ? 'Primary' : g === 'PP' ? 'Pre-Primary' : /^\d+$/.test(g) ? `Grade ${g}` : g

const toggleIn = (set: Set<string>, val: string) => {
  const next = new Set(set)
  if (next.has(val)) next.delete(val)
  else next.add(val)
  return next
}

export function useSmallGroup(roster: FilterStudent[]) {
  const gradeGroups = useMemo<GradeGroup[]>(() => {
    const byGrade = new Map<string, GradeGroup>()
    for (const s of roster) {
      const g = s.grade ?? '?'
      let grp = byGrade.get(g)
      if (!grp) {
        grp = { grade: g, order: GRADE_ORDER[g] ?? 99, label: gradeLabel(g), students: [] }
        byGrade.set(g, grp)
      }
      grp.students.push({ studentKey: s.studentKey, name: `${s.lastName}, ${s.firstName}` })
    }
    const groups = [...byGrade.values()].sort((a, b) => a.order - b.order)
    for (const grp of groups) grp.students.sort((a, b) => a.name.localeCompare(b.name))
    return groups
  }, [roster])

  // Filtering is display-only: hidden students keep any staged edits and still save.
  const [shownGrades, setShownGrades] = useState<Set<string>>(() => new Set(gradeGroups.map((g) => g.grade)))
  const [shownStu, setShownStu] = useState<Set<string>>(() => new Set(roster.map((s) => s.studentKey)))
  const [pickerOpen, setPickerOpen] = useState(false)

  const multi = gradeGroups.length > 1
  const totalStudents = roster.length

  const isShown = (s: FilterStudent) => shownGrades.has(s.grade ?? '?') && shownStu.has(s.studentKey)
  const toggleGrade = (g: string) => setShownGrades((s) => toggleIn(s, g))
  const toggleStudent = (k: string) => setShownStu((s) => toggleIn(s, k))
  const selectAll = () =>
    setShownStu(new Set(roster.filter((s) => shownGrades.has(s.grade ?? '?')).map((s) => s.studentKey)))
  const clearAll = () => setShownStu(new Set())

  return {
    gradeGroups, multi, totalStudents,
    shownGrades, shownStu, pickerOpen, setPickerOpen,
    isShown, toggleGrade, toggleStudent, selectAll, clearAll,
  }
}

export type SmallGroup = ReturnType<typeof useSmallGroup>

export function SmallGroupFilter({ sg }: { sg: SmallGroup }) {
  const {
    gradeGroups, multi, totalStudents, shownGrades, shownStu, pickerOpen, setPickerOpen,
    toggleGrade, toggleStudent, selectAll, clearAll,
  } = sg
  return (
    <>
      {multi && (
        <>
          <p className="filter-label">Grades in this homeroom</p>
          <div className="grade-chips">
            {gradeGroups.map((g) => (
              <button
                key={g.grade}
                className={`grade-chip${shownGrades.has(g.grade) ? ' on' : ''}`}
                onClick={() => toggleGrade(g.grade)}
              >
                {g.label} <span className="c">· {g.students.length}</span>
              </button>
            ))}
          </div>
        </>
      )}

      <div className="mfilter">
        <button className="mfilter-summary" onClick={() => setPickerOpen(!pickerOpen)}>
          <span className="chev">{pickerOpen ? '▾' : '▸'}</span> Students{' '}
          <span className="muted">({[...shownStu].length} of {totalStudents} shown)</span>
        </button>
        {pickerOpen && (
          <div className="mfilter-body">
            <div className="mfilter-actions">
              <button className="btn-ghost" onClick={selectAll}>Select all</button>
              <button className="btn-ghost" onClick={clearAll}>Clear all</button>
              <span className="muted small">Show just the small group you pulled to assess.</span>
            </div>
            {gradeGroups.filter((g) => shownGrades.has(g.grade)).map((g) => (
              <div key={g.grade}>
                {multi && <div className="pick-grade">{g.label}</div>}
                <div className="chips">
                  {g.students.map((s) => (
                    <label key={s.studentKey} className="schip">
                      <input
                        type="checkbox"
                        checked={shownStu.has(s.studentKey)}
                        onChange={() => toggleStudent(s.studentKey)}
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
    </>
  )
}
