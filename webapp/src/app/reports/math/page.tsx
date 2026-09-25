import Link from 'next/link'
import { redirect } from 'next/navigation'
import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getMathCohortGroups, type TeacherGroup } from '@/lib/data'
import GroupCards from '@/components/GroupCards'

export const dynamic = 'force-dynamic'

// Reports > Math landing. Math is P-6 and the matrix is group-scoped (a whole-school grid is
// unusable), so — like Data Entry and Programming — the caller first picks a homeroom or a grade
// cohort. Picking one opens its read-only results matrix.
export default async function MathReportsPage() {
  const upn = await getCurrentUpn()

  let groups: TeacherGroup[] = []
  let error: string | null = null
  try {
    groups = await getMathCohortGroups(upn)
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  // A caller with exactly one group jumps straight to it (teacher with a single homeroom).
  if (!error && groups.length === 1) {
    redirect(`/reports/math/${encodeURIComponent(groups[0].key)}`)
  }

  return (
    <>
      <PageHeader title="Reports" subtitle="Math — pick a class or grade to see the results matrix" />
      <div className="subject-toggle">
        <Link href="/reports" className="toggle">Reading</Link>
        <Link href="/reports?subject=writing" className="toggle">Writing</Link>
        <Link href="/reports/math" className="toggle-on">Math</Link>
        <Link href="/reports/rwm" className="toggle">RWM</Link>
      </div>
      <p className="muted small" style={{ margin: '0 0 1rem' }}>
        Math results cover grades Primary–6 only.
      </p>
      {error ? (
        <ErrorNote message={error} />
      ) : groups.length === 0 ? (
        <EmptyState
          title="No classes in your scope"
          hint="Math results appear here for the Primary–6 classes you can see."
        />
      ) : (
        <GroupCards groups={groups} hrefBase="/reports/math" metaSuffix="students" metaMode="count" />
      )}
    </>
  )
}
