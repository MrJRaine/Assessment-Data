import Link from 'next/link'
import { EmptyState, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import {
  getWindowAssessmentType,
  getTeacherRoster,
  getTeacherRosterWriting,
  getMathRoster,
  getScaleLevels,
  getAchievementLevels,
  type RosterStudent,
  type WritingRosterStudent,
  type MathRosterRow,
  type ScaleLevel,
  type AchievementBand,
} from '@/lib/data'
import RosterEntry from './RosterEntry'
import WritingRosterEntry from './WritingRosterEntry'
import MathRosterEntry from './MathRosterEntry'

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

  // The window's type drives which grid renders: Writing → four 1-4 trait inputs;
  // Math → the student × task mastery matrix; Reading → level dropdown.
  let assessmentType: string | null = null
  let roster: RosterStudent[] = []
  let writingRoster: WritingRosterStudent[] = []
  let mathRoster: MathRosterRow[] = []
  let levels: ScaleLevel[] = []
  let achievementLevels: AchievementBand[] = []
  let error: string | null = null
  try {
    assessmentType = await getWindowAssessmentType(windowId)
    if (assessmentType === 'Writing') {
      writingRoster = await getTeacherRosterWriting(upn, windowId, groupKey)
    } else if (assessmentType === 'Math') {
      mathRoster = await getMathRoster(upn, windowId, groupKey)
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
  const isMath = assessmentType === 'Math'
  const subject = isWriting ? 'Writing' : isMath ? 'Math' : 'Reading'
  const count = isMath
    ? new Set(mathRoster.map((r) => r.studentKey)).size
    : isWriting
      ? writingRoster.length
      : roster.length

  return (
    <>
      <div className="back-row">
        <Link href={`/enter/${windowId}`} className="back-link">
          &larr; Back to groups
        </Link>
        <span className="group-label">{groupLabel(groupKey)} · {subject}</span>
      </div>

      {error ? (
        <ErrorNote message={error} />
      ) : count === 0 ? (
        <EmptyState title="No students in this group for this cycle" />
      ) : isWriting ? (
        <WritingRosterEntry windowId={windowId} groupKey={groupKey} roster={writingRoster} />
      ) : isMath ? (
        <MathRosterEntry windowId={windowId} groupKey={groupKey} rows={mathRoster} />
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
