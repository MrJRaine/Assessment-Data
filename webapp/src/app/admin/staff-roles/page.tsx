import { PageHeader, ErrorNote, EmptyState } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getCallerCapabilities, getStaffRoleOverrideList, type StaffRoleOverrideRow } from '@/lib/data'
import RoleOverrideManager from './RoleOverrideManager'

export const dynamic = 'force-dynamic'

export default async function StaffRolesPage() {
  const upn = await getCurrentUpn()

  let allowed = false
  let overrides: StaffRoleOverrideRow[] = []
  let error: string | null = null
  try {
    // fresh: authorization must never come from a cached capability.
    allowed = (await getCallerCapabilities(upn, { fresh: true })).isSysAdmin
    if (allowed) overrides = await getStaffRoleOverrideList()
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  return (
    <>
      <PageHeader
        title="Role Overrides"
        subtitle="Classify staff the PowerSchool export can't — e.g. Instructional Coaches as Administrator"
      />
      {error ? (
        <ErrorNote message={error} />
      ) : !allowed ? (
        <EmptyState title="Access restricted" hint="Managing role overrides is restricted to system administrators." />
      ) : (
        <RoleOverrideManager overrides={overrides} />
      )}
    </>
  )
}
