import Link from 'next/link'
import { EmptyState, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import {
  getTeacherGroups,
  getTeacherRoster,
  getTeacherRosterWriting,
  getMathRoster,
  getScaleLevels,
  getAchievementLevels,
  type TeacherGroup,
  type RosterStudent,
  type WritingRosterStudent,
  type MathRosterRow,
  type ScaleLevel,
  type AchievementBand,
  type WritingLanguage,
} from '@/lib/data'
import RosterEntry from './RosterEntry'
import WritingRosterEntry from './WritingRosterEntry'
import MathRosterEntry from './MathRosterEntry'

export const dynamic = 'force-dynamic'

export default async function RosterGrid({
  params,
}: {
  params: Promise<{ cycleGroupId: string; subject: string; groupKey: string }>
}) {
  const { cycleGroupId: rawCycle, subject: rawSubject, groupKey: rawGroupKey } = await params
  const cycleGroupId = decodeURIComponent(rawCycle)
  const subject = decodeURIComponent(rawSubject)
  const groupKey = decodeURIComponent(rawGroupKey)
  const upn = await getCurrentUpn()

  let roster: RosterStudent[] = []
  let writingRoster: WritingRosterStudent[] = []
  let mathRoster: MathRosterRow[] = []
  let levels: ScaleLevel[] = []
  let achievementLevels: AchievementBand[] = []
  let group: TeacherGroup | null = null
  let windowId: string | null = null
  let error: string | null = null

  const isWriting = subject === 'Writing'
  const isMath = subject === 'Math'

  try {
    // Re-resolve the caller's groups for this cycle + subject. This does three jobs at once:
    // it AUTHORIZES the group (a key the caller can't see resolves to nothing), it supplies the
    // display label, and it tells us which cycle INSTANCE this section's students sit under —
    // there is no windowId in the URL any more, because you pick a cycle, not an instance.
    const groups = await getTeacherGroups(upn, cycleGroupId, subject)
    group = groups.find((g) => g.key === groupKey) ?? null
    const windowIds = group?.windowIds ?? []
    if (group && windowIds.length > 1) {
      // Don't silently pick one and drop the other instance's students. This only happens when a
      // cycle is configured so a single section straddles two same-language instances.
      error = `This class falls under ${windowIds.length} scoped instances of this cycle, so entries can't be routed from one roster yet. Narrow the cycle's instances on the Cycles page, or enter by the narrower scope.`
    }
    windowId = windowIds[0] ?? null

    if (!error && windowId) {
      if (isWriting) {
        // The LANGUAGE comes from the course (an FLA section is French, an ELA section English),
        // so the old EN/FR toggle is gone — there is nothing for the teacher to get wrong.
        const language: WritingLanguage = group?.language === 'French' ? 'French' : 'English'
        writingRoster = await getTeacherRosterWriting(upn, windowId, groupKey, language)
      } else if (isMath) {
        mathRoster = await getMathRoster(upn, windowId, groupKey)
      } else {
        roster = await getTeacherRoster(upn, windowId, groupKey)
        const scaleSystem = roster[0]?.scaleSystem ?? null
        if (scaleSystem) levels = await getScaleLevels(scaleSystem)
        achievementLevels = await getAchievementLevels()
      }
    }
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  const language: WritingLanguage = group?.language === 'French' ? 'French' : 'English'
  const count = isMath
    ? new Set(mathRoster.map((r) => r.studentKey)).size
    : isWriting
      ? writingRoster.length
      : roster.length

  const groupDisplay = group?.label ?? groupKey
  const schoolName = group?.schoolName ?? null

  return (
    <>
      <div className="back-row">
        <Link href={`/enter/cycle/${rawCycle}/${rawSubject}`} className="back-link">
          &larr; Back to groups
        </Link>
        <span className="group-label">
          {groupDisplay}
          {schoolName ? ` · ${schoolName}` : ''} · {subject}
          {isWriting ? ` · ${language}` : ''}
        </span>
      </div>

      {error ? (
        <ErrorNote message={error} />
      ) : !group || !windowId ? (
        <EmptyState
          title="This class isn't in this cycle"
          hint="It may have no students in the cycle's grade or program scope, or you may no longer teach it."
        />
      ) : count === 0 ? (
        <EmptyState title="No students in this group for this cycle" />
      ) : isWriting ? (
        <WritingRosterEntry windowId={windowId} groupKey={groupKey} roster={writingRoster} language={language} />
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
