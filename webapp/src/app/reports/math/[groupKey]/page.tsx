import Link from 'next/link'
import { EmptyState, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getMathCohort, type MathCohortRow } from '@/lib/data'
import MathCohortView from './MathCohortView'

export const dynamic = 'force-dynamic'

// Reports > Math > one group. Read-only results matrix (styled like the entry grid) over ALL of the
// current year's math cycles, latest result per task. P-6.
export default async function MathCohortPage({
  params,
}: {
  params: Promise<{ groupKey: string }>
}) {
  const { groupKey: raw } = await params
  const groupKey = decodeURIComponent(raw)
  const upn = await getCurrentUpn()

  let rows: MathCohortRow[] = []
  let error: string | null = null
  try {
    rows = await getMathCohort(upn, groupKey)
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  const first = rows[0]
  const gradeLabel = (g: string) =>
    g === 'P' ? 'Primary' : g === 'PP' ? 'Pre-Primary' : `Grade ${g}`
  const groupDisplay = groupKey.startsWith('GRADE:')
    ? gradeLabel(first?.grade ?? groupKey.split(':').pop() ?? '')
    : groupKey.startsWith('SEC:')
      ? 'Section'
      : first?.homeroom
        ? `Homeroom ${first.homeroom}`
        : groupKey
  const schoolName = first?.schoolName ?? null

  return (
    <>
      <div className="back-row">
        <Link href="/reports/math" className="back-link">
          &larr; Back to groups
        </Link>
        <span className="group-label">
          {groupDisplay}
          {schoolName ? ` · ${schoolName}` : ''} · Math results
        </span>
      </div>

      {error ? (
        <ErrorNote message={error} />
      ) : rows.length === 0 ? (
        <EmptyState
          title="No students in this group"
          hint="Math results appear here once this class has Primary–6 students on roll."
        />
      ) : (
        <MathCohortView rows={rows} />
      )}
    </>
  )
}
