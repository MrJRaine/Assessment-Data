'use client'

import { Fragment, useMemo, useState } from 'react'
import type { MissingDataRow, MissingGroupRow, MissingSubject } from '@/lib/data'
import { gradeSpanLabel } from '../rollupModel'
import { fmtPct } from '../math/mathModel' // shared 2-dp % format (cross-report consistency)
import { loadMissingGroup } from '../actions'

// Missing-results roll-up (user ask 2026-11-10, built 2026-11-12): Administrator/RegionalAnalyst
// only. TCRCE → School → Lead teacher → Section; opening a section lists the students who still
// need data entered for the selected cycle. Counts = students missing a result per subject
// (deduped by student at every roll-up level — one entered result clears every section the
// student sits in); % column + row colour = % REPORTED (user call 2026-11-13 — positive frame):
// <50% red · 50–<75% yellow · 75–<100% light green · 100% dark green (user buckets — deliberately
// NOT the usual 50/65/80 heat scale).

const SUBJECTS: MissingSubject[] = ['Reading', 'Writing', 'Math']
const NO_LEAD = '__none__'

interface Tally {
  m: Record<MissingSubject, number>
  e: Record<MissingSubject, number>
  mTot: number
  eTot: number
}

// Distinct (student × subject) data points over a set of feed rows: a student expected in two
// mapped sections counts once, since one entered result clears both.
function tally(rows: MissingDataRow[]): Tally {
  const seen = new Set<string>()
  const t: Tally = {
    m: { Reading: 0, Writing: 0, Math: 0 },
    e: { Reading: 0, Writing: 0, Math: 0 },
    mTot: 0,
    eTot: 0,
  }
  for (const r of rows) {
    const k = `${r.subject}:${r.studentNumber}`
    if (seen.has(k)) continue
    seen.add(k)
    t.e[r.subject]++
    t.eTot++
    if (r.missing) {
      t.m[r.subject]++
      t.mTot++
    }
  }
  return t
}

// User buckets on % REPORTED (not the standard heat scale): 100% = dark green, 75–<100 light
// green, 50–<75 yellow, <50 red. Reuses the h1–h4 tint family so the colours stay standard.
function reportedBucket(t: Tally): string {
  if (t.eTot === 0) return 'none'
  const rep = 1 - t.mTot / t.eTot
  return rep >= 1 ? 'h4' : rep >= 0.75 ? 'h3' : rep >= 0.5 ? 'h2' : 'h1'
}

function CountCells({ t }: { t: Tally }) {
  const bucket = reportedBucket(t)
  const rep = t.eTot === 0 ? null : 1 - t.mTot / t.eTot
  return (
    <>
      {SUBJECTS.map((s) => (
        <td className="rn" key={s}>
          {t.e[s] === 0 ? <span className="muted">—</span> : t.m[s] === 0 ? <span className="muted">0</span> : t.m[s]}
        </td>
      ))}
      <td className="rn" style={{ fontWeight: 700, color: 'var(--ink)' }}>{t.mTot}</td>
      <td
        className={`rpct ${bucket}`}
        title={`${t.mTot} of ${t.eTot} expected data points missing${rep == null ? '' : ` · ${fmtPct(rep)} reported`}`}
      >
        {fmtPct(rep)}
      </td>
    </>
  )
}

interface SectionNode { id: string; label: string; grades: string[]; rows: MissingDataRow[] }
interface TeacherNode { key: string; label: string; noLead: boolean; sections: SectionNode[]; rows: MissingDataRow[] }
interface SchoolNode { id: string; name: string; teachers: TeacherNode[]; rows: MissingDataRow[] }

type BlockState =
  | { status: 'loading' }
  | { status: 'done'; rows: MissingGroupRow[] }
  | { status: 'error'; message: string }

