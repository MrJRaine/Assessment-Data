import { redirect } from 'next/navigation'
import { PageHeader } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getCallerCapabilities, getMaintenanceWindow } from '@/lib/data'
import MaintenanceControl from './MaintenanceControl'

export const dynamic = 'force-dynamic'

// Sysadmin-only control page for the maintenance window (StaffAppAccess.IsSysAdmin).
export default async function MaintenanceAdminPage() {
  const upn = await getCurrentUpn()
  const caps = await getCallerCapabilities(upn, { fresh: true })
  if (!caps.isSysAdmin) redirect('/')

  // Resilient if AppMaintenance isn't deployed yet — show "none" rather than erroring the page.
  let current = { maintenanceAt: null as string | null, message: null as string | null }
  try {
    current = await getMaintenanceWindow()
  } catch {
    /* table not deployed yet — the first schedule will surface a clear error */
  }

  return (
    <>
      <PageHeader
        title="Maintenance"
        subtitle="Schedule a graceful entry lockout before an emergency container swap. Teachers get a countdown, entry locks in stages, and unsaved work is auto-saved before the restart."
      />
      <MaintenanceControl current={current} />
    </>
  )
}
