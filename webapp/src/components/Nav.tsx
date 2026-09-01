'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'

const ITEMS = [
  { href: '/', label: 'Home', exact: true },
  { href: '/enter', label: 'Data Entry' },
  { href: '/students', label: 'Students' },
  { href: '/ipp', label: 'IPPs' },
  { href: '/cycles', label: 'Cycles', cap: 'cycles' as const },
  { href: '/ingest', label: 'Ingest', cap: 'ingest' as const },
]

export default function Nav({ showCycles = false, showIngest = false }: { showCycles?: boolean; showIngest?: boolean }) {
  const path = usePathname()
  // Cycles + Ingest are capability-gated (StaffAppAccess) — hide them from anyone without the
  // capability (the pages/actions also enforce it server-side).
  const items = ITEMS.filter((it) =>
    it.cap === 'cycles' ? showCycles : it.cap === 'ingest' ? showIngest : true,
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
