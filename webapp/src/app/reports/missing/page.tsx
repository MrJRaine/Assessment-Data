import { notFound } from 'next/navigation'
import { ToggleLink } from '@/components/ToggleLink'
import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import {
  getMissingDataAll, getReportCycles, getCallerAccessLevel,
  type MissingDataRow, type ReportCycle,
} from '@/lib/data'
import CycleSelector from '../CycleSelector'
import MissingRollupTree from './MissingRollupTree'

export const dynamic = 'force-dynamic'

// Reports > Missing results: Administrator / RegionalAnalyst ONLY (user decision 2026-11-12 —
// Specialist Teachers excluded too). Everyone else 404s here, the tab is hidden for them on the
// other report pages, and tvf_MissingDataAll has no non-Admin/RA branch — three layers deep.
const ALLOWED = new Set(['Administrator', 'RegionalAnalyst'])

export default async function MissingResultsPage({
  searchParams,
}: {
  searchParams: Promise<{ cycle?: string }>
}) {
  const { cycle: cycleParam } = await searchParams
  const upn = await getCurrentUpn()

  let accessLevel: string | null = null
  let error: string | null = null
  try {
    accessLevel = await getCallerAccessLevel(upn)
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }
  // Outside the try: notFound() throws a control-flow error a catch must not swallow.
  if (!error && !ALLOWED.has(accessLevel ?? '')) notFound()

  let rows: MissingDataRow[] = []
  let cycles: ReportCycle[] = []
  let cycle: string | null = null
  if (!error) {
    try {
      cycles = await getReportCycles()
      // This report is inherently per-cycle (no most-recent-result mode), so the selector shows
      // cycles only — no "Current" chip — and no ?cycle param = the newest cycle that has started
      // (what the entry screens are on), which the selector then shows as selected.
      cycle = cycleParam ?? cycles[cycles.length - 1]?.cycleGroupId ?? null
      if (cycle) rows = await getMissingDataAll(upn, cycle)
    } catch (e) {
      error = e instanceof Error ? e.message : String(e)
    }
  }

  return (
    <>
      <PageHeader
        title="Reports"
        subtitle="Missing results — who still needs data entered for the selected cycle"
      />
      <div className="subject-toggle">
        <ToggleLink href="/reports" className="toggle">Reading</ToggleLink>
        <ToggleLink href="/reports?subject=writing" className="toggle">Writing</ToggleLink>
        <ToggleLink href="/reports/math" className="toggle">Math</ToggleLink>
        <ToggleLink href="/reports/rwm" className="toggle">RWM</ToggleLink>
        <ToggleLink href="/reports/missing" className="toggle-on">Missing results</ToggleLink>
      </div>
      <p className="muted small" style={{ margin: '0 0 1rem' }}>
        Counts are students without a result for this cycle, by school, lead teacher, and section
        (students with a confirmed IPP in a subject are not expected in it). Math counts as reported
        once 80% of the cycle&apos;s tasks are filled in. Open a section to see who still needs data entered.
      </p>
      {cycles.length > 0 ? <CycleSelector cycles={cycles} cyclesOnly /> : null}
      {error ? (
        <ErrorNote message={error} />
      ) : cycle == null ? (
        <EmptyState title="No cycles yet" hint="Missing results appear once a cycle has started." />
      ) : rows.length === 0 ? (
        <EmptyState
          title="Nothing expected for this cycle"
          hint="No section rosters map to this cycle's windows in your schools."
        />
      ) : (
        // Remount on cycle change so no expanded node from the previous cycle lingers.
        <MissingRollupTree key={cycle} rows={rows} cycle={cycle} showAll={accessLevel === 'RegionalAnalyst'} />
      )}
    </>
  )
}
