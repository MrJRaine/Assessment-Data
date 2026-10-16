'use client'

import { Fragment, useState, type ReactNode } from 'react'
import {
  type Counts, type RollupSchool, type RollupStudent, type SummarizeBy,
  tally, pctOf, childrenOf, gradeLabel, gradeRank,
} from './rollupModel'
import { heatClass, fmtPct } from './math/mathModel' // shared heat scale + % format (cross-subject consistency)

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
  schools, cycle, loadGroup, renderDetail, toolbarExtra, showAll = false,
}: {
  schools: RollupSchool[]
  cycle: string | null
  loadGroup: (groupKey: string, cycle: string | null) => Promise<{ rows: T[]; error: string | null }>
  renderDetail: (rows: T[]) => ReactNode
  toolbarExtra?: ReactNode // extra control in the toolbar (e.g. the writing COIL/IOLC toggle)
  showAll?: boolean // region-wide caller → show the TCRCE all-schools roll-up row (grade-only)
}) {
  const [summarizeBy, setSummarizeBy] = useState<SummarizeBy>('Grade')
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
        {toolbarExtra ? <><span className="spacer" />{toolbarExtra}</> : null}
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
            {showAll && schools.length > 1
              ? (() => {
                  const allStudents = schools.flatMap((s) => s.students)
                  const tOpen = openSchools.has(TCRCE_ID)
                  const tc = tally(allStudents)
                  return (
                    <Fragment key={TCRCE_ID}>
                      <tr className="tnode lvl1 tcrce">
                        <th className="col-task" onClick={() => toggleSchool(TCRCE_ID)}>
                          <span className="tchev">{tOpen ? '▾' : '▸'}</span>TCRCE<span className="tsub">all schools</span>
                        </th>
                        <StudentsCell c={tc} />
                        <ResultsCell c={tc} />
                        <MeetCell c={tc} />
                      </tr>
                      {tOpen
                        ? gradeGroups(allStudents).map((g) => {
                            const gc = tally(g.students)
                            return (
                              <tr className="tnode lvl2" key={`${TCRCE_ID}:${g.grade}`}>
                                <th className="col-task">
                                  <span className="tchev" style={{ visibility: 'hidden' }}>▸</span>{gradeLabel(g.grade)}
                                </th>
                                <StudentsCell c={gc} />
                                <ResultsCell c={gc} />
                                <MeetCell c={gc} />
                              </tr>
                            )
                          })
                        : null}
                    </Fragment>
                  )
                })()
              : null}
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
                    ? childrenOf(sch, summarizeBy).map((node) => {
                        const nOpen = openNodes.has(node.id)
                        const nc = tally(node.students)
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
                              <MeetCell c={nc} />
                            </tr>
                            {nOpen && node.groupKey ? (
                              <tr className="blockrow">
                                <td colSpan={4}>
                                  <div className="blockwrap">
                                    {!block || block.status === 'loading' ? (
                                      <p className="muted small" style={{ margin: 0 }}>Loading students…</p>
                                    ) : block.status === 'error' ? (
                                      <div className="notice notice-error">
                                        <div className="notice-title">Couldn&apos;t load this group</div>
                                        <div className="muted">{block.message}</div>
                                      </div>
                                    ) : (
                                      renderDetail(block.rows)
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
