'use client'

import { useMemo } from 'react'
import type { ReadingRollupRow, ReadingGroupRow } from '@/lib/data'
import { type RollupStudent, type LangFilter, buildSchools } from './rollupModel'
import { RollupTree } from './RollupTree'
import { loadReadingGroup } from './actions'

// Reading oversight roll-up: School → Grade/Homeroom → students (EN/FR reading level + band). Thin
// wrapper over the shared RollupTree; the per-group detail shows each student's English + French level.

export default function ReadingRollupTree({ rows, cycle, showAll }: { rows: ReadingRollupRow[]; cycle: string | null; showAll?: boolean }) {
  const schools = useMemo(() => {
    const byKey = new Map<string, RollupStudent>()
    for (const r of rows) {
      if (!r.schoolId) continue
      let s = byKey.get(r.studentKey)
      if (!s) {
        s = {
          key: r.studentKey, grade: r.grade ?? '', homeroom: r.homeroom, homeroomKey: r.homeroomKey,
          schoolId: r.schoolId, schoolName: r.schoolName ?? r.schoolId, ipp: r.readingIPP === true, results: [],
        }
        byKey.set(r.studentKey, s)
      }
      if (r.scaleSystem === 'EN_Reading' || r.scaleSystem === 'FR_Reading') {
        s.results.push({ en: r.scaleSystem === 'EN_Reading', code: r.achievementCode })
      }
    }
    return buildSchools([...byKey.values()])
  }, [rows])

  return (
    <RollupTree<ReadingGroupRow>
      schools={schools}
      cycle={cycle}
      showAll={showAll}
      loadGroup={loadReadingGroup}
      renderDetail={(groupRows, lang) => <ReadingDetail rows={groupRows} lang={lang} />}
    />
  )
}

// ── One group's students: English + French reading level, coloured by achievement band ────────────
interface DetailCell { levelCode: string | null; name: string | null; color: string | null; delta: number | null }
interface DetailStudent { key: string; name: string; grade: string | null; ipp: boolean; en: DetailCell | null; fr: DetailCell | null }

function pivot(rows: ReadingGroupRow[]): DetailStudent[] {
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
    return (
      <td className="stu">
        {ipp ? <span className="muted" title="IPP — not measured against the benchmark">IPP</span> : <span className="muted">—</span>}
      </td>
    )
  }
  const title = [cell.name, cell.delta == null ? null : `Δ ${cell.delta > 0 ? `+${cell.delta}` : cell.delta}`].filter(Boolean).join(' · ')
  return (
    <td className="stu" title={title || undefined}>
      <span style={cell.color ? { color: cell.color, fontWeight: 600 } : undefined}>{cell.levelCode}</span>
    </td>
  )
}

function ReadingDetail({ rows, lang }: { rows: ReadingGroupRow[]; lang: LangFilter }) {
  const all = pivot(rows)
  // Language filter: show only students with a result in the selected language (both level columns stay).
  const students = lang === 'All' ? all : all.filter((s) => (lang === 'EN' ? s.en : s.fr))
  if (students.length === 0) return <p className="muted small" style={{ margin: 0 }}>No students in this group for this language.</p>
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
