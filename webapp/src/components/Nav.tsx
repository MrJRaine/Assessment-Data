'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'

const ITEMS = [
  { href: '/', label: 'Home', exact: true },
  { href: '/enter', label: 'Data Entry' },
  { href: '/students', label: 'Students' },
  { href: '/programming', label: 'Programming' },
  { href: '/cycles', label: 'Cycles', cap: 'cycles' as const },
  { href: '/ingest', label: 'Ingest', cap: 'ingest' as const },
  { href: '/admin/maintenance', label: 'Maintenance', cap: 'maintenance' as const },
]

export default function Nav({
  showCycles = false,
  showIngest = false,
  showMaintenance = false,
}: {
  showCycles?: boolean
  showIngest?: boolean
  showMaintenance?: boolean
}) {
  const path = usePathname()
  // Cycles + Ingest + Maintenance are capability-gated (StaffAppAccess) — hide them from anyone
  // without the capability (the pages/actions also enforce it server-side).
  const items = ITEMS.filter((it) =>
    it.cap === 'cycles'
      ? showCycles
      : it.cap === 'ingest'
        ? showIngest
        : it.cap === 'maintenance'
          ? showMaintenance
          : true,
  )
  return (
    <nav className="nav">
      {items.map((it) => {
        const active = it.exact ? path === it.href : path === it.href || path.startsWith(it.href + '/')
        return (
          <Link key={it.href} href={it.href} className={active ? 'nav-link active' : 'nav-link'}>
            {it.label}
          </Link>
        )
      })}
    </nav>
  )
}
