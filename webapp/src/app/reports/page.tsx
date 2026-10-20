import Link from 'next/link'
import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import {
  getStudentCohort,
  getStudentCohortWriting,
  getAchievementLevels,
  getAssessableGradeRange,
  getReportCycles,
  getCallerAccessLevel,
  getReadingCohortAll,
  getWritingCohortAll,
  type CohortStudent,
  type AchievementBand,
  type ReportCycle,
  type ReadingRollupRow,
  type WritingRollupRow,
} from '@/lib/data'
import CohortView from './CohortView'
import CohortCharts from './CohortCharts'
import ReadingRollupTree from './ReadingRollupTree'
import WritingRollupTree from './WritingRollupTree'
import CycleSelector from './CycleSelector'

export const dynamic = 'force-dynamic'

// Oversight roles (Administrator / SpecialistTeacher / RegionalAnalyst) LAND on the School → Grade/Homeroom
// roll-up tree, with the flat per-student cohort list available as a second view (?view=list) — both carry
// the two charts at the top. Teachers get the flat cohort list directly. Scope is enforced in the TVFs
// regardless of this UI branch.
const OVERSIGHT = new Set(['Administrator', 'SpecialistTeacher', 'RegionalAnalyst'])

export default async function StudentsPage({
  searchParams,
}: {
  searchParams: Promise<{ subject?: string; cycle?: string; view?: string }>
}) {
  const { subject, cycle: cycleParam, view: viewParam } = await searchParams
  const isWriting = subject === 'writing'
  const upn = await getCurrentUpn()
  const cycle = cycleParam ?? null // cycle-binding applies to Reading AND Writing (cycles are shared)
  const view = viewParam === 'list' ? 'list' : 'summary' // oversight: roll-up (default) vs flat student list

  let cohort: CohortStudent[] = []
  let trendCohort: CohortStudent[] | undefined // all-cycles cohort for the by-cycle trend (teachers)
  let rollup: ReadingRollupRow[] = []
  let rollupAll: ReadingRollupRow[] = [] // all-cycles (for the trend); == rollup when no cycle selected
  let writingRollup: WritingRollupRow[] = []
  let writingRollupAll: WritingRollupRow[] = []
  let bands: AchievementBand[] = []
  let assessableRange: { minOrder: number; maxOrder: number } | null = null
  let cycles: ReportCycle[] = []
  let oversight = false
  let regionWide = false // RegionalAnalyst = sees all schools → gets the TCRCE all-schools roll-up row
  let error: string | null = null
  try {
    const accessLevel = await getCallerAccessLevel(upn)
    oversight = accessLevel != null && OVERSIGHT.has(accessLevel)
    regionWide = accessLevel === 'RegionalAnalyst'
    cycles = await getReportCycles()
    bands = await getAchievementLevels()
    if (oversight) {
      // Roll-up feed: cycle-scoped (donut + tree). The trend is cycle-INDEPENDENT, so pull an all-cycles
      // copy too — but only when a cycle is actually selected; otherwise they're identical (one read).
      if (!isWriting) {
        rollup = await getReadingCohortAll(upn, cycle)
        rollupAll = cycle == null ? rollup : await getReadingCohortAll(upn, null)
      } else {
        writingRollup = await getWritingCohortAll(upn, cycle)
        writingRollupAll = cycle == null ? writingRollup : await getWritingCohortAll(upn, null)
      }
      // The flat student list is a second view, loaded only when selected.
      if (view === 'list') {
        cohort = isWriting ? await getStudentCohortWriting(upn, cycle) : await getStudentCohort(upn, cycle)
        assessableRange = await getAssessableGradeRange(isWriting ? 'Writing' : 'Reading', cycle)
      }
    } else {
      cohort = isWriting ? await getStudentCohortWriting(upn, cycle) : await getStudentCohort(upn, cycle)
      assessableRange = await getAssessableGradeRange(isWriting ? 'Writing' : 'Reading', cycle)
      // By-cycle trend is cycle-independent: all-cycles copy (reuse `cohort` when no cycle is selected).
      trendCohort = cycle == null
        ? undefined
        : isWriting ? await getStudentCohortWriting(upn, null) : await getStudentCohort(upn, null)
    }
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  // Chart feeds for the oversight top charts: donut = cycle-scoped rollup; trend = all-cycles rollup.
  const donutRows = (isWriting ? writingRollup : rollup).map((r) => ({ code: r.achievementCode }))
  const trendRows = (isWriting ? writingRollupAll : rollupAll).map((r) => ({ code: r.achievementCode, date: r.assessmentDate }))

  // View-switch hrefs, preserving subject + cycle.
  const viewHref = (v: 'summary' | 'list') => {
    const p = new URLSearchParams()
    if (isWriting) p.set('subject', 'writing')
    if (cycle) p.set('cycle', cycle)
    if (v === 'list') p.set('view', 'list')
    const qs = p.toString()
    return qs ? `/reports?${qs}` : '/reports'
  }

  return (
    <>
      <PageHeader title="Reports" subtitle="Cohort — filter, view distribution, and drill down to the student level" />
      <div className="subject-toggle">
        <Link href="/reports" className={!isWriting ? 'toggle-on' : 'toggle'}>
          Reading
        </Link>
        <Link href="/reports?subject=writing" className={isWriting ? 'toggle-on' : 'toggle'}>
          Writing
        </Link>
        <Link href="/reports/math" className="toggle">
          Math
        </Link>
        <Link href="/reports/rwm" className="toggle">
          RWM
        </Link>
      </div>
      {cycles.length > 0 ? <CycleSelector cycles={cycles} /> : null}
      {error ? (
        <ErrorNote message={error} />
      ) : oversight ? (
        <>
          {/* Two charts on top of BOTH views: donut follows the cycle selector; the by-cycle trend is
              independent of it (always the full year). */}
          <CohortCharts donutRows={donutRows} trendRows={trendRows} bands={bands} cycles={cycles} />
          <div className="subject-toggle" role="tablist" aria-label="Report view">
            <Link href={viewHref('summary')} className={view === 'summary' ? 'toggle-on' : 'toggle'}>
              Summary
            </Link>
            <Link href={viewHref('list')} className={view === 'list' ? 'toggle-on' : 'toggle'}>
              Student list
            </Link>
          </div>
          {view === 'list' ? (
            cohort.length === 0 ? (
              <EmptyState
                title="No students in your scope"
                hint={`${isWriting ? 'Writing' : 'Reading'} results and demographics appear here for students you can see.`}
              />
            ) : (
              // Charts render at the page top for oversight, so suppress CohortView's own copy.
              <CohortView
                key={`${isWriting ? 'writing' : 'reading'}:${cycle ?? 'current'}:list`}
                cohort={cohort}
                bands={bands}
                cycles={cycles}
                subject={isWriting ? 'Writing' : 'Reading'}
                assessableRange={assessableRange}
                showCharts={false}
              />
            )
          ) : isWriting ? (
            <WritingRollupTree key={`writing:${cycle ?? 'current'}`} rows={writingRollup} cycle={cycle} showAll={regionWide} />
          ) : (
            <ReadingRollupTree key={`reading:${cycle ?? 'current'}`} rows={rollup} cycle={cycle} showAll={regionWide} />
          )}
        </>
      ) : cohort.length === 0 ? (
        <EmptyState
          title="No students in your scope"
          hint={`${isWriting ? 'Writing' : 'Reading'} results and demographics appear here for students you can see.`}
        />
      ) : (
        // key on subject+cycle: the Reading/Writing toggle AND the cycle selector are SAME-ROUTE soft
        // navigations, so React reconciles this client component in place — which left stale rows from the
        // previous render mounted until a hard refresh. Keying forces a full remount on either change.
        // Filters/sort restore from sessionStorage, so the user's selections survive the remount.
        <CohortView
          key={`${isWriting ? 'writing' : 'reading'}:${cycle ?? 'current'}`}
          cohort={cohort}
          bands={bands}
          cycles={cycles}
          subject={isWriting ? 'Writing' : 'Reading'}
          assessableRange={assessableRange}
          trendCohort={trendCohort}
        />
      )}
    </>
  )
}
