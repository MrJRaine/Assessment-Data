import { redirect } from 'next/navigation'
import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getProgrammingGroups, getProgrammingSummary, type TeacherGroup, type ProgrammingSummary } from '@/lib/data'
import GroupCards from '../enter/[windowId]/GroupCards'
import ProgrammingProgress from './ProgrammingProgress'

export const dynamic = 'force-dynamic'

// Programming landing = the shared choose-a-group picker (window-less groups over flagged students).
// Teachers see their own classes ("My classes"); above-teacher roles get the oversight lenses.
// Picking a group opens its IPP + Adaptations roster.
export default async function ProgrammingPage() {
  const upn = await getCurrentUpn()

  let groups: TeacherGroup[] = []
  let summary: ProgrammingSummary | null = null
  let error: string | null = null
  try {
    ;[groups, summary] = await Promise.all([getProgrammingGroups(upn), getProgrammingSummary(upn)])
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  // A caller with exactly one group (e.g. a teacher with a single homeroom) skips the picker and
  // goes straight to that roster — "teacher → straight to their students".
  if (!error && groups.length === 1) {
    redirect(`/programming/${groups[0].key}`)
  }

  return (
    <>
      <PageHeader
        title="Programming"
        subtitle="Record each student's Individual Program Plans and Adaptations by subject, so results are interpreted correctly."
      />
      {error ? (
        <ErrorNote message={error} />
      ) : groups.length === 0 ? (
        <EmptyState
          title="No IPP or Adaptation records in your scope"
          hint="A class appears here once PowerSchool flags one of its students for an IPP or an Adaptation."
        />
      ) : (
        <>
          {summary ? <ProgrammingProgress ipp={summary.ipp} adaptation={summary.adaptation} /> : null}
          <GroupCards groups={groups} hrefBase="/programming" metaSuffix="need confirmation" />
        </>
      )}
    </>
  )
}
