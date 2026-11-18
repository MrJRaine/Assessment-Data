import { ToggleLink } from '@/components/ToggleLink'
import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import {
  getStudentCohort,
  getStudentCohortWriting,
  getAchievementLevels,
  getAssessableGradeRange,
  getReportCycles,
  getCallerAccessLevel,
  getReadingCohortAll,
  getWritingCohortAll,
  type CohortStudent,
  type AchievementBand,
  type ReportCycle,
  type ReadingRollupRow,
  type WritingRollupRow,
} from '@/lib/data'
import CohortView from './CohortView'
import ReadingRollupTree from './ReadingRollupTree'
import WritingRollupTree from './WritingRollupTree'
import CycleSelector from './CycleSelector'

export const dynamic = 'force-dynamic'

// Oversight roles (Administrator / SpecialistTeacher / RegionalAnalyst) LAND on the School → Grade/Homeroom
// roll-up tree, with the flat per-student cohort list available as a second view (?view=list) — both carry
// the two charts at the top. Teachers get the flat cohort list directly. Scope is enforced in the TVFs
// regardless of this UI branch.
const OVERSIGHT = new Set(['Administrator', 'SpecialistTeacher', 'RegionalAnalyst'])

export default async function StudentsPage({
  searchParams,
}: {
  searchParams: Promise<{ subject?: string; cycle?: string; view?: string }>
}) {
  const { subject, cycle: cycleParam, view: viewParam } = await searchParams
  const isWriting = subject === 'writing'
  const upn = await getCurrentUpn()
  const cycle = cycleParam ?? null // cycle-binding applies to Reading AND Writing (cycles are shared)
  const view = viewParam === 'list' ? 'list' : 'summary' // oversight: roll-up (default) vs flat student list

  let cohort: CohortStudent[] = []
  let trendCohort: CohortStudent[] | undefined // all-cycles cohort for the by-cycle trend (teachers)
  let rollup: ReadingRollupRow[] = []
  let rollupAll: ReadingRollupRow[] = [] // all-cycles (for the trend); == rollup when no cycle selected
  let writingRollup: WritingRollupRow[] = []
  let writingRollupAll: WritingRollupRow[] = []
  let bands: AchievementBand[] = []
  let assessableRange: { minOrder: number; maxOrder: number } | null = null
  let cycles: ReportCycle[] = []
  let oversight = false
  let regionWide = false // RegionalAnalyst = sees all schools → gets the TCRCE all-schools roll-up row
  let adminRA = false // Administrator/RegionalAnalyst only → Missing results tab (NOT SpecialistTeacher)
  let error: string | null = null
  try {
    const accessLevel = await getCallerAccessLevel(upn)
    oversight = accessLevel != null && OVERSIGHT.has(accessLevel)
    regionWide = accessLevel === 'RegionalAnalyst'
    adminRA = accessLevel === 'Administrator' || regionWide
    cycles = await getReportCycles()
    bands = await getAchievementLevels()
    if (oversight) {
      if (view === 'list') {
        // Student-list view: the charts are CohortView's own, fed from the FILTERED rows (2026-10-30 fix —
        // the page-top roll-up-fed charts ignored the list's filter chips, so the donut/trend sat frozen
        // while the table filtered). The roll-up feed isn't rendered here, so don't fetch it.
        cohort = isWriting ? await getStudentCohortWriting(upn, cycle) : await getStudentCohort(upn, cycle)
        assessableRange = await getAssessableGradeRange(isWriting ? 'Writing' : 'Reading', cycle)
        // By-cycle trend is cycle-independent: all-cycles copy (reuse `cohort` when no cycle is selected).
        trendCohort = cycle == null
          ? undefined
          : isWriting ? await getStudentCohortWriting(upn, null) : await getStudentCohort(upn, null)
      } else {
        // Summary view — roll-up feed: cycle-scoped (donut + tree). The trend is cycle-INDEPENDENT, so pull
        // an all-cycles copy too — but only when a cycle is actually selected; otherwise identical (one read).
        if (!isWriting) {
          rollup = await getReadingCohortAll(upn, cycle)
          rollupAll = cycle == null ? rollup : await getReadingCohortAll(upn, null)
        } else {
          writingRollup = await getWritingCohortAll(upn, cycle)
          writingRollupAll = cycle == null ? writingRollup : await getWritingCohortAll(upn, null)
        }
      }
    } else {
      cohort = isWriting ? await getStudentCohortWriting(upn, cycle) : await getStudentCohort(upn, cycle)
      assessableRange = await getAssessableGradeRange(isWriting ? 'Writing' : 'Reading', cycle)
      // By-cycle trend is cycle-independent: all-cycles copy (reuse `cohort` when no cycle is selected).
      trendCohort = cycle == null
        ? undefined
        : isWriting ? await getStudentCohortWriting(upn, null) : await getStudentCohort(upn, null)
    }
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  // View-switch hrefs, preserving subject + cycle.
  const viewHref = (v: 'summary' | 'list') => {
    const p = new URLSearchParams()
    if (isWriting) p.set('subject', 'writing')
    if (cycle) p.set('cycle', cycle)
    if (v === 'list') p.set('view', 'list')
    const qs = p.toString()
    return qs ? `/reports?${qs}` : '/reports'
  }

  // Dynamic, printable page title — reflects the current subject + selected cycle.
  const subjectLabel = isWriting ? 'Writing' : 'Reading'
  const cycleName = cycle ? cycles.find((c) => c.cycleGroupId === cycle)?.name ?? null : null
  const reportTitle = `${subjectLabel} Report${cycleName ? ` — ${cycleName}` : ''}`

  // Summary / Student-list switch (oversight). Rendered inline in the roll-up toolbar on Summary, and
  // standalone above the cohort table on the Student-list view.
  const viewToggle = (
    <div className="subject-toggle" role="tablist" aria-label="Report view" style={{ margin: 0 }}>
      <ToggleLink href={viewHref('summary')} className={view === 'summary' ? 'toggle-on' : 'toggle'}>
        Summary
      </ToggleLink>
      <ToggleLink href={viewHref('list')} className={view === 'list' ? 'toggle-on' : 'toggle'}>
        Student list
      </ToggleLink>
    </div>
  )

  return (
    <>
      <PageHeader title={reportTitle} />
      <div className="report-top-row">
        <div className="subject-toggle" style={{ margin: 0 }}>
          <ToggleLink href="/reports" className={!isWriting ? 'toggle-on' : 'toggle'}>
            Reading
          </ToggleLink>
          <ToggleLink href="/reports?subject=writing" className={isWriting ? 'toggle-on' : 'toggle'}>
            Writing
          </ToggleLink>
          <ToggleLink href="/reports/math" className="toggle">
            Math
          </ToggleLink>
          <ToggleLink href="/reports/rwm" className="toggle">
            RWM
          </ToggleLink>
          {adminRA ? (
            <ToggleLink href="/reports/missing" className="toggle">
              Missing results
            </ToggleLink>
          ) : null}
        </div>
        {cycles.length > 0 ? <CycleSelector cycles={cycles} /> : null}
      </div>
      {error ? (
        <ErrorNote message={error} />
      ) : oversight ? (
        <>
          {view === 'list' ? (
            <>
              {cohort.length === 0 ? (
                <>
                  {/* No CohortView to carry the switch here, so render it standalone — otherwise an
                      empty list would strand the viewer with no way back to Summary. */}
                  <div style={{ margin: '0 0 0.75rem' }}>{viewToggle}</div>
                  <EmptyState
                    title="No students in your scope"
                    hint={`${isWriting ? 'Writing' : 'Reading'} results and demographics appear here for students you can see.`}
                  />
                </>
              ) : (
                // CohortView renders its OWN charts here, fed from the FILTERED rows — the donut and trend
                // follow the filter chips (2026-10-30 fix; the page-top roll-up-fed copy ignored them). The
                // Summary/Student-list switch rides its control bar, so the page order is charts →
                // controls → table on both views (2026-11-10).
                <CohortView
                  key={`${isWriting ? 'writing' : 'reading'}:${cycle ?? 'current'}:list`}
                  cohort={cohort}
                  bands={bands}
                  cycles={cycles}
                  subject={isWriting ? 'Writing' : 'Reading'}
                  assessableRange={assessableRange}
                  trendCohort={trendCohort}
                  viewToggle={viewToggle}
                />
              )}
            </>
          ) : isWriting ? (
            // Summary view: the tree renders the two page-top charts itself, so they follow its
            // Language of Assessment toggle and demographic filters (donut = the filtered cycle-scoped
            // feed; trend = the all-cycles copy through the same filters, right edge = selected cycle).
            <WritingRollupTree key={`writing:${cycle ?? 'current'}`} rows={writingRollup} trendRows={writingRollupAll} bands={bands} cycles={cycles} cycle={cycle} showAll={regionWide} viewToggle={viewToggle} />
          ) : (
            <ReadingRollupTree key={`reading:${cycle ?? 'current'}`} rows={rollup} trendRows={rollupAll} bands={bands} cycles={cycles} cycle={cycle} showAll={regionWide} viewToggle={viewToggle} />
          )}
        </>
      ) : cohort.length === 0 ? (
        <EmptyState
          title="No students in your scope"
          hint={`${isWriting ? 'Writing' : 'Reading'} results and demographics appear here for students you can see.`}
        />
      ) : (
        // key on subject+cycle: the Reading/Writing toggle AND the cycle selector are SAME-ROUTE soft
        // navigations, so React reconciles this client component in place — which left stale rows from the
        // previous render mounted until a hard refresh. Keying forces a full remount on either change.
        // Filters/sort restore from sessionStorage, so the user's selections survive the remount.
        <CohortView
          key={`${isWriting ? 'writing' : 'reading'}:${cycle ?? 'current'}`}
          cohort={cohort}
          bands={bands}
          cycles={cycles}
          subject={isWriting ? 'Writing' : 'Reading'}
          assessableRange={assessableRange}
          trendCohort={trendCohort}
        />
      )}
    </>
  )
}
