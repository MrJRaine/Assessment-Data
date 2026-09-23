import { Suspense } from 'react'
import Link from 'next/link'
import { EmptyState, ErrorNote, Loading } from '@/components/ui'
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

function BackLink({ rawCycle, rawSubject }: { rawCycle: string; rawSubject: string }) {
  return (
    <Link href={`/enter/cycle/${rawCycle}/${rawSubject}`} className="back-link">
      &larr; Back to groups
    </Link>
  )
}

// Shown INSTANTLY on navigation while the roster's warehouse queries run. Keeps the Back link in place
// (so a teacher can bail mid-load) and gives the click immediate feedback.
function RosterLoading({ rawCycle, rawSubject }: { rawCycle: string; rawSubject: string }) {
  return (
    <>
      <div className="back-row">
        <BackLink rawCycle={rawCycle} rawSubject={rawSubject} />
      </div>
      <Loading label="Loading roster…" />
    </>
  )
}

// The page renders its shell (the Back link) and a Suspense boundary IMMEDIATELY, then STREAMS the
// roster in when its queries resolve. These cards are force-dynamic and not prefetched, so loading.tsx
// doesn't fire on click; an in-page Suspense boundary means the server flushes the shell + the
// "Loading roster…" fallback right away (fast first byte) instead of holding the whole response until
// every roster query finishes — so the click never looks dead, and the roster fills in a beat later.
export default async function RosterGrid({
  params,
  searchParams,
}: {
  params: Promise<{ cycleGroupId: string; subject: string; groupKey: string }>
  searchParams: Promise<{ [k: string]: string | string[] | undefined }>
}) {
  const { cycleGroupId: rawCycle, subject: rawSubject, groupKey: rawGroupKey } = await params
  // Metadata the picker card carried forward (see GroupCards.cardHref) so the roster can skip the
  // getTeacherGroups re-resolve. Absent on direct links / combined rosters -> the page falls back.
  const sp = await searchParams
  const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null
  const card = {
    windowIds: (first(sp.w) ?? '').split(',').map((s) => s.trim()).filter(Boolean),
    label: first(sp.label),
    language: first(sp.lang),
    schoolName: first(sp.school),
  }
  return (
    <Suspense fallback={<RosterLoading rawCycle={rawCycle} rawSubject={rawSubject} />}>
      <RosterBody rawCycle={rawCycle} rawSubject={rawSubject} rawGroupKey={rawGroupKey} card={card} />
    </Suspense>
  )
}

async function RosterBody({
  rawCycle,
  rawSubject,
  rawGroupKey,
  card,
}: {
  rawCycle: string
  rawSubject: string
  rawGroupKey: string
  card: { windowIds: string[]; label: string | null; language: string | null; schoolName: string | null }
}) {
  const cycleGroupId = decodeURIComponent(rawCycle)
  const subject = decodeURIComponent(rawSubject)
  // One segment can carry SEVERAL comma-joined keys — the picker's "enter several at once" mode.
  const groupKeys = decodeURIComponent(rawGroupKey).split(',').map((k) => k.trim()).filter(Boolean)
  const upn = await getCurrentUpn()

  const isWriting = subject === 'Writing'
  const isMath = subject === 'Math'

  let picked: TeacherGroup[] = []
  let unresolvedKeys: string[] = []
  const emptyInstances: string[] = []
  let group: TeacherGroup | null = null
  const slices: Slice[] = []
  let error: string | null = null

  try {
    let windowIds: string[]
    // FAST PATH: a single card click carries the group's windows + label + language + school on the
    // URL (see GroupCards.cardHref), so we skip the ~1s getTeacherGroups re-resolve. Authorization is
    // unaffected — the roster TVF re-checks access by section, so a spoofed/stale param returns no
    // students, never someone else's. Falls back below for direct links and combined rosters.
    if (groupKeys.length === 1 && card.windowIds.length > 0) {
      const g = {
        key: groupKeys[0],
        label: card.label ?? groupKeys[0],
        language: card.language,
        schoolName: card.schoolName,
        windowIds: card.windowIds,
      } as TeacherGroup
      picked = [g]
      group = g
      windowIds = card.windowIds
    } else {
      // Re-resolving the caller's groups does three jobs: it AUTHORIZES the group (a key the caller
      // can't see resolves to nothing), supplies the display label, and names which cycle INSTANCE(S)
      // this class's students sit under — there is no windowId in the URL, because you pick a cycle.
      const groups = await getTeacherGroups(upn, cycleGroupId, subject)
      // Every requested key must be one the caller can actually see, so a hand-typed key grants
      // nothing. But don't drop the rest in silence — if a teacher opened three classes and one
      // resolved to nothing, they must be told, not left counting heads.
      picked = groupKeys.map((k) => groups.find((g) => g.key === k)).filter((g): g is TeacherGroup => !!g)
      unresolvedKeys = groupKeys.filter((k) => !groups.some((g) => g.key === k))
      group = picked[0] ?? null
      // A combined roster spans the union of its classes' instances.
      windowIds = [...new Set(picked.flatMap((g) => g.windowIds ?? []))]
    }

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
      // roster is resolved. An empty grid with a live Save button is a trap, so don't render one --
      // but don't drop it in silence either: record it and say so underneath.
      if (slice.count > 0) slices.push(slice)
      else if (slice.label) emptyInstances.push(slice.label)
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
        <BackLink rawCycle={rawCycle} rawSubject={rawSubject} />
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

      {/* Anything this page could NOT show gets said out loud, above the grids. A teacher who picked
          three classes and gets two must be told which one is missing and why — never left to count
          heads and wonder. */}
      {!error && unresolvedKeys.length > 0 && (
        <div className="no-tasks">
          <strong>
            {unresolvedKeys.length === 1 ? 'One class you opened' : `${unresolvedKeys.length} classes you opened`} could
            not be shown.
          </strong>
          <p>
            {unresolvedKeys.length === 1 ? 'It is' : 'They are'} not among the classes you can enter for this cycle —
            usually because you no longer teach {unresolvedKeys.length === 1 ? 'it' : 'them'}, or the course isn&apos;t
            assessed in this cycle. Anything below is complete for the classes that did open.
          </p>
        </div>
      )}
      {!error && emptyInstances.length > 0 && (
        <div className="no-tasks">
          <strong>Part of this cycle has no students in this class.</strong>
          <p>
            Nobody here falls under {emptyInstances.join(' or ')}, so {emptyInstances.length === 1 ? 'that' : 'those'}{' '}
            {emptyInstances.length === 1 ? 'section is' : 'sections are'} not shown. Everyone who can be entered is below.
          </p>
        </div>
      )}

      {error ? (
        <ErrorNote message={error} />
      ) : !group ? (
        <EmptyState
          title="This class isn't in this cycle"
          hint="It may have no students in the cycle's grade or program scope, or you may no longer teach it."
        />
      ) : slices.length === 0 ? (
        // Never a bare "no results" — say why THIS user sees nothing, in their terms.
        <EmptyState
          title={`No students to enter for ${group.label}`}
          hint={`Everyone in this class falls outside what this cycle covers — its grade range, its programs, or ${
            isWriting ? 'its language' : 'the language of this course'
          }. Check the cycle's scope on the Cycles page, or pick a different class.`}
        />
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
