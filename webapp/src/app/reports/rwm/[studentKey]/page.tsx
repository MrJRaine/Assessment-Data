import Link from 'next/link'
import { EmptyState, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getStudentCohortRWM, getStudentRWMHistory, type RWMStudent, type RWMHistoryRow } from '@/lib/data'
import RWMStudentView from './RWMStudentView'

export const dynamic = 'force-dynamic'

// Reports > RWM > one student: per-area snapshot + 0–3 per-cycle table + trend.
export default async function RwmStudentPage({
  params,
}: {
  params: Promise<{ studentKey: string }>
}) {
  const { studentKey } = await params
  const upn = await getCurrentUpn()

  let cohort: RWMStudent[] = []
  let history: RWMHistoryRow[] = []
  let error: string | null = null
  try {
    ;[cohort, history] = await Promise.all([getStudentCohortRWM(upn), getStudentRWMHistory(upn, studentKey)])
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  // Stable order for prev/next (same as the table would show without filters).
  const ordered = [...cohort].sort((a, b) => a.lastName.localeCompare(b.lastName) || a.firstName.localeCompare(b.firstName))
  const idx = ordered.findIndex((s) => s.studentKey === studentKey)
  const student = idx >= 0 ? ordered[idx] : null
  const prev = idx > 0 ? ordered[idx - 1] : null
  const next = idx >= 0 && idx < ordered.length - 1 ? ordered[idx + 1] : null

  if (error) {
    return (
      <>
        <div className="back-row"><Link href="/reports/rwm" className="back-link">&larr; Back to RWM</Link></div>
        <ErrorNote message={error} />
      </>
    )
  }
  if (!student) {
    return (
      <>
        <div className="back-row"><Link href="/reports/rwm" className="back-link">&larr; Back to RWM</Link></div>
        <EmptyState title="Student not found in your scope" hint="This student may not be a Primary–6 student you can see, or has a confirmed IPP." />
      </>
    )
  }

  return (
    <RWMStudentView
      student={student}
      history={history}
      position={idx + 1}
      total={ordered.length}
      prevKey={prev?.studentKey ?? null}
      nextKey={next?.studentKey ?? null}
    />
  )
}
