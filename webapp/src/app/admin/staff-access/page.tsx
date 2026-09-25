import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getCallerCapabilities, getStaffAppAccessList, type StaffAccessRow } from '@/lib/data'
import StaffAccessManager from './StaffAccessManager'

export const dynamic = 'force-dynamic'

export default async function StaffAccessPage() {
  const upn = await getCurrentUpn()

  let allowed = false
  let staff: StaffAccessRow[] = []
  let error: string | null = null
  try {
    // fresh: authorization must never come from a cached capability.
    allowed = (await getCallerCapabilities(upn, { fresh: true })).isSysAdmin
    if (allowed) staff = await getStaffAppAccessList()
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  return (
    <>
      <PageHeader
        title="Staff Access"
        subtitle="Grant app capabilities — cycle management, ingest, and the grace-lock overrides"
      />
      {error ? (
        <ErrorNote message={error} />
      ) : !allowed ? (
        <EmptyState title="Access restricted" hint="Managing staff access is restricted to system administrators." />
      ) : (
        <StaffAccessManager staff={staff} selfUpn={upn} />
      )}
    </>
  )
}
