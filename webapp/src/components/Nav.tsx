'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'

const ITEMS = [
  { href: '/', label: 'Home', exact: true },
  { href: '/enter', label: 'Data Entry' },
  { href: '/students', label: 'Students' },
  { href: '/ipp', label: 'IPPs' },
  { href: '/ingest', label: 'Ingest' },
]

export default function Nav({ showIngest = false }: { showIngest?: boolean }) {
  const path = usePathname()
  // Ingest is RegionalAnalyst-only — hide it from everyone else (the page/actions also enforce it).
  const items = ITEMS.filter((it) => it.href !== '/ingest' || showIngest)
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
