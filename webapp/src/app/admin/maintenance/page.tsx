import { redirect } from 'next/navigation'
import { PageHeader } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getCallerCapabilities, getMaintenanceWindow } from '@/lib/data'
import MaintenanceControl from './MaintenanceControl'

export const dynamic = 'force-dynamic'

// Maintenance control page — CanMaintain (Technology Services) OR sysadmin (1.3.0; was sysadmin-only).
export default async function MaintenanceAdminPage() {
  const upn = await getCurrentUpn()
  const caps = await getCallerCapabilities(upn, { fresh: true })
  if (!caps.canMaintain && !caps.isSysAdmin) redirect('/')

  // Resilient if AppMaintenance isn't deployed yet — show "none" rather than erroring the page.
  let current = { maintenanceAt: null as string | null, message: null as string | null, setBy: null as string | null }
  try {
    current = await getMaintenanceWindow()
  } catch {
    /* table not deployed yet — the first schedule will surface a clear error */
  }

  // LOTO: the Cancel/all-clear control belongs to the window's OWNER or a sysadmin — matching the
  // proc's gate, so a CanMaintain non-owner isn't shown a button that would be refused.
  const canClear = caps.isSysAdmin || (current.setBy != null && current.setBy === upn.toLowerCase())

  return (
    <>
      <PageHeader
        title="Maintenance"
        subtitle="Schedule a graceful entry lockout before an emergency container swap. Teachers get a countdown, entry locks in stages, and unsaved work is auto-saved before the restart."
      />
      <MaintenanceControl current={current} canClear={canClear} />
    </>
  )
}
