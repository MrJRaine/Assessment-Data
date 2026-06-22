import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getStudentIPPList, type IPPRow } from '@/lib/data'
import IPPManager from './IPPManager'

export const dynamic = 'force-dynamic'

export default async function IppPage() {
  const upn = await getCurrentUpn()

  let rows: IPPRow[] = []
  let error: string | null = null
  try {
    rows = await getStudentIPPList(upn)
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  return (
    <>
      <PageHeader
        title="IPP Subject Confirmation"
        subtitle="Confirm each student's Literacy IPP so assessment data is interpreted correctly"
      />
      {error ? (
        <ErrorNote message={error} />
      ) : rows.length === 0 ? (
        <EmptyState title="No IPP rows in your scope" hint="Students flagged for an IPP appear here once PowerSchool marks them." />
      ) : (
        <IPPManager rows={rows} />
      )}
    </>
  )
}
