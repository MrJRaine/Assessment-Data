import Link from 'next/link'
import { PageHeader, EmptyState, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getTeacherRoster, getScaleLevels, type RosterStudent, type ScaleLevel } from '@/lib/data'
import RosterEntry from './RosterEntry'

export const dynamic = 'force-dynamic'

function groupLabel(groupKey: string): string {
  return groupKey.startsWith('HR:') ? `Homeroom ${groupKey.slice(3)}` : groupKey
}

export default async function RosterGrid({
  params,
}: {
  params: Promise<{ windowId: string; groupKey: string }>
}) {
  const { windowId, groupKey: rawGroupKey } = await params
  const groupKey = decodeURIComponent(rawGroupKey)
  const upn = await getCurrentUpn()

  let roster: RosterStudent[] = []
  let levels: ScaleLevel[] = []
  let error: string | null = null
  try {
    roster = await getTeacherRoster(upn, windowId, groupKey)
    const scaleSystem = roster[0]?.scaleSystem ?? null
    if (scaleSystem) levels = await getScaleLevels(scaleSystem)
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  return (
    <>
      <PageHeader title="Roster entry" subtitle={groupLabel(groupKey)} />
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
        <RosterEntry windowId={windowId} groupKey={groupKey} roster={roster} levels={levels} />
      )}
    </>
  )
}
