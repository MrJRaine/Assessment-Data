import { PageHeader, CardLink, EmptyState, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getTeacherWindows, type TeacherWindow } from '@/lib/data'

export const dynamic = 'force-dynamic'

function WindowCard({ w }: { w: TeacherWindow }) {
  return (
    <CardLink
      href={`/enter/${w.id}`}
      title={w.name}
      meta={`${w.status} · ${w.enteredCount}/${w.applicableCount} entered`}
    />
  )
}

export default async function WindowSelect() {
  const upn = await getCurrentUpn()
  let windows: TeacherWindow[] = []
  let error: string | null = null
  try {
    windows = await getTeacherWindows(upn)
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  // Ongoing-assessment model: windows are monthly bins. Show open windows above the fold; tuck
  // closed (past) ones into a collapsed accordion — still selectable, since late entry is allowed.
  const current = windows.filter((w) => w.status === 'Open' || w.status === 'ClosesToday')
  const past = windows.filter((w) => w.status === 'Closed')
  const upcomingCount = windows.filter((w) => w.status === 'Upcoming').length

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
        <>
          {current.length > 0 ? (
            <div className="card-grid">
              {current.map((w) => (
                <WindowCard key={w.id} w={w} />
              ))}
            </div>
          ) : (
            <EmptyState
              title="No open windows right now"
              hint="A new window opens on the 1st of each month. Past windows are below — you can still enter results late."
            />
          )}

          {past.length > 0 ? (
            <details className="accordion">
              <summary>Past windows ({past.length}) — still open for late entry</summary>
              <div className="card-grid">
                {past.map((w) => (
                  <WindowCard key={w.id} w={w} />
                ))}
              </div>
            </details>
          ) : null}

          {upcomingCount > 0 ? (
            <p className="muted upcoming-note">
              {upcomingCount} upcoming window{upcomingCount === 1 ? '' : 's'} — each opens on the 1st of its month.
            </p>
          ) : null}
        </>
      )}
    </>
  )
}
