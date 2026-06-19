import { PageHeader, CardLink, EmptyState, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getTeacherWindows, type TeacherWindow } from '@/lib/data'

export const dynamic = 'force-dynamic'

export default async function WindowSelect() {
  const upn = await getCurrentUpn()
  let windows: TeacherWindow[] = []
  let error: string | null = null
  try {
    windows = await getTeacherWindows(upn)
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  return (
    <>
      <PageHeader title="Enter Assessments" subtitle="Step 1 — choose an assessment window" />
      {error ? (
        <ErrorNote message={error} />
      ) : windows.length === 0 ? (
        <EmptyState
          title="No assessment windows for you right now"
          hint="Windows appear here once you have a roster in an active assessment window."
        />
      ) : (
        <div className="card-grid">
          {windows.map((w) => (
            <CardLink
              key={w.id}
              href={`/enter/${w.id}`}
              title={w.name}
              meta={`${w.status} · ${w.enteredCount}/${w.applicableCount} entered`}
            />
          ))}
        </div>
      )}
    </>
  )
}
