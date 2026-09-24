import { PageHeader, CardLink, EmptyState, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getTeacherWindows, type TeacherWindow } from '@/lib/data'

export const dynamic = 'force-dynamic'

/**
 * ONE card per (cycle x subject) — you pick the CYCLE, not an instance.
 *
 * A Short Cycle of Response is a header plus N scoped instances (subject x language x program
 * scope x grade band), so "SCoR 1" can be 8 DimAssessmentWindow rows. Showing one card each made
 * /enter a wall of near-identical "SCoR 1" tiles. These collapse to "SCoR 1" under Reading,
 * Writing and Math, and the link carries the CYCLE key + subject; which instance a given student
 * belongs to is resolved downstream from their course language, program and grade.
 */
type CycleCard = {
  key: string
  cycleGroupId: string
  subject: string
  title: string
  status: string
  applicableCount: number
  enteredCount: number
  doneCount: number // Math only: students who've completed >80% of their benchmark-month tasks
}

// Most-open status wins across the cycle's instances: a cycle with any open instance is open.
const STATUS_RANK: Record<string, number> = { Open: 0, ClosesToday: 1, Upcoming: 2, Closed: 3 }

function collapseToCycles(windows: TeacherWindow[]): { cards: CycleCard[]; orphans: number } {
  const out: CycleCard[] = []
  const byCycle = new Map<string, CycleCard>()
  let orphans = 0

  for (const w of windows) {
    // An instance with no cycle header can't be entered: the whole flow is keyed on the header, so
    // there is nowhere for a card to point. Count it and say so rather than render a dead card —
    // it means a window exists outside the Cycles page and an admin needs to attach it.
    if (!w.cycleGroupId) {
      orphans++
      continue
    }

    const key = `${w.cycleGroupId}|${w.assessmentType}`
    const existing = byCycle.get(key)
    if (!existing) {
      const card: CycleCard = {
        key,
        cycleGroupId: w.cycleGroupId,
        subject: w.assessmentType,
        title: w.cycleName ?? w.name,
        status: w.status,
        applicableCount: w.applicableCount,
        enteredCount: w.enteredCount,
        doneCount: w.doneCount,
      }
      byCycle.set(key, card)
      out.push(card)
      continue
    }
    // Counts are per-instance totals, so they SUM: a dual-language student with both an English and
    // a French writing result owes two entries, and the ratio tracks entries, not heads.
    existing.applicableCount += w.applicableCount
    existing.enteredCount += w.enteredCount
    existing.doneCount += w.doneCount
    if ((STATUS_RANK[w.status] ?? 9) < (STATUS_RANK[existing.status] ?? 9)) existing.status = w.status
  }

  return { cards: out, orphans }
}

function CycleCardLink({ c }: { c: CycleCard }) {
  return (
    <CardLink
      href={`/enter/cycle/${encodeURIComponent(c.cycleGroupId)}/${encodeURIComponent(c.subject)}`}
      title={c.title}
      meta={c.subject === 'Math'
        ? `${c.status} · ${c.enteredCount}/${c.applicableCount} started · ${c.doneCount} done`
        : `${c.status} · ${c.enteredCount}/${c.applicableCount} done`}
    />
  )
}

// One subject section: open cycles above the fold + a collapsed accordion of past ones
// (still selectable, since late entry is allowed).
function SubjectSection({ title, cycles }: { title: string; cycles: CycleCard[] }) {
  const current = cycles.filter((c) => c.status === 'Open' || c.status === 'ClosesToday')
  const past = cycles.filter((c) => c.status === 'Closed')
  const lower = title.toLowerCase()

  return (
    <section className="window-section">
      <h2 className="section-heading">{title}</h2>
      {current.length > 0 ? (
        <div className="card-grid">
          {current.map((c) => (
            <CycleCardLink key={c.key} c={c} />
          ))}
        </div>
      ) : (
        <p className="muted">No open {lower} cycle right now.</p>
      )}

      {past.length > 0 ? (
        <details className="accordion">
          <summary>
            Past {lower} cycles ({past.length}) — still open for late entry
          </summary>
          <div className="card-grid">
            {past.map((c) => (
              <CycleCardLink key={c.key} c={c} />
            ))}
          </div>
        </details>
      ) : null}
    </section>
  )
}

export default async function WindowSelect() {
  const upn = await getCurrentUpn()
  let windows: TeacherWindow[] = []
  let error: string | null = null
  try {
    windows = await getTeacherWindows(upn)
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  const { cards: cycles, orphans } = collapseToCycles(windows)
  const reading = cycles.filter((c) => c.subject === 'Reading')
  const writing = cycles.filter((c) => c.subject === 'Writing')
  const math = cycles.filter((c) => c.subject === 'Math')
  const other = cycles.filter((c) => !['Reading', 'Writing', 'Math'].includes(c.subject))

  return (
    <>
      <PageHeader title="Data Entry" subtitle="Step 1 — choose a cycle" />
      {error ? (
        <ErrorNote message={error} />
      ) : cycles.length === 0 && orphans === 0 ? (
        <EmptyState
          title="No cycles for you right now"
          hint="Cycles appear here once you have a roster in an active Short Cycle of Response."
        />
      ) : (
        <>
          {reading.length > 0 ? <SubjectSection title="Reading" cycles={reading} /> : null}
          {writing.length > 0 ? <SubjectSection title="Writing" cycles={writing} /> : null}
          {math.length > 0 ? <SubjectSection title="Math" cycles={math} /> : null}
          {other.length > 0 ? <SubjectSection title="Other" cycles={other} /> : null}
          {orphans > 0 ? (
            <p className="muted">
              {orphans} assessment window{orphans === 1 ? ' is' : 's are'} not attached to a Short Cycle and can&apos;t be
              opened here. An administrator can attach {orphans === 1 ? 'it' : 'them'} on the Cycles page.
            </p>
          ) : null}
        </>
      )}
    </>
  )
}
