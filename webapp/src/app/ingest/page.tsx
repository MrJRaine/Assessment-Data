import { PageHeader, ScaffoldNote, Placeholder } from '@/components/ui'

export const dynamic = 'force-dynamic'

export default function Ingest() {
  return (
    <>
      <PageHeader title="Ingest" subtitle="Analyst-triggered data ingestion" />
      <ScaffoldNote>
        Regional-analyst only &mdash; will gate on role and bind to the ingest trigger proc.
      </ScaffoldNote>
      <Placeholder label="ingest status + trigger control" />
    </>
  )
}
