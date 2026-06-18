import { getReadiness } from '@/lib/readiness'
import { PageHeader, CardLink, ScaffoldNote } from '@/components/ui'

export const dynamic = 'force-dynamic'

export default function Home() {
  const r = getReadiness()
  return (
    <>
      <PageHeader title="Assessment Data Platform" subtitle="Reading & writing assessment entry and review" />
      <ScaffoldNote>
        Layout scaffold &mdash; navigation and page structure are in place; data wiring is pending Fabric
        access (Phase 3b / B3).
      </ScaffoldNote>
      <div className="card-grid">
        <CardLink href="/enter" title="Enter Assessments" meta="Window &rarr; group &rarr; roster" />
        <CardLink href="/students" title="Students" meta="Cohort view + per-student detail" />
        <CardLink href="/ipp" title="IPPs" meta="Individual Program Plan flags" />
        <CardLink href="/ingest" title="Ingest" meta="Analyst-triggered ingestion" />
      </div>
      <div className="status-strip muted">
        Region: {r.region} {r.regionCompliant ? '(OK)' : '(check)'} &middot; Auth: {r.authMode} &middot;
        Fabric configured: {r.fabricConfigured ? 'yes' : 'no'}
      </div>
    </>
  )
}