// One opened section's still-missing students (lazy-loaded — the feed is name-free on purpose).
function SectionDetail({ rows }: { rows: MissingGroupRow[] }) {
  const students = useMemo(() => {
    const m = new Map<string, { firstName: string; lastName: string; grade: string | null; homeroom: string | null; subjects: MissingSubject[] }>()
    for (const r of rows) {
      let s = m.get(r.studentNumber)
      if (!s) {
        s = { firstName: r.firstName, lastName: r.lastName, grade: r.grade, homeroom: r.homeroom, subjects: [] }
        m.set(r.studentNumber, s)
      }
      if (!s.subjects.includes(r.subject)) s.subjects.push(r.subject)
    }
    for (const s of m.values()) s.subjects.sort((a, b) => SUBJECTS.indexOf(a) - SUBJECTS.indexOf(b))
    return [...m.values()].sort(
      (a, b) => a.lastName.localeCompare(b.lastName) || a.firstName.localeCompare(b.firstName),
    )
  }, [rows])

  if (students.length === 0) {
    return <p className="muted small" style={{ margin: 0 }}>Everyone on this section&apos;s roster has results for this cycle.</p>
  }
  return (
    <div className="mscroll">
      <table className="mgrid">
        <thead>
          <tr>
            <th className="col-task">Student</th>
            <th className="stu">Grade</th>
            <th className="stu">Homeroom</th>
            <th className="ach">Needs a result in</th>
          </tr>
        </thead>
        <tbody>
          {students.map((s, i) => (
            <tr key={i}>
              <th className="col-task" scope="row">{s.lastName}, {s.firstName}</th>
              <td className="stu">{s.grade ?? '—'}</td>
              <td className="stu">{s.homeroom ?? '—'}</td>
              <td className="ach">
                {s.subjects.map((sub) => (
                  <span className="rwm-area no" key={sub} style={{ marginRight: '0.3rem' }}>{sub}</span>
                ))}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export default function MissingRollupTree({
  rows, cycle, showAll,
}: { rows: MissingDataRow[]; cycle: string; showAll?: boolean }) {
  const schools = useMemo<SchoolNode[]>(() => {
    const bySchool = new Map<string, SchoolNode & { tmap: Map<string, TeacherNode & { smap: Map<string, SectionNode> }> }>()
    for (const r of rows) {
      let sch = bySchool.get(r.schoolId)
      if (!sch) {
        sch = { id: r.schoolId, name: r.schoolName, teachers: [], rows: [], tmap: new Map() }
        bySchool.set(r.schoolId, sch)
      }
      sch.rows.push(r)
      const tKey = r.teacherEmail ?? NO_LEAD
      let t = sch.tmap.get(tKey)
      if (!t) {
        t = {
          key: tKey,
          label: r.teacherName ?? r.teacherEmail ?? 'No lead teacher',
          noLead: r.teacherEmail == null,
          sections: [], rows: [], smap: new Map(),
        }
        sch.tmap.set(tKey, t)
      }
      t.rows.push(r)
      let sec = t.smap.get(r.sectionId)
      if (!sec) {
        sec = {
          id: r.sectionId,
          label: r.courseName
            ? `${r.courseName}${r.sectionNumber ? ` · ${r.sectionNumber}` : ''}`
            : `Section ${r.sectionId}`,
          grades: [],
          rows: [],
        }
        t.smap.set(r.sectionId, sec)
      }
      sec.rows.push(r)
      if (r.grade && !sec.grades.includes(r.grade)) sec.grades.push(r.grade)
    }
    const out: SchoolNode[] = []
    for (const sch of bySchool.values()) {
      for (const t of sch.tmap.values()) {
        t.sections = [...t.smap.values()].sort((a, b) => a.label.localeCompare(b.label, undefined, { numeric: true }))
        sch.teachers.push(t)
      }
      // "No lead teacher" sorts last so real teachers read first; never silently dropped.
      sch.teachers.sort((a, b) => Number(a.noLead) - Number(b.noLead) || a.label.localeCompare(b.label))
      out.push({ id: sch.id, name: sch.name, teachers: sch.teachers, rows: sch.rows })
    }
    return out.sort((a, b) => a.name.localeCompare(b.name))
  }, [rows])

  const [openSchools, setOpenSchools] = useState<Set<string>>(() => new Set(schools.length === 1 ? [schools[0].id] : []))
  const [openNodes, setOpenNodes] = useState<Set<string>>(() => new Set())
  const [blocks, setBlocks] = useState<Record<string, BlockState>>({})

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

  function toggleSection(nodeId: string, sectionId: string) {
    const opening = !openNodes.has(nodeId)
    toggleNode(nodeId)
    if (opening && !blocks[sectionId]) {
      setBlocks((prev) => ({ ...prev, [sectionId]: { status: 'loading' } }))
      loadMissingGroup(sectionId, cycle)
        .then((res) =>
          setBlocks((prev) => ({
            ...prev,
            [sectionId]: res.error ? { status: 'error', message: res.error } : { status: 'done', rows: res.rows },
          })),
        )
        .catch(() =>
          setBlocks((prev) => ({ ...prev, [sectionId]: { status: 'error', message: 'Could not load this section. Please retry.' } })),
        )
    }
  }

  return (
    <div className="math-entry">
      <div className="mtoolbar">
        <span className="spacer" />
        {/* Close-only on purpose: an "expand all" would fire every section's lazy load at once. */}
        <button type="button" className="btn-ghost" onClick={() => { setOpenSchools(new Set()); setOpenNodes(new Set()) }}>
          Collapse all
        </button>
      </div>

      <div className="mlegend">
        <span className="grp"><strong>Students missing a result</strong> (confirmed IPPs excluded)</span>
        <span className="grp">% = reported ÷ expected data points · row colour matches:</span>
        <span className="grp">
          <span className="sw h1" /> &lt;50 <span className="sw h2" /> 50–74 <span className="sw h3" /> 75–99 <span className="sw h4" /> 100
        </span>
        <span className="grp">Math counts as reported at 80% of the cycle&apos;s tasks (the entry grid&apos;s own threshold).</span>
      </div>

      <div className="mtree-wrap">
        <table className="mgrid mtree">
          <thead>
            <tr>
              <th className="col-task">School</th>
              {SUBJECTS.map((s) => (
                <th className="rn" key={s}>{s}</th>
              ))}
              <th className="rn">Total</th>
              <th className="rpct-h">% reported</th>
            </tr>
          </thead>
          <tbody>
            {showAll && schools.length > 1 ? (
              (() => {
                const t = tally(schools.flatMap((s) => s.rows))
                return (
                  <tr className={`tnode lvl1 tcrce miss-${reportedBucket(t)}`}>
                    <th className="col-task" style={{ cursor: 'default' }}>
                      <span className="tchev" style={{ visibility: 'hidden' }}>▸</span>TCRCE<span className="tsub">all schools</span>
                    </th>
                    <CountCells t={t} />
                  </tr>
                )
              })()
            ) : null}
            {schools.map((sch) => {
              const open = openSchools.has(sch.id)
              const st = tally(sch.rows)
              return (
                <Fragment key={sch.id}>
                  <tr className={`tnode lvl1 miss-${reportedBucket(st)}`}>
                    <th className="col-task" onClick={() => toggleSchool(sch.id)}>
                      <span className="tchev">{open ? '▾' : '▸'}</span>{sch.name}
                    </th>
                    <CountCells t={st} />
                  </tr>
                  {open
                    ? sch.teachers.map((tch) => {
                        const tId = `T:${sch.id}:${tch.key}`
                        const tOpen = openNodes.has(tId)
                        const tt = tally(tch.rows)
                        return (
                          <Fragment key={tId}>
                            <tr className={`tnode lvl2 miss-${reportedBucket(tt)}`}>
                              <th className="col-task" onClick={() => toggleNode(tId)}>
                                <span className="tchev">{tOpen ? '▾' : '▸'}</span>{tch.label}
                                <span className="tsub">{tch.sections.length} section{tch.sections.length === 1 ? '' : 's'}</span>
                              </th>
                              <CountCells t={tt} />
                            </tr>
                            {tOpen
                              ? tch.sections.map((sec) => {
                                  const sId = `S:${tId}:${sec.id}`
                                  const sOpen = openNodes.has(sId)
                                  const sct = tally(sec.rows)
                                  const block = blocks[sec.id]
                                  return (
                                    <Fragment key={sId}>
                                      <tr className={`tnode lvl3 miss-${reportedBucket(sct)}`}>
                                        <th className="col-task" onClick={() => toggleSection(sId, sec.id)}>
                                          <span className="tchev">{sOpen ? '▾' : '▸'}</span>{sec.label}
                                          {sec.grades.length > 0 ? <span className="tsub">{gradeSpanLabel(sec.grades)}</span> : null}
                                        </th>
                                        <CountCells t={sct} />
                                      </tr>
                                      {sOpen ? (
                                        <tr className="blockrow">
                                          <td colSpan={6}>
                                            <div className="blockwrap">
                                              {!block || block.status === 'loading' ? (
                                                <p className="muted small" style={{ margin: 0 }}>Loading students…</p>
                                              ) : block.status === 'error' ? (
                                                <div className="notice notice-error">
                                                  <div className="notice-title">Couldn&apos;t load this section</div>
                                                  <div className="muted">{block.message}</div>
                                                </div>
                                              ) : (
                                                <SectionDetail rows={block.rows} />
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
