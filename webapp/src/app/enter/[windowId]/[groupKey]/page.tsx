import Link from 'next/link'
import { PageHeader, ScaffoldNote, EmptyState, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getTeacherRoster, type RosterStudent } from '@/lib/data'

export const dynamic = 'force-dynamic'

function groupLabel(groupKey: string): string {
  return groupKey.startsWith('HR:') ? `Homeroom ${groupKey.slice(3)}` : groupKey
}

function ippText(s: RosterStudent): string {
  if (s.ippStatus === true) return 'IPP'
  if (s.ippStatus === false) return 'Not IPP'
  return s.ippNeedsConfirmation ? 'Confirm' : '—'
}

export default async function RosterGrid({
  params,
}: {
  params: Promise<{ windowId: string; groupKey: string }>
}) {
  const { windowId, groupKey } = await params
  const upn = await getCurrentUpn()
  let roster: RosterStudent[] = []
  let error: string | null = null
  try {
    roster = await getTeacherRoster(upn, windowId, decodeURIComponent(groupKey))
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  return (
    <>
      <PageHeader title="Roster entry" subtitle={groupLabel(decodeURIComponent(groupKey))} />
      <p>
        <Link href={`/enter/${windowId}`} className="back-link">
          &larr; Back to groups
        </Link>
      </p>

      {error ? (
        <ErrorNote message={error} />
      ) : roster.length === 0 ? (
        <EmptyState title="No students in this group for this window" />
      ) : (
        <>
          <ScaffoldNote>
            Reading current state (live). Level entry + Save bind to <code>usp_UpsertReadingAssessment</code>{' '}
            once it accepts an <code>@UPN</code> parameter for the service-principal connection.
          </ScaffoldNote>
          <table className="grid">
            <thead>
              <tr>
                <th>Student</th>
                <th>Grade</th>
                <th>Current level</th>
                <th>Expected</th>
                <th>Δ</th>
                <th>IPP</th>
              </tr>
            </thead>
            <tbody>
              {roster.map((s) => (
                <tr key={s.studentKey}>
                  <td>
                    {s.lastName}, {s.firstName}
                  </td>
                  <td>{s.grade ?? '—'}</td>
                  <td>
                    {s.currentLevel ?? <span className="muted">not entered</span>}
                    {s.assessmentDate ? <span className="muted"> · {s.assessmentDate}</span> : null}
                  </td>
                  <td className="muted">
                    {s.expectedMin && s.expectedMax ? `${s.expectedMin}–${s.expectedMax}` : '—'}
                  </td>
                  <td>{s.currentDelta === null ? '—' : s.currentDelta > 0 ? `+${s.currentDelta}` : s.currentDelta}</td>
                  <td className={s.ippNeedsConfirmation ? 'ipp-confirm' : undefined}>{ippText(s)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </>
  )
}
