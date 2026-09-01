import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getCallerAccessLevel, getShortCycles, type ShortCycle } from '@/lib/data'
import ShortCyclesManager from './ShortCyclesManager'

export const dynamic = 'force-dynamic'

export default async function CyclesPage() {
  const upn = await getCurrentUpn()

  let role: string | null = null
  let cycles: ShortCycle[] = []
  let error: string | null = null
  try {
    role = await getCallerAccessLevel(upn)
    if (role === 'RegionalAnalyst') cycles = await getShortCycles()
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  return (
    <>
      <PageHeader
        title="Short Cycles of Response"
        subtitle="Define the assessment cycles teachers enter results into"
      />
      {error ? (
        <ErrorNote message={error} />
      ) : role !== 'RegionalAnalyst' ? (
        <EmptyState
          title="Regional Analyst access required"
          hint="Managing assessment cycles is restricted to regional analysts."
        />
      ) : (
        <ShortCyclesManager initialCycles={cycles} />
      )}
    </>
  )
}
