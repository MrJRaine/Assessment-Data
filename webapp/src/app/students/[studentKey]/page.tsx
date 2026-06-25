import Link from 'next/link'
import { PageHeader, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getStudentNavList, getStudentHistory, type HistoryRow, type StudentNavItem } from '@/lib/data'
import StudentDetailView from './StudentDetailView'

export const dynamic = 'force-dynamic'

export default async function StudentDetailPage({ params }: { params: Promise<{ studentKey: string }> }) {
  const { studentKey } = await params
  const upn = await getCurrentUpn()

  let error: string | null = null
  let navList: StudentNavItem[] = []
  let initialHistory: HistoryRow[] = []
  try {
    // The nav list is fetched once here; subsequent prev/next paging is client-side, so the heavy
    // cohort query no longer re-runs on every navigation (the cause of the slow paging).
    ;[navList, initialHistory] = await Promise.all([
      getStudentNavList(upn),
      getStudentHistory(upn, studentKey),
    ])
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  if (error) {
    return (
      <>
        <PageHeader title="Student detail" />
        <ErrorNote message={error} />
      </>
    )
  }

  if (!navList.some((s) => s.studentKey === studentKey)) {
    return (
      <>
        <PageHeader title="Student detail" />
        <p>
          <Link href="/students" className="back-link">&larr; Back to students</Link>
        </p>
        <div className="notice notice-empty">
          <div className="notice-title">Student not in your scope</div>
        </div>
      </>
    )
  }

  return <StudentDetailView navList={navList} initialKey={studentKey} initialHistory={initialHistory} />
}
