import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import {
  getStudentCohort,
  getAchievementLevels,
  type CohortStudent,
  type AchievementBand,
} from '@/lib/data'
import CohortView from './CohortView'

export const dynamic = 'force-dynamic'

export default async function StudentsPage() {
  const upn = await getCurrentUpn()

  let cohort: CohortStudent[] = []
  let bands: AchievementBand[] = []
  let error: string | null = null
  try {
    cohort = await getStudentCohort(upn)
    bands = await getAchievementLevels()
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  return (
    <>
      <PageHeader title="Student Data" subtitle="Cohort — filter, view distribution, and drill into a student" />
      {error ? (
        <ErrorNote message={error} />
      ) : cohort.length === 0 ? (
        <EmptyState title="No students in your scope" hint="Reading assessments and demographics appear here for students you can see." />
      ) : (
        <CohortView cohort={cohort} bands={bands} />
      )}
    </>
  )
}
