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
import ReadingRollupTree from './ReadingRollupTree'
import WritingRollupTree from './WritingRollupTree'
import CycleSelector from './CycleSelector'

export const dynamic = 'force-dynamic'

// Oversight roles get the School → Grade/Homeroom roll-up tree (reading, 1.3.0); teachers keep the
// flat per-student cohort list. Scope is enforced in the TVF regardless of this UI branch.
const OVERSIGHT = new Set(['Administrator', 'SpecialistTeacher', 'RegionalAnalyst'])

export default async function StudentsPage({
  searchParams,
}: {
  searchParams: Promise<{ subject?: string; cycle?: string }>
}) {
  const { subject, cycle: cycleParam } = await searchParams
  const isWriting = subject === 'writing'
  const upn = await getCurrentUpn()
  const cycle = cycleParam ?? null // cycle-binding applies to Reading AND Writing (cycles are shared)

  let cohort: CohortStudent[] = []
  let rollup: ReadingRollupRow[] = []
  let writingRollup: WritingRollupRow[] = []
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
    // Oversight roles get the School → Grade/Homeroom roll-up tree (Reading or Writing); teachers get the
    // flat per-student cohort list.
    if (oversight && !isWriting) {
      rollup = await getReadingCohortAll(upn, cycle)
    } else if (oversight && isWriting) {
      writingRollup = await getWritingCohortAll(upn, cycle)
    } else {
      cohort = isWriting ? await getStudentCohortWriting(upn, cycle) : await getStudentCohort(upn, cycle)
      bands = await getAchievementLevels()
      // Assessable grade scope (e.g. Reading = P–8) — scoped to the selected cycle's window when one is picked.
      assessableRange = await getAssessableGradeRange(isWriting ? 'Writing' : 'Reading', cycle)
    }
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  const useReadingTree = oversight && !isWriting
  const useWritingTree = oversight && isWriting

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
      ) : useReadingTree ? (
        // key on cycle so an expanded school doesn't survive a cycle switch (same reason as the Math tree).
        <ReadingRollupTree key={`reading:${cycle ?? 'current'}`} rows={rollup} cycle={cycle} showAll={regionWide} />
      ) : useWritingTree ? (
        <WritingRollupTree key={`writing:${cycle ?? 'current'}`} rows={writingRollup} cycle={cycle} showAll={regionWide} />
      ) : cohort.length === 0 ? (
        <EmptyState
          title="No students in your scope"
          hint={`${isWriting ? 'Writing' : 'Reading'} results and demographics appear here for students you can see.`}
        />
      ) : (
        // key on subject+cycle: the Reading/Writing toggle AND the cycle selector are SAME-ROUTE
        // soft navigations, so React reconciles this client component in place — which left stale
        // rows from the previous render mounted in the table (e.g. reading rows with reading columns
        // + reading links, inert to the writing sort) until a hard refresh. Keying forces a full
        // remount on either change: the old subtree is torn down and rebuilt fresh from the new data.
        // Filters/sort restore from sessionStorage, so the user's selections survive the remount.
        <CohortView key={`${isWriting ? 'writing' : 'reading'}:${cycle ?? 'current'}`} cohort={cohort} bands={bands} subject={isWriting ? 'Writing' : 'Reading'} assessableRange={assessableRange} />
      )}
    </>
  )
}
