import { ToggleLink } from '@/components/ToggleLink'
import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import {
  getMathCohortAll, getCallerAccessLevel, getReportCycles,
  type MathRollupRow, type ReportCycle,
} from '@/lib/data'
import CycleSelector from '../CycleSelector'
import MathRollupTree from './MathRollupTree'

export const dynamic = 'force-dynamic'

// Reports > Math landing. Math is P-5.
//   EVERYONE (teachers + oversight) gets the SAME roll-up tree — School → [Grade | Homeroom] toggle →
//   per-grade block. Teachers see their OWN students (tvf_StudentCohortMathAll's Taught scope); oversight
//   roles see the schools they cover; a RegionalAnalyst also gets the all-schools (TCRCE) row. This
//   replaced the teacher card picker (grade/homeroom cards), a holdover from before math had a consistent
//   scale across windows/grades — a grade isn't a class, so it didn't belong in "My classes".
export default async function MathReportsPage({ searchParams }: { searchParams: Promise<{ cycle?: string }> }) {
  const upn = await getCurrentUpn()
  const { cycle: cycleParam } = await searchParams
  const cycle = cycleParam ?? null

  let error: string | null = null
  let accessLevel: string | null = null
  let rows: MathRollupRow[] = []
  let cycles: ReportCycle[] = []
  try {
    accessLevel = await getCallerAccessLevel(upn)
    ;[rows, cycles] = await Promise.all([getMathCohortAll(upn, cycle), getReportCycles()])
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  const toggle = (
    <div className="subject-toggle">
      <ToggleLink href="/reports" className="toggle">Reading</ToggleLink>
      <ToggleLink href="/reports?subject=writing" className="toggle">Writing</ToggleLink>
      <ToggleLink href="/reports/math" className="toggle-on">Math</ToggleLink>
      <ToggleLink href="/reports/rwm" className="toggle">RWM</ToggleLink>
    </div>
  )

  return (
    <>
      <PageHeader title="Reports" subtitle="Math — the Primary–5 results matrix" />
      {toggle}
      <p className="muted small" style={{ margin: '0 0 1rem' }}>
        Math results cover grades Primary–5 only. Open a school, then a grade or homeroom, to see its students.
      </p>
      {cycles.length > 0 ? <CycleSelector cycles={cycles} /> : null}
      {error ? (
        <ErrorNote message={error} />
      ) : rows.length === 0 ? (
        <EmptyState
          title="No students in your scope"
          hint="Math results appear here for the Primary–5 students you teach or oversee."
        />
      ) : (
        // Remount on cycle change so no expanded block from the previous cycle lingers.
        <MathRollupTree key={cycle ?? 'current'} rows={rows} cycle={cycle} showAll={accessLevel === 'RegionalAnalyst'} />
      )}
    </>
  )
}
