'use client'

import { Fragment, useMemo, useState } from 'react'
import type { ReadingRollupRow, ReadingGroupRow } from '@/lib/data'
import { heatClass, fmtPct } from './math/mathModel' // shared heat scale + % format (cross-subject consistency)
import { loadReadingGroup } from './actions'

// ── Reports > Reading OVERSIGHT roll-up tree (1.3.0 reports rebuild). Mirrors the Math tree:
//
//   School → [Summarize by: Grade | Homeroom] → grade/homeroom rows → (expand) individual students
//
// Each roll-up row shows distinct STUDENTS, total RESULTS, and % Meeting/Exceeding — each with an EN/FR
// breakdown in the hover. A student assessed in both languages counts ONCE in Students and TWICE in
// Results. % is over results that carry an achievement band (code >= 3 = Meeting/Exceeding); IPP /
// no-result are excluded from the % and shown in the hover. Expanding a Grade/Homeroom row lazy-loads
// that group's students (their EN/FR reading level + band). Oversight only; teachers keep the flat list.

type SummarizeBy = 'Grade' | 'Homeroom'
const MEETING_MIN = 3 // DimAchievementLevel code at/above = Meeting/Exceeding (matches writing's b3+b4)

// Local P–12 grade order (Math's GRADE_ORDER stops at 6; reading spans P–8).
const GRADE_ORDER: Record<string, number> = {
  PP: -1, P: 0, '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9, '10': 10, '11': 11, '12': 12,
}
const gradeLabel = (g: string) => (g === 'P' ? 'Primary' : g === 'PP' ? 'Pre-Primary' : `Grade ${g}`)
const gradeRank = (g: string) => GRADE_ORDER[g] ?? 99

interface Res { lang: 'EN_Reading' | 'FR_Reading'; code: number | null }
interface TreeStudent {
  key: string
  grade: string
  homeroom: string | null
  homeroomKey: string | null
  schoolId: string
  results: Res[]
}
interface School { id: string; name: string; students: TreeStudent[] }
interface ChildNode {
  id: string
  label: string
  sub: string | null
  groupKey: string | null // reading-group key; null = can't open (no homeroom)
  grades: string[]
  students: TreeStudent[]
}
type BlockState = { status: 'loading' } | { status: 'done'; rows: ReadingGroupRow[] } | { status: 'error'; message: string }

interface Counts {
  students: number
  studentsEN: number
  studentsFR: number
  studentsNone: number
  results: number
  resultsEN: number
  resultsFR: number
  meet: number
  band: number
  meetEN: number
  bandEN: number
  meetFR: number
  bandFR: number
}

function tally(students: TreeStudent[]): Counts {
  const c: Counts = {
    students: 0, studentsEN: 0, studentsFR: 0, studentsNone: 0,
    results: 0, resultsEN: 0, resultsFR: 0,
    meet: 0, band: 0, meetEN: 0, bandEN: 0, meetFR: 0, bandFR: 0,
  }
  for (const s of students) {
    c.students++
    let hasEN = false
    let hasFR = false
    for (const r of s.results) {
      c.results++
      const en = r.lang === 'EN_Reading'
      if (en) { c.resultsEN++; hasEN = true } else { c.resultsFR++; hasFR = true }
      if (r.code != null) {
        c.band++
        if (en) c.bandEN++
        else c.bandFR++
        if (r.code >= MEETING_MIN) {
          c.meet++
          if (en) c.meetEN++
          else c.meetFR++
        }
      }
    }
    if (hasEN) c.studentsEN++
    if (hasFR) c.studentsFR++
    if (!hasEN && !hasFR) c.studentsNone++
  }
  return c
}

const pctOf = (meet: number, band: number): number | null => (band === 0 ? null : meet / band)

function StudentsCell({ c }: { c: Counts }) {
  const title = `EN ${c.studentsEN} · FR ${c.studentsFR} · no result ${c.studentsNone}\n(a student assessed in both languages is counted once here)`
  return <td className="rn" title={title}>{c.students}</td>
}
function ResultsCell({ c }: { c: Counts }) {
  return <td className="rn" title={`EN ${c.resultsEN} · FR ${c.resultsFR}`}>{c.results}</td>
}
function MeetCell({ c }: { c: Counts }) {
  const p = pctOf(c.meet, c.band)
  if (p == null) return <td className="rpct none" title="No results with a level here">—</td>
  const title = `Meeting/Exceeding ${c.meet} of ${c.band} results with a level\nEN ${c.meetEN}/${c.bandEN} · FR ${c.meetFR}/${c.bandFR}`
  return <td className={`rpct ${heatClass(p)}`} title={title}>{fmtPct(p)}</td>
}

