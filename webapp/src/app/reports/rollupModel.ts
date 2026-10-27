// Shared model for the Reports oversight roll-up trees (Reading + Writing, 1.3.0). Subject-agnostic:
// a student carries a flat list of results, each tagged with its language (en = English) and achievement
// band code. The tree + counts are identical across subjects; only the per-group student DETAIL differs
// (reading = EN/FR level; writing = four COIL traits + average), which the subject wrappers supply.

export type SummarizeBy = 'Grade' | 'Homeroom'
export type LangFilter = 'All' | 'EN' | 'FR' // language-of-assessment filter (Slice 4)
export const MEETING_MIN = 3 // DimAchievementLevel code at/above = Meeting/Exceeding (b3 Meeting, b4 Exceeding)

// P–12 grade order (Math's own list stops at 6; reading/writing span further).
export const GRADE_ORDER: Record<string, number> = {
  PP: -1, P: 0, '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9, '10': 10, '11': 11, '12': 12,
}
export const gradeLabel = (g: string) => (g === 'P' ? 'Primary' : g === 'PP' ? 'Pre-Primary' : `Grade ${g}`)
export const gradeRank = (g: string) => GRADE_ORDER[g] ?? 99

// Compact grade-span label for a split homeroom, using grade CODES (P/PP/1…): a single grade -> "Grade P";
// two CONSECUTIVE grades -> "Grade P/1"; three or more consecutive -> "Grade P-2" (lower–upper); any
// NON-consecutive set -> "Grade P,2" / "Grade P,1,3".
export function gradeSpanLabel(grades: string[]): string {
  const sorted = [...new Set(grades)].sort((a, b) => gradeRank(a) - gradeRank(b))
  if (sorted.length === 0) return ''
  if (sorted.length === 1) return `Grade ${sorted[0]}`
  const ranks = sorted.map(gradeRank)
  const consecutive = ranks[ranks.length - 1] - ranks[0] === sorted.length - 1
  if (consecutive) {
    return sorted.length === 2
      ? `Grade ${sorted[0]}/${sorted[1]}`
      : `Grade ${sorted[0]}-${sorted[sorted.length - 1]}`
  }
  return `Grade ${sorted.join(',')}`
}

export type WritingTraitKey = 'conventions' | 'organization' | 'ideas' | 'language'

export interface RollupResult {
  en: boolean // true = English track, false = French
  code: number | null // achievement band for this result; null = no band (no delta/avg)
  // Writing only — the four trait scores (1–4; null = SCR/'-'/unscored) + the 4-trait average, for the
  // per-trait roll-up measures. Reading results omit these.
  traits?: { conventions: number | null; organization: number | null; ideas: number | null; language: number | null }
  avgScore?: number | null
}
export interface RollupStudent {
  key: string
  grade: string
  homeroom: string | null
  homeroomKey: string | null
  schoolId: string
  schoolName: string
  ipp: boolean // confirmed subject IPP — excluded from the % (not measured against the benchmark)
  results: RollupResult[]
}
export interface RollupSchool { id: string; name: string; students: RollupStudent[] }
export interface RollupChild {
  id: string
  label: string
  sub: string | null
  groupKey: string | null // GRADE:<school>:<grade> or a homeroom GroupKey; null = can't open (no homeroom)
  grades: string[]
  students: RollupStudent[]
}

export interface Counts {
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
  ippExcluded: number // results with a band that were left out of the % because the student is IPP
}

// Distinct STUDENTS (a both-languages student counts once) vs total RESULTS (counts per language), and
// % Meeting/Exceeding over results that carry a band — EXCLUDING IPP students (not measured), matching
// the Math roll-up's treatment. IPP results are tallied in `ippExcluded` for the hover.
//
// `lang` narrows the view to one language of assessment (Slice 4): a specific language counts only that
// language's results and DROPS students with none in it (so Students/Results reflect that language's
// population); 'All' keeps everything incl. no-result students.
export function tally(students: RollupStudent[], lang: LangFilter = 'All'): Counts {
  const c: Counts = {
    students: 0, studentsEN: 0, studentsFR: 0, studentsNone: 0,
    results: 0, resultsEN: 0, resultsFR: 0,
    meet: 0, band: 0, meetEN: 0, bandEN: 0, meetFR: 0, bandFR: 0, ippExcluded: 0,
  }
  for (const s of students) {
    const rs = lang === 'All' ? s.results : s.results.filter((r) => r.en === (lang === 'EN'))
    if (lang !== 'All' && rs.length === 0) continue // not part of this language's view
    c.students++
    let hasEN = false
    let hasFR = false
    for (const r of rs) {
      c.results++
      if (r.en) { c.resultsEN++; hasEN = true } else { c.resultsFR++; hasFR = true }
      if (r.code == null) continue
      if (s.ipp) { c.ippExcluded++; continue } // IPP: has a mark but isn't measured against the benchmark
      c.band++
      if (r.en) c.bandEN++
      else c.bandFR++
      if (r.code >= MEETING_MIN) {
        c.meet++
        if (r.en) c.meetEN++
        else c.meetFR++
      }
    }
    if (hasEN) c.studentsEN++
    if (hasFR) c.studentsFR++
    if (!hasEN && !hasFR) c.studentsNone++
  }
  return c
}

