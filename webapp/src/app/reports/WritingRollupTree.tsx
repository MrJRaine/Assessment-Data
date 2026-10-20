'use client'

import Link from 'next/link'
import { useMemo, useState, type ReactNode } from 'react'
import type { WritingRollupRow, WritingGroupRow } from '@/lib/data'
import { type RollupStudent, type LangFilter, type Measure, buildSchools, traitMeasure, avgMeasure, gradeRank } from './rollupModel'
import { RollupTree } from './RollupTree'
import { loadWritingGroup } from './actions'
import { traitsInOrder, type TraitMeta, type WritingTraitKey } from '@/lib/writingTraits'
import { useTraitOrder, TraitOrderToggle } from '@/components/TraitOrderToggle'

// Writing oversight roll-up: School → Grade/Homeroom → students (four COIL traits + average per
// language). Thin wrapper over the shared RollupTree; the COIL/IOLC toggle lives in the toolbar and
// re-orders the trait columns in the expanded student detail.

const langShort = (l: string | null) => (l === 'English' ? 'EN' : l === 'French' ? 'FR' : '—')

const scoreFor = (r: WritingGroupRow, key: WritingTraitKey): string | null =>
  key === 'ideas' ? r.ideasScore
    : key === 'organization' ? r.organizationScore
      : key === 'language' ? r.languageScore
        : r.conventionsScore

export default function WritingRollupTree({ rows, cycle, showAll, viewToggle }: { rows: WritingRollupRow[]; cycle: string | null; showAll?: boolean; viewToggle?: ReactNode }) {
  const [traitMode, setTraitMode] = useTraitOrder()
  const traits = useMemo(() => traitsInOrder(traitMode), [traitMode])

  const schools = useMemo(() => {
    const byKey = new Map<string, RollupStudent>()
    for (const r of rows) {
      if (!r.schoolId) continue
      let s = byKey.get(r.studentKey)
      if (!s) {
        s = {
          key: r.studentKey, grade: r.grade ?? '', homeroom: r.homeroom, homeroomKey: r.homeroomKey,
          schoolId: r.schoolId, schoolName: r.schoolName ?? r.schoolId, ipp: r.writingIPP === true, results: [],
        }
        byKey.set(r.studentKey, s)
      }
      if (r.assessmentLanguage === 'English' || r.assessmentLanguage === 'French') {
        s.results.push({
          en: r.assessmentLanguage === 'English',
          code: r.achievementCode,
          avgScore: r.avgScore,
          traits: {
            conventions: traitNum(r.conventionsScore),
            organization: traitNum(r.organizationScore),
            ideas: traitNum(r.ideasScore),
            language: traitNum(r.languageScore),
          },
        })
      }
    }
    return buildSchools([...byKey.values()])
  }, [rows])

  // Roll-up measure columns in the active COIL/IOLC order: one per trait (% at score >= 3, or mean) + the
  // overall average. The %/Mean toggle lives in RollupTree; these just supply the stats + labels.
  const measures: Measure[] = useMemo(
    () => [
      ...traits.map((t) => ({ key: t.key, label: t.label, compute: (s: RollupStudent[], l: LangFilter) => traitMeasure(s, l, t.key) })),
      { key: 'avg', label: 'Avg', compute: (s: RollupStudent[], l: LangFilter) => avgMeasure(s, l) },
    ],
    [traits],
  )

  return (
    <RollupTree<WritingGroupRow>
      schools={schools}
      cycle={cycle}
      showAll={showAll}
      loadGroup={loadWritingGroup}
      toolbarExtra={<TraitOrderToggle mode={traitMode} onChange={setTraitMode} />}
      renderDetail={(groupRows, lang) => <WritingDetail rows={groupRows} traits={traits} lang={lang} />}
      viewToggle={viewToggle}
      measures={measures}
    />
  )
}

// A trait score string ('1'-'4' | 'SCR' | '-' | null) → its numeric value, or null when not a 1–4 score
// (SCR / '-' / blank are dropped from both the % and the mean).
function traitNum(v: string | null): number | null {
  if (v == null || v === 'SCR' || v === '-') return null
  const n = Number(v)
  return Number.isFinite(n) ? n : null
}

// ── One group's students: the four writing traits (in the active COIL/IOLC order) + average, per
// language. One row per (student, language); a no-result student is a single "—" row. ───────────────
function TraitScoreCell({ value }: { value: string | null }) {
  if (value == null) return <td className="stu"><span className="muted">—</span></td>
  if (value === '-') return <td className="stu"><span className="muted" title="Not assessed this cycle">-</span></td>
  if (value === 'SCR') return <td className="stu"><span className="muted" title="Scribed — omitted from the average">SCR</span></td>
  return <td className="stu">{value}</td>
}