export default function ReadingRollupTree({ rows, cycle }: { rows: ReadingRollupRow[]; cycle: string | null }) {
  const schools = useMemo(() => {
    const byKey = new Map<string, TreeStudent>()
    const schoolNames = new Map<string, string>()
    for (const r of rows) {
      if (!r.schoolId) continue
      let s = byKey.get(r.studentKey)
      if (!s) {
        s = {
          key: r.studentKey, grade: r.grade ?? '', homeroom: r.homeroom, homeroomKey: r.homeroomKey,
          schoolId: r.schoolId, results: [],
        }
        byKey.set(r.studentKey, s)
        schoolNames.set(r.schoolId, r.schoolName ?? r.schoolId)
      }
      if (r.scaleSystem === 'EN_Reading' || r.scaleSystem === 'FR_Reading') {
        s.results.push({ lang: r.scaleSystem, code: r.achievementCode })
      }
    }
    const bySchool = new Map<string, School>()
    for (const s of byKey.values()) {
      let sch = bySchool.get(s.schoolId)
      if (!sch) {
        sch = { id: s.schoolId, name: schoolNames.get(s.schoolId) ?? s.schoolId, students: [] }
        bySchool.set(s.schoolId, sch)
      }
      sch.students.push(s)
    }
    return [...bySchool.values()].sort((a, b) => a.name.localeCompare(b.name))
  }, [rows])

  const [summarizeBy, setSummarizeBy] = useState<SummarizeBy>('Grade')
  // A caller who sees exactly one school lands with it open; multi-school starts collapsed.
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
      const grades = [...new Set(students.map((s) => s.grade))].sort((a, b) => gradeRank(a) - gradeRank(b))
      if (summarizeBy === 'Grade') {
        return { id: `G:${sch.id}:${k}`, label: gradeLabel(k), sub: null, groupKey: `GRADE:${sch.id}:${k}`, grades, students }
      }
      const hr = students[0].homeroom
      return {
        id: `H:${sch.id}:${k}`,
        label: k && hr ? `Homeroom ${hr}` : 'No homeroom',
        sub: grades.map(gradeLabel).join(', '),
        groupKey: k || null, // homeroom GroupKey; null = no homeroom (can't open)
        grades,
        students,
      }
    })
    return nodes.sort(
      (a, b) => gradeRank(a.grades[0]) - gradeRank(b.grades[0]) || a.label.localeCompare(b.label, undefined, { numeric: true }),
    )
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
      loadReadingGroup(gk, cycle)
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

  const noHomeroomCount = schools.reduce((n, sch) => n + sch.students.filter((s) => !s.homeroomKey).length, 0)

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
        <span className="muted">Summarize by</span>
        <div className="subject-toggle" style={{ margin: 0 }}>
          {(['Grade', 'Homeroom'] as SummarizeBy[]).map((m) => (
            <button key={m} className={summarizeBy === m ? 'toggle-on' : ''} onClick={() => setSummarizeBy(m)}>
              {m}
            </button>
          ))}
        </div>
      </div>

      <div className="mlegend">
        <span className="grp"><strong>% Meeting or Exceeding</strong></span>
        <span className="grp">
          <span className="sw h1" /> &lt;50 <span className="sw h2" /> 50–64 <span className="sw h3" /> 65–80 <span className="sw h4" /> &gt;80
        </span>
        <span className="grp">Out of results with a level. IPP / No data excluded — hover any figure for the EN/FR breakdown.</span>
      </div>
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
              <th className="rpct-h">% Meeting/Exceeding</th>
            </tr>
          </thead>
          <tbody>
            {schools.map((sch) => {
              const open = openSchools.has(sch.id)
              const c = tally(sch.students)
              return (
                <Fragment key={sch.id}>
                  <tr className="tnode lvl1">
                    <th className="col-task" onClick={() => toggleSchool(sch.id)}>
                      <span className="tchev">{open ? '▾' : '▸'}</span>{sch.name}
                    </th>
                    <StudentsCell c={c} />
                    <ResultsCell c={c} />
                    <MeetCell c={c} />
                  </tr>
                  {open
                    ? childrenOf(sch).map((node) => {
                        const nOpen = openNodes.has(node.id)
                        const nc = tally(node.students)
                        return (
                          <Fragment key={node.id}>
                            <tr className="tnode lvl2">
                              <th className={`col-task${node.groupKey ? '' : ' nochev'}`} onClick={() => node.groupKey && toggleNode(node)}>
                                <span className="tchev">{node.groupKey ? (nOpen ? '▾' : '▸') : ''}</span>{node.label}
                                {node.sub ? <span className="tsub">{node.sub}</span> : null}
                              </th>
                              <StudentsCell c={nc} />
                              <ResultsCell c={nc} />
                              <MeetCell c={nc} />
                            </tr>
                            {nOpen && node.groupKey ? (
                              <tr className="blockrow">
                                <td colSpan={4}>
                                  <div className="blockwrap">
                                    <ReadingGroupBlock state={blocks[node.groupKey]} />
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

// ── One expanded Grade/Homeroom: the students in the group with their EN/FR reading level + band ───
interface DetailCell { levelCode: string | null; name: string | null; color: string | null; delta: number | null }
interface DetailStudent { key: string; name: string; grade: string | null; ipp: boolean; en: DetailCell | null; fr: DetailCell | null }

function pivotStudents(rows: ReadingGroupRow[]): DetailStudent[] {
  const byKey = new Map<string, DetailStudent>()
  for (const r of rows) {
    let s = byKey.get(r.studentKey)
    if (!s) {
      s = { key: r.studentKey, name: `${r.lastName}, ${r.firstName}`, grade: r.grade, ipp: r.readingIPP === true, en: null, fr: null }
      byKey.set(r.studentKey, s)
    }
    if (r.scaleSystem === 'EN_Reading' || r.scaleSystem === 'FR_Reading') {
      const cell: DetailCell = { levelCode: r.levelCode, name: r.achievementName, color: r.achievementHexColor, delta: r.readingDelta }
      if (r.scaleSystem === 'EN_Reading') s.en = cell
      else s.fr = cell
    }
  }
  return [...byKey.values()].sort((a, b) => a.name.localeCompare(b.name))
}

function LevelCell({ cell, ipp }: { cell: DetailCell | null; ipp: boolean }) {
  if (!cell || cell.levelCode == null) {
    return <td className="stu">{ipp ? <span className="muted" title="IPP — not measured against the benchmark">IPP</span> : <span className="muted">—</span>}</td>
  }
  const title = [cell.name, cell.delta == null ? null : `Δ ${cell.delta > 0 ? `+${cell.delta}` : cell.delta}`].filter(Boolean).join(' · ')
  return (
    <td className="stu" title={title || undefined}>
      <span style={cell.color ? { color: cell.color, fontWeight: 600 } : undefined}>{cell.levelCode}</span>
    </td>
  )
}

function ReadingGroupBlock({ state }: { state: BlockState | undefined }) {
  if (!state || state.status === 'loading') return <p className="muted small" style={{ margin: 0 }}>Loading students…</p>
  if (state.status === 'error') {
    return (
      <div className="notice notice-error">
        <div className="notice-title">Couldn&apos;t load this group</div>
        <div className="muted">{state.message}</div>
      </div>
    )
  }
  const students = pivotStudents(state.rows)
  if (students.length === 0) return <p className="muted small" style={{ margin: 0 }}>No students in this group.</p>
  return (
    <div className="mscroll">
      <table className="mgrid">
        <thead>
          <tr>
            <th className="col-task">Student</th>
            <th className="stu">Grade</th>
            <th className="stu">English</th>
            <th className="stu">French</th>
          </tr>
        </thead>
        <tbody>
          {students.map((s) => (
            <tr key={s.key}>
              <th className="col-task" scope="row">{s.name}</th>
              <td className="stu">{s.grade ?? '—'}</td>
              <LevelCell cell={s.en} ipp={s.ipp} />
              <LevelCell cell={s.fr} ipp={s.ipp} />
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
