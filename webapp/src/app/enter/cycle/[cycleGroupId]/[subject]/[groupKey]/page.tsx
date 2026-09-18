import Link from 'next/link'
import { EmptyState, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import {
  getTeacherGroups,
  getShortCycles,
  getTeacherRoster,
  getTeacherRosterWriting,
  getMathRoster,
  getScaleLevels,
  getAchievementLevels,
  type TeacherGroup,
  type ShortCycleInstance,
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

// One instance's slice of this class, with everything its grid needs.
type Slice = {
  windowId: string
  label: string // only shown when the class straddles more than one instance
  roster: RosterStudent[]
  writingRoster: WritingRosterStudent[]
  mathRoster: MathRosterRow[]
  levels: ScaleLevel[]
  achievementLevels: AchievementBand[]
  count: number
}

const gradeLabel = (g: string) =>
  g === 'P' ? 'Primary' : g === 'PP' ? 'Pre-Primary' : g === 'RG' ? 'Graduating' : `Gr ${g}`

// What makes this instance different from the others the class falls under: its program scope and
// grade band. (Language is not in here — the course pins it, so every slice shares one.)
function instanceLabel(i: ShortCycleInstance): string {
  const band = i.minGrade === i.maxGrade ? gradeLabel(i.minGrade) : `${gradeLabel(i.minGrade)}–${gradeLabel(i.maxGrade)}`
  const scope = i.programScope.length ? i.programScope.join(', ') : 'All programs'
  return `${scope} · ${band}`
}

export default async function RosterGrid({
  params,
}: {
  params: Promise<{ cycleGroupId: string; subject: string; groupKey: string }>
}) {
  const { cycleGroupId: rawCycle, subject: rawSubject, groupKey: rawGroupKey } = await params
  const cycleGroupId = decodeURIComponent(rawCycle)
  const subject = decodeURIComponent(rawSubject)
  // One segment can carry SEVERAL comma-joined keys — the picker's "enter several at once" mode.
  const groupKeys = decodeURIComponent(rawGroupKey).split(',').map((k) => k.trim()).filter(Boolean)
  const upn = await getCurrentUpn()

  const isWriting = subject === 'Writing'
  const isMath = subject === 'Math'

  let picked: TeacherGroup[] = []
  let group: TeacherGroup | null = null
  const slices: Slice[] = []
  let error: string | null = null

  try {
    // Re-resolving the caller's groups does three jobs: it AUTHORIZES the group (a key the caller
    // can't see resolves to nothing), supplies the display label, and names which cycle INSTANCE(S)
    // this class's students sit under — there is no windowId in the URL, because you pick a cycle.
    const groups = await getTeacherGroups(upn, cycleGroupId, subject)
    // Every requested key must be one the caller can actually see; anything else is silently
    // dropped, so a hand-typed key grants nothing.
    picked = groupKeys.map((k) => groups.find((g) => g.key === k)).filter((g): g is TeacherGroup => !!g)
    group = picked[0] ?? null
    // A combined roster spans the union of its classes' instances.
    const windowIds = [...new Set(picked.flatMap((g) => g.windowIds ?? []))]

    // Usually one instance. A class straddles two when the cycle splits the same language by program
    // scope or grade band, and then each instance gets its own grid and its own Save — the same
    // shape the math grid uses for a split-grade class. Never pick one and drop the other's students.
    let instances: ShortCycleInstance[] = []
    if (windowIds.length > 1) {
      const cycle = (await getShortCycles()).find((c) => c.cycleGroupId === cycleGroupId)
      instances = (cycle?.instances ?? []).filter((i) => windowIds.includes(i.id))
    }
    const labelFor = (id: string) => {
      const i = instances.find((x) => x.id === id)
      return i ? instanceLabel(i) : ''
    }

    // The LANGUAGE comes from the course (an FLA section is French, an ELA section English), so the
    // old EN/FR toggle is gone — there is nothing for the teacher to set wrong.
    const language: WritingLanguage = group?.language === 'French' ? 'French' : 'English'

    for (const windowId of windowIds) {
      const slice: Slice = {
        windowId,
        label: labelFor(windowId),
        roster: [],
        writingRoster: [],
        mathRoster: [],
        levels: [],
        achievementLevels: [],
        count: 0,
      }
      if (isWriting) {
        slice.writingRoster = await getTeacherRosterWriting(upn, windowId, groupKeys, language)
        slice.count = slice.writingRoster.length
      } else if (isMath) {
        slice.mathRoster = await getMathRoster(upn, windowId, groupKeys)
        slice.count = new Set(slice.mathRoster.map((r) => r.studentKey)).size
      } else {
        slice.roster = await getTeacherRoster(upn, windowId, groupKeys)
        const scaleSystem = slice.roster[0]?.scaleSystem ?? null
        if (scaleSystem) slice.levels = await getScaleLevels(scaleSystem)
        slice.achievementLevels = await getAchievementLevels()
        slice.count = slice.roster.length
      }
      // An instance this class matched in aggregate can still hold none of ITS students once the
      // roster is resolved; an empty grid with a Save button would just be a trap.
      if (slice.count > 0) slices.push(slice)
    }
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  const language: WritingLanguage = group?.language === 'French' ? 'French' : 'English'
  const split = slices.length > 1
  const schoolName = group?.schoolName ?? null

  return (
    <>
      <div className="back-row">
        <Link href={`/enter/cycle/${rawCycle}/${rawSubject}`} className="back-link">
          &larr; Back to groups
        </Link>
        <span className="group-label">
          {/* A combined roster names every class it covers, so the teacher can see at a glance
              which ones they're marking -- the school is dropped, since it would repeat. */}
          {picked.length > 1
            ? picked.map((g) => g.label).join(' + ')
            : `${group?.label ?? groupKeys.join(', ')}${schoolName ? ` · ${schoolName}` : ''}`}
          {' · '}
          {subject}
          {isWriting ? ` · ${language}` : ''}
        </span>
      </div>

      {error ? (
        <ErrorNote message={error} />
      ) : !group ? (
        <EmptyState
          title="This class isn't in this cycle"
          hint="It may have no students in the cycle's grade or program scope, or you may no longer teach it."
        />
      ) : slices.length === 0 ? (
        <EmptyState title="No students in this group for this cycle" />
      ) : (
        slices.map((s) => (
          <section key={s.windowId} className={split ? 'window-section' : undefined}>
            {/* Only worth a heading when there's more than one — otherwise it's noise on every roster. */}
            {split && (
              <h2 className="section-heading">
                {s.label} <span className="muted">· {s.count} student{s.count === 1 ? '' : 's'}</span>
              </h2>
            )}
            {isWriting ? (
              <WritingRosterEntry windowId={s.windowId} groupKey={groupKeys.join(",")} roster={s.writingRoster} language={language} />
            ) : isMath ? (
              <MathRosterEntry windowId={s.windowId} groupKey={groupKeys.join(",")} rows={s.mathRoster} />
            ) : (
              <RosterEntry
                windowId={s.windowId}
                groupKey={groupKeys.join(",")}
                roster={s.roster}
                levels={s.levels}
                achievementLevels={s.achievementLevels}
              />
            )}
          </section>
        ))
      )}
    </>
  )
}
