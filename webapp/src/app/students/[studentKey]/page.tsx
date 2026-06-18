import Link from 'next/link'
import { PageHeader, ScaffoldNote, Placeholder } from '@/components/ui'
import { MOCK_STUDENTS } from '@/lib/mock'

export const dynamic = 'force-dynamic'

export default async function StudentDetail({ params }: { params: Promise<{ studentKey: string }> }) {
  const { studentKey } = await params
  const student = MOCK_STUDENTS.find((s) => s.key === studentKey)
  return (
    <>
      <PageHeader
        title={student?.name ?? `Student ${studentKey}`}
        subtitle={student ? `Grade ${student.grade}` : undefined}
      />
      <p>
        <Link href="/students" className="back-link">
          &larr; Back to students
        </Link>
      </p>
      <ScaffoldNote>
        Info strip, assessment timeline, and reading-level line chart bind to the per-student history view.
      </ScaffoldNote>
      <div className="detail-grid">
        <Placeholder label="info strip (IPP status, current level)" />
        <Placeholder label="reading-level line chart over time" />
        <Placeholder label="assessment history table (most recent first)" />
      </div>
    </>
  )
}
