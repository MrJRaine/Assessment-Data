import { PageHeader, ScaffoldNote, CardLink, Placeholder } from '@/components/ui'
import { MOCK_STUDENTS } from '@/lib/mock'

export const dynamic = 'force-dynamic'

export default function Students() {
  return (
    <>
      <PageHeader title="Students" subtitle="Cohort — filter and drill into a student" />
      <ScaffoldNote>
        Filters and charts bind to the cohort secured view; cards below are placeholder students.
      </ScaffoldNote>
      <div className="toolbar">
        <Placeholder label="filter bar (homeroom · program · school · achievement)" />
      </div>
      <div className="card-grid">
        {MOCK_STUDENTS.map((s) => (
          <CardLink key={s.key} href={`/students/${s.key}`} title={s.name} meta={`Grade ${s.grade}`} />
        ))}
      </div>
    </>
  )
}
