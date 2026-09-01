'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'

const ITEMS = [
  { href: '/', label: 'Home', exact: true },
  { href: '/enter', label: 'Data Entry' },
  { href: '/students', label: 'Students' },
  { href: '/ipp', label: 'IPPs' },
  { href: '/cycles', label: 'Cycles', analyst: true },
  { href: '/ingest', label: 'Ingest', analyst: true },
]

export default function Nav({ showAnalyst = false }: { showAnalyst?: boolean }) {
  const path = usePathname()
  // Cycles + Ingest are RegionalAnalyst-only — hide them from everyone else (the pages/actions also enforce it).
  const items = ITEMS.filter((it) => !it.analyst || showAnalyst)
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
