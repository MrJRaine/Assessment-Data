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

// One assessment-type section: open windows above the fold + a collapsed accordion of past ones
// (still selectable, since late entry is allowed) + a count of upcoming windows.
function SubjectSection({ title, windows }: { title: string; windows: TeacherWindow[] }) {
  const current = windows.filter((w) => w.status === 'Open' || w.status === 'ClosesToday')
  const past = windows.filter((w) => w.status === 'Closed')
  const lower = title.toLowerCase()

  return (
    <section className="window-section">
      <h2 className="section-heading">{title}</h2>
      {current.length > 0 ? (
        <div className="card-grid">
          {current.map((w) => (
            <WindowCard key={w.id} w={w} />
          ))}
        </div>
      ) : (
        <p className="muted">No open {lower} window right now.</p>
      )}

      {past.length > 0 ? (
        <details className="accordion">
          <summary>
            Past {lower} windows ({past.length}) — still open for late entry
          </summary>
          <div className="card-grid">
            {past.map((w) => (
              <WindowCard key={w.id} w={w} />
            ))}
          </div>
        </details>
      ) : null}
    </section>
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

  const reading = windows.filter((w) => w.assessmentType === 'Reading')
  const writing = windows.filter((w) => w.assessmentType === 'Writing')
  const other = windows.filter((w) => w.assessmentType !== 'Reading' && w.assessmentType !== 'Writing')

  return (
    <>
      <PageHeader title="Data Entry" subtitle="Step 1 — choose an assessment window" />
      {error ? (
        <ErrorNote message={error} />
      ) : windows.length === 0 ? (
        <EmptyState
          title="No assessment windows for you right now"
          hint="Windows appear here once you have a roster in an active assessment window."
        />
      ) : (
        <>
          {reading.length > 0 ? <SubjectSection title="Reading" windows={reading} /> : null}
          {writing.length > 0 ? <SubjectSection title="Writing" windows={writing} /> : null}
          {other.length > 0 ? <SubjectSection title="Other" windows={other} /> : null}
        </>
      )}
    </>
  )
}
