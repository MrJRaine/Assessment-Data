import Link from 'next/link'
import { PageHeader, EmptyState, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import {
  getWindowAssessmentType,
  getTeacherRoster,
  getTeacherRosterWriting,
  getScaleLevels,
  getAchievementLevels,
  type RosterStudent,
  type WritingRosterStudent,
  type ScaleLevel,
  type AchievementBand,
} from '@/lib/data'
import RosterEntry from './RosterEntry'
import WritingRosterEntry from './WritingRosterEntry'

export const dynamic = 'force-dynamic'

export default async function RosterGrid({
  params,
}: {
  params: Promise<{ windowId: string; groupKey: string }>
}) {
  const { windowId, groupKey: rawGroupKey } = await params
  const groupKey = decodeURIComponent(rawGroupKey)
  const upn = await getCurrentUpn()

  // The window's type drives which grid renders: Writing → four 1-4 trait inputs; Reading → level dropdown.
  let assessmentType: string | null = null
  let roster: RosterStudent[] = []
  let writingRoster: WritingRosterStudent[] = []
  let levels: ScaleLevel[] = []
  let achievementLevels: AchievementBand[] = []
  let error: string | null = null
  try {
    assessmentType = await getWindowAssessmentType(windowId)
    if (assessmentType === 'Writing') {
      writingRoster = await getTeacherRosterWriting(upn, windowId, groupKey)
    } else {
      roster = await getTeacherRoster(upn, windowId, groupKey)
      const scaleSystem = roster[0]?.scaleSystem ?? null
      if (scaleSystem) levels = await getScaleLevels(scaleSystem)
      achievementLevels = await getAchievementLevels()
    }
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  const isWriting = assessmentType === 'Writing'
  const count = isWriting ? writingRoster.length : roster.length

  // Friendly header from the roster rows (the URL key is opaque). Homeroom groups show
  // 'Homeroom <name> · <school>'; section groups (grade 10+) have no homeroom, so fall
  // back to the key.
  const firstRow = isWriting ? writingRoster[0] : roster[0]
  const groupDisplay = firstRow?.homeroom ? `Homeroom ${firstRow.homeroom}` : groupKey
  const schoolName = firstRow?.schoolName ?? null

  return (
    <>
      <PageHeader title="Roster entry" subtitle={`${groupDisplay}${schoolName ? ` · ${schoolName}` : ''} · ${isWriting ? 'Writing' : 'Reading'}`} />
      <p>
        <Link href={`/enter/${windowId}`} className="back-link">
          &larr; Back to groups
        </Link>
      </p>

      {error ? (
        <ErrorNote message={error} />
      ) : count === 0 ? (
        <EmptyState title="No students in this group for this window" />
      ) : isWriting ? (
        <WritingRosterEntry windowId={windowId} groupKey={groupKey} roster={writingRoster} />
      ) : (
        <RosterEntry
          windowId={windowId}
          groupKey={groupKey}
          roster={roster}
          levels={levels}
          achievementLevels={achievementLevels}
        />
      )}
    </>
  )
}
