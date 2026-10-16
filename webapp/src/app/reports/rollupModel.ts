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

export interface RollupResult {
  en: boolean // true = English track, false = French
  code: number | null // achievement band for this result; null = no band (no delta/avg)
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
      sub: grades.map(gradeLabel).join(', '),
      groupKey: k || null,
      grades,
      students,
    }
  })
  return nodes.sort(
    (a, b) => gradeRank(a.grades[0]) - gradeRank(b.grades[0]) || a.label.localeCompare(b.label, undefined, { numeric: true }),
  )
}
