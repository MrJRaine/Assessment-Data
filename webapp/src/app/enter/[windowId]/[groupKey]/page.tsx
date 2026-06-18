import Link from 'next/link'
import { PageHeader, ScaffoldNote, Placeholder } from '@/components/ui'
import { MOCK_STUDENTS, MOCK_WINDOWS, mockGroups } from '@/lib/mock'

export const dynamic = 'force-dynamic'

export default async function RosterGrid({
  params,
}: {
  params: Promise<{ windowId: string; groupKey: string }>
}) {
  const { windowId, groupKey } = await params
  const win = MOCK_WINDOWS.find((w) => w.id === windowId)
  const group = mockGroups(windowId).find((g) => g.key === groupKey)
  return (
    <>
      <PageHeader title="Roster entry" subtitle={`${win?.name ?? windowId} · ${group?.label ?? groupKey}`} />
      <p>
        <Link href={`/enter/${windowId}`} className="back-link">
          &larr; Back to groups
        </Link>
      </p>
      <ScaffoldNote>
        Entry grid is placeholder structure &mdash; rows, level combo, IPP toggle, and Save bind to the
        secured roster view + submission proc.
      </ScaffoldNote>
      <table className="grid">
        <thead>
          <tr>
            <th>Student</th>
            <th>Grade</th>
            <th>Current level</th>
            <th>New level</th>
            <th>IPP</th>
          </tr>
        </thead>
        <tbody>
          {MOCK_STUDENTS.map((s) => (
            <tr key={s.key}>
              <td>{s.name}</td>
              <td>{s.grade}</td>
              <td className="muted">&mdash;</td>
              <td>
                <Placeholder label="level combo" />
              </td>
              <td>
                <Placeholder label="toggle" />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <div className="actions">
        <button className="btn" disabled>
          Save (wiring pending)
        </button>
      </div>
    </>
  )
}
