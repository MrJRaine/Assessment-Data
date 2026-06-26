import Link from 'next/link'
import { PageHeader, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import {
  getStudentNavList,
  getStudentHistory,
  getStudentHistoryWriting,
  type HistoryRow,
  type WritingHistoryRow,
  type StudentNavItem,
} from '@/lib/data'
import StudentDetailView from './StudentDetailView'
import { loadStudentHistory, loadStudentHistoryWriting } from './actions'

export const dynamic = 'force-dynamic'

export default async function StudentDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ studentKey: string }>
  searchParams: Promise<{ subject?: string }>
}) {
  const { studentKey } = await params
  const { subject } = await searchParams
  const isWriting = subject === 'writing'
  const subj: 'Reading' | 'Writing' = isWriting ? 'Writing' : 'Reading'
  const upn = await getCurrentUpn()

  let error: string | null = null
  let navList: StudentNavItem[] = []
  let initialHistory: HistoryRow[] | WritingHistoryRow[] = []
  try {
    ;[navList, initialHistory] = await Promise.all([
      getStudentNavList(upn, subj),
      isWriting ? getStudentHistoryWriting(upn, studentKey) : getStudentHistory(upn, studentKey),
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

  return (
    <StudentDetailView
      navList={navList}
      initialKey={studentKey}
      initialHistory={initialHistory}
      subject={subj}
      loadHistory={isWriting ? loadStudentHistoryWriting : loadStudentHistory}
    />
  )
}
