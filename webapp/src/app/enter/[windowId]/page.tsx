import Link from 'next/link'
import { PageHeader, CardLink, ScaffoldNote } from '@/components/ui'
import { mockGroups, MOCK_WINDOWS } from '@/lib/mock'

export const dynamic = 'force-dynamic'

export default async function GroupSelect({ params }: { params: Promise<{ windowId: string }> }) {
  const { windowId } = await params
  const win = MOCK_WINDOWS.find((w) => w.id === windowId)
  const groups = mockGroups(windowId)
  return (
    <>
      <PageHeader title="Choose a group" subtitle={`Step 2 — ${win?.name ?? windowId}`} />
      <p>
        <Link href="/enter" className="back-link">
          &larr; Back to windows
        </Link>
      </p>
      <ScaffoldNote>
        Groups are placeholder data &mdash; to be replaced by a roster-derived grouping for this window +
        teacher.
      </ScaffoldNote>
      <div className="card-grid">
        {groups.map((g) => (
          <CardLink
            key={g.key}
            href={`/enter/${windowId}/${g.key}`}
            title={g.label}
            meta={`${g.count} students`}
          />
        ))}
      </div>
    </>
  )
}
