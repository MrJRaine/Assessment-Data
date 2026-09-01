import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getCallerCapabilities } from '@/lib/data'
import IngestPanel from './IngestPanel'

export const dynamic = 'force-dynamic'

export default async function IngestPage() {
  const upn = await getCurrentUpn()

  let allowed = false
  let error: string | null = null
  try {
    allowed = (await getCallerCapabilities(upn)).canRunIngest
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  return (
    <>
      <PageHeader title="Ingest" subtitle="Upload PowerSchool exports and run the ingest cycle" />
      {error ? (
        <ErrorNote message={error} />
      ) : !allowed ? (
        <EmptyState
          title="Access restricted"
          hint="Ingesting PowerSchool data is restricted to designated staff."
        />
      ) : (
        <IngestPanel />
      )}
    </>
  )
}
