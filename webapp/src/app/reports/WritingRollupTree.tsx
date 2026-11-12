'use client'

import Link from 'next/link'
import { useMemo, useState, type ReactNode } from 'react'
import type { WritingRollupRow, WritingGroupRow, AchievementBand, ReportCycle } from '@/lib/data'
import { type RollupStudent, type LangFilter, type SummarizeBy, type Measure, type DemoFilter, buildSchools, traitMeasure, avgMeasure, gradeRank, demoPass } from './rollupModel'
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

// Rows → one RollupStudent per student, results tagged with language + date (date feeds the trend).
function buildStudents(rows: WritingRollupRow[]): RollupStudent[] {
  const byKey = new Map<string, RollupStudent>()
  for (const r of rows) {
    if (!r.schoolId) continue
    let s = byKey.get(r.studentKey)
    if (!s) {
      s = {
        key: r.studentKey, grade: r.grade ?? '', homeroom: r.homeroom, homeroomKey: r.homeroomKey,
        schoolId: r.schoolId, schoolName: r.schoolName ?? r.schoolId, ipp: r.writingIPP === true,
        gender: r.gender, selfIDAfrican: r.selfIDAfrican, selfIDIndigenous: r.selfIDIndigenous,
        expectedEN: false, expectedFR: false, results: [],
      }
      byKey.set(r.studentKey, s)
    }
    if (r.isExpectedOnly && (r.assessmentLanguage === 'English' || r.assessmentLanguage === 'French')) {
      // Expected in this language, no result yet: keeps the student in that language's view
      // (tally counts them under Students / "no result") without inventing a phantom result.
      if (r.assessmentLanguage === 'English') s.expectedEN = true
      else s.expectedFR = true
    } else if (r.assessmentLanguage === 'English' || r.assessmentLanguage === 'French') {
      s.results.push({
        en: r.assessmentLanguage === 'English',
        code: r.achievementCode,
        date: r.assessmentDate,
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
  return [...byKey.values()]
}

export default function WritingRollupTree({ rows, trendRows, bands, cycles, cycle, showAll, viewToggle }: {
  rows: WritingRollupRow[]
  // All-cycles rows for the by-cycle trend (rows are cycle-scoped); bands/cycles feed the charts.
  trendRows: WritingRollupRow[]
  bands: AchievementBand[]
  cycles: ReportCycle[]
  cycle: string | null
  showAll?: boolean
  viewToggle?: ReactNode
}) {
  const [traitMode, setTraitMode] = useTraitOrder()
  const traits = useMemo(() => traitsInOrder(traitMode), [traitMode])

  const schools = useMemo(() => buildSchools(buildStudents(rows)), [rows])
  const charts = useMemo(
    () => ({ trendStudents: buildStudents(trendRows), bands, cycles }),
    [trendRows, bands, cycles],
  )

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
      renderDetail={(groupRows, lang, summarizeBy, demo) => <WritingDetail rows={groupRows} traits={traits} lang={lang} summarizeBy={summarizeBy} demo={demo} />}
      viewToggle={viewToggle}
      measures={measures}
      charts={charts}
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

type WSortKey = 'student' | 'grade' | 'homeroom' | 'lang' | 'avg' | 'achievement' | WritingTraitKey
type WSortState = { key: WSortKey; dir: 'asc' | 'desc' }
// A per-result sort SPLITS a student's stacked rows; a demographic sort (student/grade/homeroom) keeps them merged.
const PER_RESULT_W: ReadonlySet<WSortKey> = new Set<WSortKey>(['lang', 'avg', 'achievement', 'ideas', 'organization', 'language', 'conventions'])
const langRankW = (l: string | null) => (l === 'English' ? 0 : l === 'French' ? 1 : 2)

function WSortHead({ label, col, sort, onSort, className = 'stu' }: { label: string; col: WSortKey; sort: WSortState; onSort: (k: WSortKey) => void; className?: string }) {
  const ind = sort.key === col ? (sort.dir === 'asc' ? ' ▲' : ' ▼') : ''
  return <th className={`${className} sortable`} onClick={() => onSort(col)}>{label}{ind}</th>
}

function WritingDetail({ rows, traits, lang, summarizeBy, demo }: { rows: WritingGroupRow[]; traits: TraitMeta[]; lang: LangFilter; summarizeBy: SummarizeBy; demo: DemoFilter }) {
  const [sort, setSort] = useState<WSortState>({ key: 'student', dir: 'asc' })
  // Demographic filters first (so the drill matches the filtered node counts above it), then language.
  const demoRows = rows.filter(demoPass(demo))
  const filtered = lang === 'All' ? demoRows : demoRows.filter((r) => r.assessmentLanguage === (lang === 'EN' ? 'English' : 'French'))
  if (filtered.length === 0) return <p className="muted small" style={{ margin: 0 }}>No students in this group match the current filters.</p>
  // The node already pins one axis: a Grade node drills to Homeroom; a Homeroom node drills to Grade.
  // (Neither repeats School — the drill is always inside one school.)
  const demoAxis: 'grade' | 'homeroom' = summarizeBy === 'Grade' ? 'homeroom' : 'grade'

  const val = (r: WritingGroupRow, k: WSortKey): string | number | null => {
    switch (k) {
      case 'student': return `${r.lastName}, ${r.firstName}`.toLowerCase()
      case 'grade': return gradeRank(r.grade ?? '')
      case 'homeroom': return r.homeroom
      case 'lang': return r.assessmentLanguage // 'English' | 'French' | null
      case 'avg': return r.avgScore
      case 'achievement': return r.achievementCode
      default: return traitNum(scoreFor(r, k)) // one of the four trait keys
    }
  }
  const sorted = [...filtered].sort((a, b) => {
    const nameCmp = `${a.lastName}, ${a.firstName}`.localeCompare(`${b.lastName}, ${b.firstName}`)
    const va = val(a, sort.key)
    const vb = val(b, sort.key)
    if (va == null && vb == null) return nameCmp || langRankW(a.assessmentLanguage) - langRankW(b.assessmentLanguage)
    if (va == null) return 1 // nulls last
    if (vb == null) return -1
    const base = typeof va === 'number' && typeof vb === 'number' ? va - vb : String(va).localeCompare(String(vb))
    return base !== 0 ? (sort.dir === 'desc' ? -base : base) : (nameCmp || langRankW(a.assessmentLanguage) - langRankW(b.assessmentLanguage))
  })
  const click = (k: WSortKey) => setSort((p) => (p.key === k ? { key: k, dir: p.dir === 'asc' ? 'desc' : 'asc' } : { key: k, dir: 'asc' }))

  // MERGE (demographic sort): a student's language rows stay together, Student/Grade merged (rowSpan).
  // SPLIT (per-result sort): rows flat, demographics repeated.
  const mergeMode = !PER_RESULT_W.has(sort.key)
  let groups: WritingGroupRow[][]
  if (mergeMode) {
    const byNum = new Map<string, WritingGroupRow[]>()
    const order: string[] = []
    for (const r of sorted) {
      let g = byNum.get(r.studentNumber)
      if (!g) { g = []; byNum.set(r.studentNumber, g); order.push(r.studentNumber) }
      g.push(r)
    }
    groups = order.map((n) => byNum.get(n)!.slice().sort((a, b) => langRankW(a.assessmentLanguage) - langRankW(b.assessmentLanguage)))
  } else {
    groups = sorted.map((r) => [r])
  }

  const renderRow = (r: WritingGroupRow, showDemo: boolean, span: number) => {
    const noResult = r.assessmentLanguage == null
    const hasResult = r.avgScore != null
    return (
      <tr key={`${r.studentNumber}:${r.assessmentLanguage ?? 'none'}`}>
        {showDemo ? (
          <>
            <th className="col-task" scope="row" rowSpan={span}>
              <Link href={`/reports/${r.studentKey}?subject=writing`} className="back-link">{r.lastName}, {r.firstName}</Link>
              {r.writingIPP ? <span className="tsub" title="Writing IPP — excluded from % Meeting/Exceeding">IPP</span> : null}
            </th>
            <td className="stu" rowSpan={span}>{(demoAxis === 'homeroom' ? r.homeroom : r.grade) ?? '—'}</td>
          </>
        ) : null}
        <td className="stu">{langShort(r.assessmentLanguage)}</td>
        {traits.map((t) =>
          noResult ? <td className="stu" key={t.key}><span className="muted">—</span></td>
            : <TraitScoreCell key={t.key} value={scoreFor(r, t.key)} />,
        )}
        <td className="stu" title={r.achievementName ?? undefined}
            style={hasResult && r.achievementHexColorTint ? { background: r.achievementHexColorTint } : undefined}>
          {r.avgScore == null ? <span className="muted">—</span> : r.avgScore.toFixed(2)}
        </td>
        {/* Keyed off the band, not the avg: an IPP student's result keeps its traits/avg but the feed
            gives it no band (not measured) — show "IPP" there, like the flat list. */}
        <td className="ach" style={hasResult && r.achievementHexColor ? { color: r.achievementHexColor, fontWeight: 600 } : undefined}>
          {r.achievementName ?? (r.writingIPP ? 'IPP' : <span className="muted">—</span>)}
        </td>
      </tr>
    )
  }

  return (
    <div className="mscroll">
      <table className="mgrid">
        <thead>
          <tr>
            <WSortHead label="Student" col="student" sort={sort} onSort={click} className="col-task" />
            <WSortHead label={demoAxis === 'homeroom' ? 'Homeroom' : 'Grade'} col={demoAxis} sort={sort} onSort={click} />
            <WSortHead label="Lang" col="lang" sort={sort} onSort={click} />
            {traits.map((t) => <WSortHead key={t.key} label={t.label} col={t.key} sort={sort} onSort={click} />)}
            <WSortHead label="Avg" col="avg" sort={sort} onSort={click} />
            <WSortHead label="Achievement" col="achievement" sort={sort} onSort={click} className="ach" />
          </tr>
        </thead>
        <tbody>
          {groups.flatMap((g) => g.map((r, i) => renderRow(r, i === 0, g.length)))}
        </tbody>
      </table>
    </div>
  )
}
