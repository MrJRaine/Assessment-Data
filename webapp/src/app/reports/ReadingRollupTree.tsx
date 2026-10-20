'use client'

import Link from 'next/link'
import { useMemo, useState, type ReactNode } from 'react'
import type { ReadingRollupRow, ReadingGroupRow } from '@/lib/data'
import { type RollupStudent, type LangFilter, buildSchools, gradeRank } from './rollupModel'
import { RollupTree } from './RollupTree'
import { loadReadingGroup } from './actions'

// Reading oversight roll-up: School → Grade/Homeroom → students (EN/FR reading level + band). Thin
// wrapper over the shared RollupTree; the per-group detail shows each student's English + French level.

export default function ReadingRollupTree({ rows, cycle, showAll, viewToggle }: { rows: ReadingRollupRow[]; cycle: string | null; showAll?: boolean; viewToggle?: ReactNode }) {
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
      viewToggle={viewToggle}
    />
  )
}

// ── One group's students: per-language reading Level, Expected benchmark, and Diff from expected ──
interface DetailCell {
  levelCode: string | null
  levelOrder: number | null
  name: string | null
  tint: string | null // achievement-band tint for the level-cell background
  delta: number | null // signed difference from the expected benchmark
  expMin: string | null
  expMax: string | null
  expMinOrder: number | null
}
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
      const cell: DetailCell = {
        levelCode: r.levelCode, levelOrder: r.levelOrder, name: r.achievementName, tint: r.achievementHexColorTint,
        delta: r.readingDelta, expMin: r.expectedMin, expMax: r.expectedMax, expMinOrder: r.expectedMinOrder,
      }
      if (r.scaleSystem === 'EN_Reading') s.en = cell
      else s.fr = cell
    }
  }
  return [...byKey.values()]
}

function LevelCell({ cell, ipp, sep }: { cell: DetailCell | null; ipp: boolean; sep?: boolean }) {
  const cls = `stu${sep ? ' grp-sep' : ''}`
  if (!cell || cell.levelCode == null) {
    return (
      <td className={cls}>
        {ipp ? <span className="muted" title="IPP — not measured against the benchmark">IPP</span> : <span className="muted">—</span>}
      </td>
    )
  }
  // Colour-code the CELL (uniform block, easy to scan) rather than the variable-width level text; limited
  // to this one level column so a dual-language student's EN/FR bands never clash.
  return (
    <td className={cls} title={cell.name ?? undefined} style={cell.tint ? { background: cell.tint } : undefined}>
      <span style={{ fontWeight: 600 }}>{cell.levelCode}</span>
    </td>
  )
}
// Expected benchmark range (collapse when min==max); only where the student has a result in that language.
function fmtExpected(cell: DetailCell | null): string {
  if (!cell || cell.levelCode == null || cell.expMin == null) return '—'
  return cell.expMax && cell.expMax !== cell.expMin ? `${cell.expMin}–${cell.expMax}` : cell.expMin
}
// Signed difference from the expected benchmark.
function fmtDiff(cell: DetailCell | null): string {
  if (!cell || cell.levelCode == null || cell.delta == null) return '—'
  return cell.delta > 0 ? `+${cell.delta}` : String(cell.delta)
}

type SortKey = 'name' | 'grade' | 'enLevel' | 'enExp' | 'enDiff' | 'frLevel' | 'frExp' | 'frDiff'
type SortState = { key: SortKey; dir: 'asc' | 'desc' }

function SortHead({ label, col, sort, onSort, className = 'stu', rowSpan }: { label: string; col: SortKey; sort: SortState; onSort: (k: SortKey) => void; className?: string; rowSpan?: number }) {
  const ind = sort.key === col ? (sort.dir === 'asc' ? ' ▲' : ' ▼') : ''
  return <th rowSpan={rowSpan} className={`${className} sortable`} onClick={() => onSort(col)}>{label}{ind}</th>
}

function ReadingDetail({ rows, lang }: { rows: ReadingGroupRow[]; lang: LangFilter }) {
  const [sort, setSort] = useState<SortState>({ key: 'name', dir: 'asc' })
  const all = pivot(rows)
  // Language filter: show only students with a result in the selected language (both level columns stay).
  const filtered = lang === 'All' ? all : all.filter((s) => (lang === 'EN' ? s.en : s.fr))
  if (filtered.length === 0) return <p className="muted small" style={{ margin: 0 }}>No students in this group for this language.</p>
  // Grade column only when the group spans >1 grade (redundant under a grade node; useful for a split homeroom).
  const showGrade = new Set(filtered.map((s) => s.grade)).size > 1

  const val = (s: DetailStudent, k: SortKey): string | number | null => {
    switch (k) {
      case 'name': return s.name
      case 'grade': return gradeRank(s.grade ?? '')
      case 'enLevel': return s.en?.levelOrder ?? null
      case 'enExp': return s.en?.expMinOrder ?? null
      case 'enDiff': return s.en?.delta ?? null
      case 'frLevel': return s.fr?.levelOrder ?? null
      case 'frExp': return s.fr?.expMinOrder ?? null
      case 'frDiff': return s.fr?.delta ?? null
    }
  }
  const students = [...filtered].sort((a, b) => {
    const va = val(a, sort.key)
    const vb = val(b, sort.key)
    if (va == null && vb == null) return a.name.localeCompare(b.name)
    if (va == null) return 1 // nulls last
    if (vb == null) return -1
    const base = typeof va === 'number' && typeof vb === 'number' ? va - vb : String(va).localeCompare(String(vb))
    return base !== 0 ? (sort.dir === 'desc' ? -base : base) : a.name.localeCompare(b.name)
  })
  const click = (k: SortKey) => setSort((p) => (p.key === k ? { key: k, dir: p.dir === 'asc' ? 'desc' : 'asc' } : { key: k, dir: 'asc' }))

  return (
    <div className="mscroll">
      <table className="mgrid">
        <thead>
          <tr>
            <SortHead label="Student" col="name" sort={sort} onSort={click} className="col-task" rowSpan={2} />
            {showGrade ? <SortHead label="Grade" col="grade" sort={sort} onSort={click} rowSpan={2} /> : null}
            <th className="stu grp-head" colSpan={3}>English</th>
            <th className="stu grp-head grp-sep" colSpan={3}>French</th>
          </tr>
          <tr>
            <SortHead label="Reading Level" col="enLevel" sort={sort} onSort={click} />
            <SortHead label="Expected" col="enExp" sort={sort} onSort={click} />
            <SortHead label="Diff" col="enDiff" sort={sort} onSort={click} />
            <SortHead label="Reading Level" col="frLevel" sort={sort} onSort={click} className="stu grp-sep" />
            <SortHead label="Expected" col="frExp" sort={sort} onSort={click} />
            <SortHead label="Diff" col="frDiff" sort={sort} onSort={click} />
          </tr>
        </thead>
        <tbody>
          {students.map((s) => (
            <tr key={s.key}>
              <th className="col-task" scope="row">
                <Link href={`/reports/${s.key}`} className="back-link">{s.name}</Link>
              </th>
              {showGrade ? <td className="stu">{s.grade ?? '—'}</td> : null}
              <LevelCell cell={s.en} ipp={s.ipp} />
              <td className="stu muted">{fmtExpected(s.en)}</td>
              <td className="stu">{fmtDiff(s.en)}</td>
              <LevelCell cell={s.fr} ipp={s.ipp} sep />
              <td className="stu muted">{fmtExpected(s.fr)}</td>
              <td className="stu">{fmtDiff(s.fr)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
