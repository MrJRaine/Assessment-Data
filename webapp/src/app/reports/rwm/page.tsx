import { ToggleLink } from '@/components/ToggleLink'
import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getStudentCohortRWM, getReportCycles, getCallerAccessLevel, type RWMStudent, type ReportCycle } from '@/lib/data'
import RWMCohortView from './RWMCohortView'
import RWMRollupTree from './RWMRollupTree'
import CycleSelector from '../CycleSelector'

export const dynamic = 'force-dynamic'

// Oversight roles land on the School → Grade/Homeroom roll-up (counts per RWM score + % in all 3),
// with the flat student list as the second view — mirroring the Reading/Writing reports. Teachers
// get the flat list directly. Scope is enforced in the TVF regardless of this UI branch.
const OVERSIGHT = new Set(['Administrator', 'SpecialistTeacher', 'RegionalAnalyst'])

// Reports > RWM: a 0–3 Reading·Writing·Math achievement roll-up, Primary–5 only.
export default async function RwmReportsPage({
  searchParams,
}: {
  searchParams: Promise<{ cycle?: string; view?: string }>
}) {
  const { cycle: cycleParam, view: viewParam } = await searchParams
  const cycle = cycleParam ?? null
  const view = viewParam === 'list' ? 'list' : 'summary'
  const upn = await getCurrentUpn()

  let cohort: RWMStudent[] = []
  let cycles: ReportCycle[] = []
  let oversight = false
  let regionWide = false
  let error: string | null = null
  try {
    const accessLevel = await getCallerAccessLevel(upn)
    oversight = accessLevel != null && OVERSIGHT.has(accessLevel)
    regionWide = accessLevel === 'RegionalAnalyst'
    cohort = await getStudentCohortRWM(upn, cycle)
    cycles = await getReportCycles()
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  // Summary / Student-list switch (oversight), preserving the selected cycle.
  const viewHref = (v: 'summary' | 'list') => {
    const p = new URLSearchParams()
    if (cycle) p.set('cycle', cycle)
    if (v === 'list') p.set('view', 'list')
    const qs = p.toString()
    return qs ? `/reports/rwm?${qs}` : '/reports/rwm'
  }
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
      <PageHeader title="Reports" subtitle="RWM — how many of Reading · Writing · Math each student is currently meeting or exceeding" />
      <div className="subject-toggle">
        <ToggleLink href="/reports" className="toggle">Reading</ToggleLink>
        <ToggleLink href="/reports?subject=writing" className="toggle">Writing</ToggleLink>
        <ToggleLink href="/reports/math" className="toggle">Math</ToggleLink>
        <ToggleLink href="/reports/rwm" className="toggle-on">RWM</ToggleLink>
      </div>
      <p className="muted small" style={{ margin: '0 0 1rem' }}>
        Primary–5 only. A student&apos;s score counts Reading, Writing, and Math where their most-recent
        result is Meeting or Exceeding (Math: rolled-up ≥ 75%). Students with a confirmed IPP in any of
        the three are excluded.
      </p>
      {cycles.length > 0 ? <CycleSelector cycles={cycles} /> : null}
      {error ? (
        <ErrorNote message={error} />
      ) : cohort.length === 0 ? (
        <EmptyState
          title="No students in your scope"
          hint="Primary–5 students (without a confirmed IPP in Reading, Writing, or Math) appear here."
        />
      ) : oversight && view === 'summary' ? (
        // Remount on cycle change so no expanded node from the previous cycle lingers.
        <RWMRollupTree key={cycle ?? 'current'} cohort={cohort} showAll={regionWide} viewToggle={viewToggle} />
      ) : (
        <RWMCohortView key={`${cycle ?? 'current'}:list`} cohort={cohort} viewToggle={oversight ? viewToggle : undefined} />
      )}
    </>
  )
}