type WSortKey = 'student' | 'grade' | 'lang' | 'avg' | WritingTraitKey
type WSortState = { key: WSortKey; dir: 'asc' | 'desc' }

function WSortHead({ label, col, sort, onSort, className = 'stu' }: { label: string; col: WSortKey; sort: WSortState; onSort: (k: WSortKey) => void; className?: string }) {
  const ind = sort.key === col ? (sort.dir === 'asc' ? ' ▲' : ' ▼') : ''
  return <th className={`${className} sortable`} onClick={() => onSort(col)}>{label}{ind}</th>
}

function WritingDetail({ rows, traits, lang }: { rows: WritingGroupRow[]; traits: TraitMeta[]; lang: LangFilter }) {
  const [sort, setSort] = useState<WSortState>({ key: 'student', dir: 'asc' })
  const filtered = lang === 'All' ? rows : rows.filter((r) => r.assessmentLanguage === (lang === 'EN' ? 'English' : 'French'))
  if (filtered.length === 0) return <p className="muted small" style={{ margin: 0 }}>No students in this group for this language.</p>
  // Grade column only when the group spans >1 grade (redundant under a grade node; useful for a split homeroom).
  const showGrade = new Set(filtered.map((r) => r.grade)).size > 1

  const val = (r: WritingGroupRow, k: WSortKey): string | number | null => {
    switch (k) {
      case 'student': return `${r.lastName}, ${r.firstName}`.toLowerCase()
      case 'grade': return gradeRank(r.grade ?? '')
      case 'lang': return r.assessmentLanguage // 'English' | 'French' | null
      case 'avg': return r.avgScore
      default: return traitNum(scoreFor(r, k)) // one of the four trait keys
    }
  }
  const sortedRows = [...filtered].sort((a, b) => {
    const nameCmp = `${a.lastName}, ${a.firstName}`.localeCompare(`${b.lastName}, ${b.firstName}`)
    const va = val(a, sort.key)
    const vb = val(b, sort.key)
    if (va == null && vb == null) return nameCmp
    if (va == null) return 1 // nulls last
    if (vb == null) return -1
    const base = typeof va === 'number' && typeof vb === 'number' ? va - vb : String(va).localeCompare(String(vb))
    return base !== 0 ? (sort.dir === 'desc' ? -base : base) : nameCmp
  })
  const click = (k: WSortKey) => setSort((p) => (p.key === k ? { key: k, dir: p.dir === 'asc' ? 'desc' : 'asc' } : { key: k, dir: 'asc' }))

  return (
    <div className="mscroll">
      <table className="mgrid">
        <thead>
          <tr>
            <WSortHead label="Student" col="student" sort={sort} onSort={click} className="col-task" />
            {showGrade ? <WSortHead label="Grade" col="grade" sort={sort} onSort={click} /> : null}
            <WSortHead label="Lang" col="lang" sort={sort} onSort={click} />
            {traits.map((t) => <WSortHead key={t.key} label={t.label} col={t.key} sort={sort} onSort={click} />)}
            <WSortHead label="Avg" col="avg" sort={sort} onSort={click} />
          </tr>
        </thead>
        <tbody>
          {sortedRows.map((r, i) => {
            const noResult = r.assessmentLanguage == null
            return (
              <tr key={`${r.studentKey}:${r.assessmentLanguage ?? 'none'}:${i}`}>
                <th className="col-task" scope="row">
                  <Link href={`/reports/${r.studentKey}?subject=writing`} className="back-link">{r.lastName}, {r.firstName}</Link>
                  {r.writingIPP ? <span className="tsub" title="Writing IPP — excluded from % Meeting/Exceeding">IPP</span> : null}
                </th>
                {showGrade ? <td className="stu">{r.grade ?? '—'}</td> : null}
                <td className="stu">{langShort(r.assessmentLanguage)}</td>
                {traits.map((t) =>
                  noResult ? <td className="stu" key={t.key}><span className="muted">—</span></td>
                    : <TraitScoreCell key={t.key} value={scoreFor(r, t.key)} />,
                )}
                <td className="stu" style={r.achievementHexColor ? { color: r.achievementHexColor, fontWeight: 600 } : undefined}
                    title={r.achievementName ?? undefined}>
                  {r.avgScore == null ? <span className="muted">—</span> : r.avgScore.toFixed(2)}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}
