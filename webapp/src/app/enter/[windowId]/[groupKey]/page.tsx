import Link from 'next/link'
import { EmptyState, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import {
  getWindowAssessmentType,
  getWindowLanguage,
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
  type WritingLanguage,
} from '@/lib/data'
import RosterEntry from './RosterEntry'
import WritingRosterEntry from './WritingRosterEntry'
import MathRosterEntry from './MathRosterEntry'

export const dynamic = 'force-dynamic'

export default async function RosterGrid({
  params,
  searchParams,
}: {
  params: Promise<{ windowId: string; groupKey: string }>
  searchParams: Promise<{ lang?: string }>
}) {
  const { windowId, groupKey: rawGroupKey } = await params
  const groupKey = decodeURIComponent(rawGroupKey)
  const upn = await getCurrentUpn()

  // Writing is dual-language. If the CYCLE is scoped to a language, that wins (no toggle). Otherwise
  // (Both) the ?lang param picks the track (default English). Ignored for Reading/Math.
  const langParam: WritingLanguage = (await searchParams).lang === 'French' ? 'French' : 'English'
  let cycleLanguage: WritingLanguage | null = null

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
      cycleLanguage = await getWindowLanguage(windowId)
      writingRoster = await getTeacherRosterWriting(upn, windowId, groupKey, cycleLanguage ?? langParam)
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
  const effectiveLanguage: WritingLanguage = cycleLanguage ?? langParam
  const isMath = assessmentType === 'Math'
  const subject = isWriting ? 'Writing' : isMath ? 'Math' : 'Reading'
  const count = isMath
    ? new Set(mathRoster.map((r) => r.studentKey)).size
    : isWriting
      ? writingRoster.length
      : roster.length

  // Friendly header from the roster rows (the URL key is opaque). Grade cohorts
  // ('GRADE:<school>:<grade>') span many homerooms → label by grade; homeroom groups show
  // 'Homeroom <name>'; section groups (grade 10+) have no homeroom, so fall back to the key.
  const firstRow = isWriting ? writingRoster[0] : isMath ? mathRoster[0] : roster[0]
  const gradeLabel = (g: string) =>
    g === 'P' ? 'Primary' : g === 'PP' ? 'Pre-Primary' : g === 'RG' ? 'Graduating' : `Grade ${g}`
  const groupDisplay = groupKey.startsWith('GRADE:')
    ? gradeLabel(firstRow?.grade ?? groupKey.split(':').pop() ?? '')
    : firstRow?.homeroom
      ? `Homeroom ${firstRow.homeroom}`
      : groupKey
  const schoolName = firstRow?.schoolName ?? null

  return (
    <>
      <div className="back-row">
        <Link href={`/enter/${windowId}`} className="back-link">
          &larr; Back to groups
        </Link>
        <span className="group-label">{groupDisplay}{schoolName ? ` · ${schoolName}` : ''} · {subject}</span>
      </div>

      {isWriting ? (
        // Dual-language writing. A "Both" cycle shows the EN/FR toggle (stays visible even when a
        // language's roster is empty, so a teacher can switch back). A language-scoped cycle fixes
        // the language and shows it as a static label. Reading/Math have no toggle.
        <div className="lang-toggle">
          <span className="lang-toggle-label">Writing in:</span>
          {cycleLanguage ? (
            <span className="seg seg-on">{cycleLanguage}</span>
          ) : (
            <span className="ipp-seg">
              <Link href={`/enter/${windowId}/${rawGroupKey}?lang=English`} className={effectiveLanguage === 'English' ? 'seg seg-on' : 'seg'}>
                English
              </Link>
              <Link href={`/enter/${windowId}/${rawGroupKey}?lang=French`} className={effectiveLanguage === 'French' ? 'seg seg-on' : 'seg'}>
                French
              </Link>
            </span>
          )}
        </div>
      ) : null}

      {error ? (
        <ErrorNote message={error} />
      ) : count === 0 ? (
        <EmptyState title="No students in this group for this cycle" />
      ) : isWriting ? (
        <WritingRosterEntry windowId={windowId} groupKey={groupKey} roster={writingRoster} language={effectiveLanguage} />
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
