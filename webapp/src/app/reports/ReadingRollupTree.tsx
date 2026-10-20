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

// ── One group's students, STACKED: one row per (student x reading language); demographics merge ──
interface RowItem {
  studentNumber: string
  studentKey: string
  name: string
  grade: string | null
  ipp: boolean
  language: 'English' | 'French' | null
  levelCode: string | null
  levelOrder: number | null
  tint: string | null
  achName: string | null
  delta: number | null
  expMin: string | null
  expMax: string | null
  expMinOrder: number | null
}

function toRows(rows: ReadingGroupRow[]): RowItem[] {
  return rows.map((r) => ({
    studentNumber: r.studentNumber,
    studentKey: r.studentKey,
    name: `${r.lastName}, ${r.firstName}`,
    grade: r.grade,
    ipp: r.readingIPP === true,
    language: r.scaleSystem === 'EN_Reading' ? 'English' : r.scaleSystem === 'FR_Reading' ? 'French' : null,
    levelCode: r.levelCode,
    levelOrder: r.levelOrder,
    tint: r.achievementHexColorTint,
    achName: r.achievementName,
    delta: r.readingDelta,
    expMin: r.expectedMin,
    expMax: r.expectedMax,
    expMinOrder: r.expectedMinOrder,
  }))
}

type SortKey = 'name' | 'grade' | 'lang' | 'level' | 'expected' | 'diff'
type SortState = { key: SortKey; dir: 'asc' | 'desc' }
// A per-result sort SPLITS a student's stacked rows; a demographic sort (name/grade) keeps them merged.
const PER_RESULT: ReadonlySet<SortKey> = new Set<SortKey>(['lang', 'level', 'expected', 'diff'])
const langRank = (l: string | null) => (l === 'English' ? 0 : l === 'French' ? 1 : 2)
const langShort = (l: string | null) => (l === 'English' ? 'EN' : l === 'French' ? 'FR' : <span className="muted">—</span>)
const fmtExp = (r: RowItem): string => {
  if (r.levelCode == null || r.expMin == null) return '—'
  return r.expMax && r.expMax !== r.expMin ? `${r.expMin}–${r.expMax}` : r.expMin
}

function SortHead({ label, col, sort, onSort, className = 'stu' }: { label: string; col: SortKey; sort: SortState; onSort: (k: SortKey) => void; className?: string }) {
  const ind = sort.key === col ? (sort.dir === 'asc' ? ' ▲' : ' ▼') : ''
  return <th className={`${className} sortable`} onClick={() => onSort(col)}>{label}{ind}</th>
}

function ReadingDetail({ rows, lang }: { rows: ReadingGroupRow[]; lang: LangFilter }) {
  const [sort, setSort] = useState<SortState>({ key: 'name', dir: 'asc' })
  const all = toRows(rows)
  // Language filter: only rows in the selected language (a NULL-language no-result row shows under 'All').
  const filtered = lang === 'All' ? all : all.filter((r) => r.language === (lang === 'EN' ? 'English' : 'French'))
  if (filtered.length === 0) return <p className="muted small" style={{ margin: 0 }}>No students in this group for this language.</p>
  const showGrade = new Set(filtered.map((r) => r.grade)).size > 1

  const val = (r: RowItem, k: SortKey): string | number | null => {
    switch (k) {
      case 'name': return r.name
      case 'grade': return gradeRank(r.grade ?? '')
      case 'lang': return r.language
      case 'level': return r.levelOrder
      case 'expected': return r.expMinOrder
      case 'diff': return r.delta
    }
  }
  const dirCmp = (va: string | number | null, vb: string | number | null): number => {
    if (va == null && vb == null) return 0
    if (va == null) return 1 // nulls last
    if (vb == null) return -1
    const base = typeof va === 'number' && typeof vb === 'number' ? va - vb : String(va).localeCompare(String(vb))
    return sort.dir === 'desc' ? -base : base
  }
  const sorted = [...filtered].sort((a, b) => {
    const p = dirCmp(val(a, sort.key), val(b, sort.key))
    if (p !== 0) return p
    return a.name.localeCompare(b.name) || langRank(a.language) - langRank(b.language)
  })
  const click = (k: SortKey) => setSort((p) => (p.key === k ? { key: k, dir: p.dir === 'asc' ? 'desc' : 'asc' } : { key: k, dir: 'asc' }))

  // MERGE (demographic sort): a student's language rows stay together, Student/Grade merged (rowSpan).
  // SPLIT (per-result sort): rows flat, demographics repeated.
  const mergeMode = !PER_RESULT.has(sort.key)
  let groups: RowItem[][]
  if (mergeMode) {
    const byNum = new Map<string, RowItem[]>()
    const order: string[] = []
    for (const r of sorted) {
      let g = byNum.get(r.studentNumber)
      if (!g) { g = []; byNum.set(r.studentNumber, g); order.push(r.studentNumber) }
      g.push(r)
    }
    groups = order.map((n) => byNum.get(n)!.slice().sort((a, b) => langRank(a.language) - langRank(b.language)))
  } else {
    groups = sorted.map((r) => [r])
  }

  const renderRow = (r: RowItem, showDemo: boolean, span: number) => {
    const miss = <span className="muted">—</span>
    const hasResult = r.levelCode != null
    return (
      <tr key={`${r.studentNumber}:${r.language ?? 'none'}`}>
        {showDemo ? (
          <>
            <th className="col-task" scope="row" rowSpan={span}>
              <Link href={`/reports/${r.studentKey}`} className="back-link">{r.name}</Link>
            </th>
            {showGrade ? <td className="stu" rowSpan={span}>{r.grade ?? '—'}</td> : null}
          </>
        ) : null}
        <td className="stu">{langShort(r.language)}</td>
        <td className="stu" title={r.achName ?? undefined} style={hasResult && r.tint ? { background: r.tint } : undefined}>
          {hasResult ? <span style={{ fontWeight: 600 }}>{r.levelCode}</span> : (r.ipp ? <span className="muted" title="IPP — not measured against the benchmark">IPP</span> : miss)}
        </td>
        <td className="stu muted">{fmtExp(r)}</td>
        <td className="stu">{hasResult && r.delta != null ? (r.delta > 0 ? `+${r.delta}` : String(r.delta)) : miss}</td>
      </tr>
    )
  }

  return (
    <div className="mscroll">
      <table className="mgrid">
        <thead>
          <tr>
            <SortHead label="Student" col="name" sort={sort} onSort={click} className="col-task" />
            {showGrade ? <SortHead label="Grade" col="grade" sort={sort} onSort={click} /> : null}
            <SortHead label="Lang" col="lang" sort={sort} onSort={click} />
            <SortHead label="Reading Level" col="level" sort={sort} onSort={click} />
            <SortHead label="Expected" col="expected" sort={sort} onSort={click} />
            <SortHead label="Diff" col="diff" sort={sort} onSort={click} />
          </tr>
        </thead>
        <tbody>
          {groups.flatMap((g) => g.map((r, i) => renderRow(r, i === 0, g.length)))}
        </tbody>
      </table>
    </div>
  )
}