export const pctOf = (meet: number, band: number): number | null => (band === 0 ? null : meet / band)

// A rolled-up measure over a set of students (one per column in the writing roll-up): both the
// % Meeting/Exceeding inputs (meet/band) AND the Mean inputs (sum/count), so a client toggle can switch
// between them without re-querying. IPP results are excluded (not measured) and counted in ippExcluded.
export interface MeasureStat {
  meet: number; band: number; sum: number; count: number; ippExcluded: number
  // Per-language breakdown for the hover tooltip (parity with reading's Counts). EN = English results.
  meetEN: number; bandEN: number; sumEN: number; countEN: number
  meetFR: number; bandFR: number; sumFR: number; countFR: number
}
const zeroStat = (): MeasureStat => ({
  meet: 0, band: 0, sum: 0, count: 0, ippExcluded: 0,
  meetEN: 0, bandEN: 0, sumEN: 0, countEN: 0, meetFR: 0, bandFR: 0, sumFR: 0, countFR: 0,
})
export interface Measure {
  key: string
  label: string
  compute: (students: RollupStudent[], lang: LangFilter) => MeasureStat
}

// One writing trait's roll-up: band/count over scored results (1–4), meet over score >= Meeting, mean via sum.
export function traitMeasure(students: RollupStudent[], lang: LangFilter, key: WritingTraitKey): MeasureStat {
  const st = zeroStat()
  for (const s of students) {
    const rs = lang === 'All' ? s.results : s.results.filter((r) => r.en === (lang === 'EN'))
    for (const r of rs) {
      const v = r.traits?.[key]
      if (v == null) continue
      if (s.ipp) { st.ippExcluded++; continue }
      const meets = v >= MEETING_MIN
      st.band++; st.count++; st.sum += v
      if (meets) st.meet++
      if (r.en) { st.bandEN++; st.countEN++; st.sumEN += v; if (meets) st.meetEN++ }
      else      { st.bandFR++; st.countFR++; st.sumFR += v; if (meets) st.meetFR++ }
    }
  }
  return st
}

// The "average" column: meet/band from the average BAND (code), mean from the average SCORE.
export function avgMeasure(students: RollupStudent[], lang: LangFilter): MeasureStat {
  const st = zeroStat()
  for (const s of students) {
    const rs = lang === 'All' ? s.results : s.results.filter((r) => r.en === (lang === 'EN'))
    for (const r of rs) {
      if (r.code == null && r.avgScore == null) continue
      if (s.ipp) { if (r.code != null) st.ippExcluded++; continue }
      if (r.code != null) {
        const meets = r.code >= MEETING_MIN
        st.band++; if (meets) st.meet++
        if (r.en) { st.bandEN++; if (meets) st.meetEN++ } else { st.bandFR++; if (meets) st.meetFR++ }
      }
      if (r.avgScore != null) {
        st.count++; st.sum += r.avgScore
        if (r.en) { st.countEN++; st.sumEN += r.avgScore } else { st.countFR++; st.sumFR += r.avgScore }
      }
    }
  }
  return st
}

export function buildSchools(students: RollupStudent[]): RollupSchool[] {
  const bySchool = new Map<string, RollupSchool>()
  for (const s of students) {
    let sch = bySchool.get(s.schoolId)
    if (!sch) {
      sch = { id: s.schoolId, name: s.schoolName, students: [] }
      bySchool.set(s.schoolId, sch)
    }
    sch.students.push(s)
  }
  return [...bySchool.values()].sort((a, b) => a.name.localeCompare(b.name))
}

export function childrenOf(sch: RollupSchool, summarizeBy: SummarizeBy): RollupChild[] {
  const groups = new Map<string, RollupStudent[]>()
  for (const s of sch.students) {
    const k = summarizeBy === 'Grade' ? s.grade : s.homeroomKey ?? ''
    groups.set(k, [...(groups.get(k) ?? []), s])
  }
  const nodes: RollupChild[] = [...groups.entries()].map(([k, students]) => {
    const grades = [...new Set(students.map((s) => s.grade))].sort((a, b) => gradeRank(a) - gradeRank(b))
    if (summarizeBy === 'Grade') {
      return { id: `G:${sch.id}:${k}`, label: gradeLabel(k), sub: null, groupKey: `GRADE:${sch.id}:${k}`, grades, students }
    }
    const hr = students[0].homeroom
    return {
      id: `H:${sch.id}:${k}`,
      label: k && hr ? `Homeroom ${hr}` : 'No homeroom',
      sub: gradeSpanLabel(grades),
      groupKey: k || null,
      grades,
      students,
    }
  })
  return nodes.sort(
    (a, b) => gradeRank(a.grades[0]) - gradeRank(b.grades[0]) || a.label.localeCompare(b.label, undefined, { numeric: true }),
  )
}
