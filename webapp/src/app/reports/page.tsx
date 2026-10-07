import Link from 'next/link'
import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import {
  getStudentCohort,
  getStudentCohortWriting,
  getAchievementLevels,
  getAssessableGradeRange,
  getReportCycles,
  type CohortStudent,
  type AchievementBand,
  type ReportCycle,
} from '@/lib/data'
import CohortView from './CohortView'
import CycleSelector from './CycleSelector'

export const dynamic = 'force-dynamic'

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
  let bands: AchievementBand[] = []
  let assessableRange: { minOrder: number; maxOrder: number } | null = null
  let cycles: ReportCycle[] = []
  let error: string | null = null
  try {
    cohort = isWriting ? await getStudentCohortWriting(upn, cycle) : await getStudentCohort(upn, cycle)
    bands = await getAchievementLevels()
    // Assessable grade scope (e.g. Reading = P–8) — scoped to the selected cycle's window when one is picked.
    assessableRange = await getAssessableGradeRange(isWriting ? 'Writing' : 'Reading', cycle)
    cycles = await getReportCycles()
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
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
      ) : cohort.length === 0 ? (
        <EmptyState
          title="No students in your scope"
          hint={`${isWriting ? 'Writing' : 'Reading'} assessments and demographics appear here for students you can see.`}
        />
      ) : (
        <CohortView cohort={cohort} bands={bands} subject={isWriting ? 'Writing' : 'Reading'} assessableRange={assessableRange} />
      )}
    </>
  )
}
