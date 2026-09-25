import Link from 'next/link'
import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getStudentCohortRWM, type RWMStudent } from '@/lib/data'
import RWMCohortView from './RWMCohortView'

export const dynamic = 'force-dynamic'

// Reports > RWM: a 0–3 Reading·Writing·Math achievement roll-up, Primary–6 only.
export default async function RwmReportsPage() {
  const upn = await getCurrentUpn()

  let cohort: RWMStudent[] = []
  let error: string | null = null
  try {
    cohort = await getStudentCohortRWM(upn)
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  return (
    <>
      <PageHeader title="Reports" subtitle="RWM — how many of Reading · Writing · Math each student is currently meeting or exceeding" />
      <div className="subject-toggle">
        <Link href="/reports" className="toggle">Reading</Link>
        <Link href="/reports?subject=writing" className="toggle">Writing</Link>
        <Link href="/reports/math" className="toggle">Math</Link>
        <Link href="/reports/rwm" className="toggle-on">RWM</Link>
      </div>
      <p className="muted small" style={{ margin: '0 0 1rem' }}>
        Primary–6 only. A student&apos;s score counts Reading, Writing, and Math where their most-recent
        result is Meeting or Exceeding (Math: rolled-up ≥ 75%). Students with a confirmed IPP in any of
        the three are excluded.
      </p>
      {error ? (
        <ErrorNote message={error} />
      ) : cohort.length === 0 ? (
        <EmptyState
          title="No students in your scope"
          hint="Primary–6 students (without a confirmed IPP in Reading, Writing, or Math) appear here."
        />
      ) : (
        <RWMCohortView cohort={cohort} />
      )}
    </>
  )
}
