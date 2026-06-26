import Link from 'next/link'
import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import {
  getStudentCohort,
  getStudentCohortWriting,
  getAchievementLevels,
  type CohortStudent,
  type AchievementBand,
} from '@/lib/data'
import CohortView from './CohortView'

export const dynamic = 'force-dynamic'

export default async function StudentsPage({
  searchParams,
}: {
  searchParams: Promise<{ subject?: string }>
}) {
  const { subject } = await searchParams
  const isWriting = subject === 'writing'
  const upn = await getCurrentUpn()

  let cohort: CohortStudent[] = []
  let bands: AchievementBand[] = []
  let error: string | null = null
  try {
    cohort = isWriting ? await getStudentCohortWriting(upn) : await getStudentCohort(upn)
    bands = await getAchievementLevels()
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  return (
    <>
      <PageHeader title="Student Data" subtitle="Cohort — filter, view distribution, and drill into a student" />
      <div className="subject-toggle">
        <Link href="/students" className={!isWriting ? 'toggle-on' : 'toggle'}>
          Reading
        </Link>
        <Link href="/students?subject=writing" className={isWriting ? 'toggle-on' : 'toggle'}>
          Writing
        </Link>
      </div>
      {error ? (
        <ErrorNote message={error} />
      ) : cohort.length === 0 ? (
        <EmptyState
          title="No students in your scope"
          hint={`${isWriting ? 'Writing' : 'Reading'} assessments and demographics appear here for students you can see.`}
        />
      ) : (
        <CohortView cohort={cohort} bands={bands} subject={isWriting ? 'Writing' : 'Reading'} />
      )}
    </>
  )
}
