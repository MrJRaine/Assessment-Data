import Link from 'next/link'
import { EmptyState, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getProgrammingRoster, type ProgrammingRosterRow } from '@/lib/data'
import ProgrammingRosterGrid from './ProgrammingRosterGrid'

export const dynamic = 'force-dynamic'

export default async function ProgrammingGroupRoster({
  params,
}: {
  params: Promise<{ groupKey: string }>
}) {
  const { groupKey: raw } = await params
  const groupKey = decodeURIComponent(raw)
  const upn = await getCurrentUpn()

  let rows: ProgrammingRosterRow[] = []
  let error: string | null = null
  try {
    rows = await getProgrammingRoster(upn, groupKey)
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  // Friendly header from the rows (the URL key is opaque). Grade cohorts label by grade; sections
  // span homerooms so just say "Section"; otherwise the homeroom name.
  const first = rows[0]
  const gradeLabel = (g: string) =>
    g === 'P' ? 'Primary' : g === 'PP' ? 'Pre-Primary' : g === 'RG' ? 'Graduating' : `Grade ${g}`
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
        <Link href="/programming" className="back-link">
          &larr; Back to groups
        </Link>
        <span className="group-label">
          {groupDisplay}
          {schoolName ? ` · ${schoolName}` : ''} · Programming
        </span>
      </div>

      {error ? (
        <ErrorNote message={error} />
      ) : rows.length === 0 ? (
        <EmptyState
          title="No IPP or Adaptation records in this group"
          hint="Students appear here once PowerSchool flags an IPP or an Adaptation."
        />
      ) : (
        <ProgrammingRosterGrid groupKey={groupKey} rows={rows} />
      )}
    </>
  )
}
