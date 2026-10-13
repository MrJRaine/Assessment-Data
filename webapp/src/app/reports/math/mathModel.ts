import type { MathCohortRow } from '@/lib/data'

// ── Shared Reports > Math model: the class matrix (MathCohortView) and the oversight roll-up tree
// (MathRollupTree) both compute Achievement Levels HERE, so a student's level is identical whichever
// view it's read from. P-5 only (the TVFs enforce it).

export type Mark = '1' | '0' | 'ipp' | 'blank'
export const rk = (studentKey: string, taskKey: string) => `${studentKey}:${taskKey}`

export interface Task {
  mathTaskKey: string
  unitName: string
  unitOrder: number
  questionNumber: string
  displayOrder: number
  outcomeCode: string | null
  description: string
}
export interface Unit { name: string; order: number; tasks: Task[] }
export interface Student { studentKey: string; studentNumber: string; name: string; fullName: string; mathIPP: boolean }
export interface Grade { grade: string; order: number; label: string; students: Student[]; units: Unit[] }

export const GRADE_ORDER: Record<string, number> = { PP: -1, P: 0, '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6 }
export const gradeLabel = (g: string) => (g === 'P' ? 'Primary' : g === 'PP' ? 'Pre-Primary' : `Grade ${g}`)

// Entry-grid achievement bands, applied to an average in [0,1].
export type BandCls = 'b1' | 'b2' | 'b3' | 'b4'
export const BAND_HEX: Record<BandCls, string> = { b1: '#b23347', b2: '#c07d16', b3: '#2f8f4e', b4: '#0092c9' }
export const BANDS: { cls: BandCls; name: string }[] = [
  { cls: 'b1', name: 'Emerging' },
  { cls: 'b2', name: 'Developing' },
  { cls: 'b3', name: 'Meeting' },
  { cls: 'b4', name: 'In-depth' },
]
export function bandForAvg(avg: number): { cls: BandCls; label: string } {
  if (avg < 0.5) return { cls: 'b1', label: 'Emerging' } // <50%
  if (avg < 0.75) return { cls: 'b2', label: 'Developing' } // 50–<75%
  if (avg < 0.9) return { cls: 'b3', label: 'Meeting' } // 75–<90%
  return { cls: 'b4', label: 'In-depth' } // ≥90%
}
export function heatClass(p: number | null) {
  return p == null ? 'none' : p > 0.8 ? 'h4' : p >= 0.65 ? 'h3' : p >= 0.5 ? 'h2' : 'h1'
}

// blankMode wires the "count blanks or not" decision the user asked to leave adjustable:
//  'exclude' (default) — a blank task doesn't count toward the average (denominator = filled cells).
//  'zero'              — a blank counts as a miss (denominator = every in-scope, non-IPP task).
export type BlankMode = 'exclude' | 'zero'

export interface UnitStat { avg: number | null; ipp: boolean; incomplete: boolean }

/**
 * One student's average for one unit, from cell counts. `inScope` excludes IPP cells (an IPP student's
 * unmarked task); `filled` = cells with a 0/1. Null avg = nothing scorable (all IPP, or nothing scored
 * in exclude mode). `incomplete` mirrors the entry grid's <80%-filled nudge.
 */
export function unitStat(c: { inScope: number; filled: number; ones: number; ipp: number }, blankMode: BlankMode): UnitStat {
  if (c.inScope === 0) return { avg: null, ipp: c.ipp > 0, incomplete: false } // all IPP
  const denom = blankMode === 'zero' ? c.inScope : c.filled
  if (denom === 0) return { avg: null, ipp: false, incomplete: false } // nothing scored
  return { avg: c.ones / denom, ipp: c.ipp > 0, incomplete: blankMode === 'exclude' && c.filled / c.inScope < 0.8 }
}

/** A student's overall roll-up = the mean of their unit averages (units with data only). */
export function meanOf(avgs: (number | null)[]): number | null {
  const xs = avgs.filter((v): v is number => v != null)
  return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null
}

// ── Roll-up tallies (oversight tree + block summary rows) ────────────────────────────────────────
// Every student in a node lands in exactly one bucket. The % is Meeting-or-In-depth over students
// WITH a level — IPP / No data / Incomplete are left out of it and shown in the hover instead.
export type Bucket = BandCls | 'inc' | 'ipp' | 'none'
export type Tally = Record<Bucket, number>
export const emptyTally = (): Tally => ({ b1: 0, b2: 0, b3: 0, b4: 0, inc: 0, ipp: 0, none: 0 })

/** Bucket for a unit cell. */
export function unitBucket(s: UnitStat): Bucket {
  if (s.avg == null) return s.ipp ? 'ipp' : 'none'
  if (s.incomplete) return 'inc'
  return bandForAvg(s.avg).cls
}
/** Bucket for the overall roll-up (never "Incomplete" — matches the matrix's overall cell). */
export function overallBucket(avg: number | null, mathIPP: boolean): Bucket {
  if (avg == null) return mathIPP ? 'ipp' : 'none'
  return bandForAvg(avg).cls
}
export function pctMeeting(t: Tally): number | null {
  const withLevel = t.b1 + t.b2 + t.b3 + t.b4
  return withLevel === 0 ? null : (t.b3 + t.b4) / withLevel
}
export function tallyTitle(t: Tally): string {
  return [
    `Emerging: ${t.b1}`,
    `Developing: ${t.b2}`,
    `Meeting: ${t.b3}`,
    `In-depth: ${t.b4}`,
    ...(t.inc ? [`Incomplete: ${t.inc}`] : []),
    `IPP: ${t.ipp}`,
    `No data: ${t.none}`,
  ].join('\n')
}
/** 2-decimal table percentage, or an em dash when no student has a level. */
export const fmtPct = (p: number | null) => (p == null ? '—' : `${(p * 100).toFixed(2)}%`)

// ── Matrix builders (one group's student × task rows → grades/units/tasks + marks) ──────────────
export function buildGrades(rows: MathCohortRow[]): Grade[] {
  const byGrade = new Map<string, Grade>()
  for (const r of rows) {
    const g = r.grade ?? '?'
    let grade = byGrade.get(g)
    if (!grade) {
      grade = { grade: g, order: GRADE_ORDER[g] ?? 99, label: gradeLabel(g), students: [], units: [] }
      byGrade.set(g, grade)
    }
    if (!grade.students.some((s) => s.studentKey === r.studentKey)) {
      grade.students.push({
        studentKey: r.studentKey,
        studentNumber: r.studentNumber,
        name: `${r.firstName} ${r.lastName.charAt(0)}.`,
        fullName: `${r.firstName} ${r.lastName}`,
        mathIPP: r.mathIPPStatus === true,
      })
    }
    let unit = grade.units.find((u) => u.name === (r.unitName ?? ''))
    if (!unit) {
      unit = { name: r.unitName ?? '', order: r.unitOrder ?? 0, tasks: [] }
      grade.units.push(unit)
    }
    if (!unit.tasks.some((t) => t.mathTaskKey === r.mathTaskKey)) {
      unit.tasks.push({
        mathTaskKey: r.mathTaskKey,
        unitName: r.unitName ?? '',
        unitOrder: r.unitOrder ?? 0,
        questionNumber: r.questionNumber ?? '',
        displayOrder: r.displayOrder ?? 0,
        outcomeCode: r.outcomeCode,
        description: r.description ?? '',
      })
    }
  }
  const grades = [...byGrade.values()].sort((a, b) => a.order - b.order)
  for (const g of grades) {
    g.students.sort((a, b) => a.name.localeCompare(b.name))
    g.units.sort((a, b) => a.order - b.order)
    for (const u of g.units) u.tasks.sort((a, b) => a.displayOrder - b.displayOrder)
  }
  return grades
}

export function buildMarks(rows: MathCohortRow[]): Record<string, Mark> {
  const m: Record<string, Mark> = {}
  for (const r of rows) {
    const key = rk(r.studentKey, r.mathTaskKey)
    if (r.result === true) m[key] = '1'
    else if (r.result === false) m[key] = '0'
    else m[key] = r.mathIPPStatus === true ? 'ipp' : 'blank'
  }
  return m
}

/** Count one student's marks over a unit's tasks (input to unitStat). */
export function countUnit(mark: (taskKey: string) => Mark, u: Unit) {
  let inScope = 0, filled = 0, ones = 0, ipp = 0
  for (const t of u.tasks) {
    const v = mark(t.mathTaskKey)
    if (v === 'ipp') { ipp++; continue }
    inScope++
    if (v === '1' || v === '0') { filled++; if (v === '1') ones++ }
  }
  return { inScope, filled, ones, ipp }
}
