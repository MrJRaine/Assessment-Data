import Link from 'next/link'
import { PageHeader, EmptyState, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getTeacherGroups, type TeacherGroup } from '@/lib/data'
import GroupCards from '@/components/GroupCards'

export const dynamic = 'force-dynamic'

/**
 * Step 2, keyed on the CYCLE + subject rather than one instance window. The groups are the caller's
 * mapped-course sections (ELA / FLA / Math only — never their gym or science class), which is also
 * where the entry LANGUAGE comes from: an FLA section enters French, an ELA section English, so
 * there is no language toggle to get wrong.
 */
export default async function GroupSelect({
  params,
}: {
  params: Promise<{ cycleGroupId: string; subject: string }>
}) {
  const { cycleGroupId: rawCycle, subject: rawSubject } = await params
  const cycleGroupId = decodeURIComponent(rawCycle)
  const subject = decodeURIComponent(rawSubject)
  const upn = await getCurrentUpn()

  let groups: TeacherGroup[] = []
  let error: string | null = null
  try {
    groups = await getTeacherGroups(upn, cycleGroupId, subject)
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  return (
    <>
      <PageHeader title="Choose a group" subtitle={`Step 2 — your ${subject.toLowerCase()} classes for this cycle`} />
      <p>
        <Link href="/enter" className="back-link">
          &larr; Back to cycles
        </Link>
      </p>
      {error ? (
        <ErrorNote message={error} />
      ) : groups.length === 0 ? (
        <EmptyState
          title="No classes for this cycle"
          hint={`You teach no ${subject.toLowerCase()} course section with students in this cycle's grade and program scope.`}
        />
      ) : (
        <GroupCards groups={groups} hrefBase={`/enter/cycle/${rawCycle}/${rawSubject}`} mode="course" subject={rawSubject} />
      )}
    </>
  )
}
