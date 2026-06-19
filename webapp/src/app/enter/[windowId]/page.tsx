import Link from 'next/link'
import { PageHeader, CardLink, EmptyState, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getTeacherGroups, type TeacherGroup } from '@/lib/data'

export const dynamic = 'force-dynamic'

export default async function GroupSelect({ params }: { params: Promise<{ windowId: string }> }) {
  const { windowId } = await params
  const upn = await getCurrentUpn()
  let groups: TeacherGroup[] = []
  let error: string | null = null
  try {
    groups = await getTeacherGroups(upn, windowId)
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  return (
    <>
      <PageHeader title="Choose a group" subtitle="Step 2 — your homerooms / sections for this window" />
      <p>
        <Link href="/enter" className="back-link">
          &larr; Back to windows
        </Link>
      </p>
      {error ? (
        <ErrorNote message={error} />
      ) : groups.length === 0 ? (
        <EmptyState
          title="No groups for this window"
          hint="You have no homeroom or section roster in this window's grade/program scope."
        />
      ) : (
        <div className="card-grid">
          {groups.map((g) => (
            <CardLink
              key={g.key}
              href={`/enter/${windowId}/${g.key}`}
              title={g.label}
              meta={`${g.enteredCount}/${g.applicableCount} entered`}
            />
          ))}
        </div>
      )}
    </>
  )
}
