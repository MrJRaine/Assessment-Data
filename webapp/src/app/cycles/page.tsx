import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getCallerCapabilities, getShortCycles, type ShortCycle } from '@/lib/data'
import ShortCyclesManager from './ShortCyclesManager'

export const dynamic = 'force-dynamic'

export default async function CyclesPage() {
  const upn = await getCurrentUpn()

  let allowed = false
  let cycles: ShortCycle[] = []
  let error: string | null = null
  try {
    allowed = (await getCallerCapabilities(upn)).canManageCycles
    if (allowed) cycles = await getShortCycles()
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
      ) : !allowed ? (
        <EmptyState
          title="Access restricted"
          hint="Managing assessment cycles is restricted to designated staff."
        />
      ) : (
        <ShortCyclesManager initialCycles={cycles} />
      )}
    </>
  )
}
