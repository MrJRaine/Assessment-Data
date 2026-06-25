import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getCallerAccessLevel } from '@/lib/data'
import IngestPanel from './IngestPanel'

export const dynamic = 'force-dynamic'

export default async function IngestPage() {
  const upn = await getCurrentUpn()

  let role: string | null = null
  let error: string | null = null
  try {
    role = await getCallerAccessLevel(upn)
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  return (
    <>
      <PageHeader title="Ingest" subtitle="Upload PowerSchool exports and run the ingest cycle" />
      {error ? (
        <ErrorNote message={error} />
      ) : role !== 'RegionalAnalyst' ? (
        <EmptyState
          title="Regional Analyst access required"
          hint="Ingesting PowerSchool data is restricted to regional analysts."
        />
      ) : (
        <IngestPanel />
      )}
    </>
  )
}
