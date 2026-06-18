import { PageHeader, CardLink, ScaffoldNote } from '@/components/ui'
import { MOCK_WINDOWS } from '@/lib/mock'

export const dynamic = 'force-dynamic'

export default function WindowSelect() {
  return (
    <>
      <PageHeader title="Enter Assessments" subtitle="Step 1 — choose an assessment window" />
      <ScaffoldNote>
        Windows below are placeholder data &mdash; to be replaced by a secured-view query scoped to the
        signed-in teacher.
      </ScaffoldNote>
      <div className="card-grid">
        {MOCK_WINDOWS.map((w) => (
          <CardLink key={w.id} href={`/enter/${w.id}`} title={w.name} meta={`${w.scale} · ${w.status}`} />
        ))}
      </div>
    </>
  )
}
