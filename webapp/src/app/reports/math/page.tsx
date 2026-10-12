import Link from 'next/link'
import { redirect } from 'next/navigation'
import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import {
  getMathCohortGroups, getMathCohortAll, getCallerAccessLevel, getReportCycles,
  type TeacherGroup, type MathRollupRow, type ReportCycle,
} from '@/lib/data'
import GroupCards from '@/components/GroupCards'
import CycleSelector from '../CycleSelector'
import MathRollupTree from './MathRollupTree'

export const dynamic = 'force-dynamic'

// Oversight roles get the roll-up tree (math-reports #2) instead of the card picker.
const OVERSIGHT = new Set(['Administrator', 'SpecialistTeacher', 'RegionalAnalyst'])

// Reports > Math landing. Math is P-5.
//  - Teachers: pick a homeroom or grade card → that group's read-only results matrix.
//  - Administrator / SpecialistTeacher / RegionalAnalyst: a collapsed roll-up tree over their whole
//    scope (School → Grade|Homeroom → per-grade block), cycle-selectable.
export default async function MathReportsPage({ searchParams }: { searchParams: Promise<{ cycle?: string }> }) {
  const upn = await getCurrentUpn()
  const { cycle: cycleParam } = await searchParams
  const cycle = cycleParam ?? null

  let error: string | null = null
  let accessLevel: string | null = null
  try {
    accessLevel = await getCallerAccessLevel(upn)
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }
  const oversight = accessLevel != null && OVERSIGHT.has(accessLevel)

  const toggle = (
    <div className="subject-toggle">
      <Link href="/reports" className="toggle">Reading</Link>
      <Link href="/reports?subject=writing" className="toggle">Writing</Link>
      <Link href="/reports/math" className="toggle-on">Math</Link>
      <Link href="/reports/rwm" className="toggle">RWM</Link>
    </div>
  )

  if (oversight && !error) {
    let rows: MathRollupRow[] = []
    let cycles: ReportCycle[] = []
    try {
      ;[rows, cycles] = await Promise.all([getMathCohortAll(upn, cycle), getReportCycles()])
    } catch (e) {
      error = e instanceof Error ? e.message : String(e)
    }
    return (
      <>
        <PageHeader title="Reports" subtitle="Math — results across the schools you oversee" />
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
            hint="Math results appear here for the Primary–5 students in the schools you oversee."
          />
        ) : (
          // Remount on cycle change so no expanded block from the previous cycle lingers.
          <MathRollupTree key={cycle ?? 'current'} rows={rows} cycle={cycle} />
        )}
      </>
    )
  }

  let groups: TeacherGroup[] = []
  if (!error) {
    try {
      groups = await getMathCohortGroups(upn)
    } catch (e) {
      error = e instanceof Error ? e.message : String(e)
    }
  }

  // A caller with exactly one group jumps straight to it (teacher with a single homeroom).
  if (!error && groups.length === 1) {
    redirect(`/reports/math/${encodeURIComponent(groups[0].key)}`)
  }

  return (
    <>
      <PageHeader title="Reports" subtitle="Math — pick a class or grade to see the results matrix" />
      {toggle}
      <p className="muted small" style={{ margin: '0 0 1rem' }}>
        Math results cover grades Primary–5 only.
      </p>
      {error ? (
        <ErrorNote message={error} />
      ) : groups.length === 0 ? (
        <EmptyState
          title="No classes in your scope"
          hint="Math results appear here for the Primary–5 classes you can see."
        />
      ) : (
        <GroupCards groups={groups} hrefBase="/reports/math" metaSuffix="students" metaMode="count" />
      )}
    </>
  )
}
