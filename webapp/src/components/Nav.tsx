'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'

const ITEMS = [
  { href: '/', label: 'Home', exact: true },
  { href: '/enter', label: 'Enter Assessments' },
  { href: '/students', label: 'Students' },
  { href: '/ipp', label: 'IPPs' },
  { href: '/ingest', label: 'Ingest' },
]

export default function Nav() {
  const path = usePathname()
  return (
    <nav className="nav">
      {ITEMS.map((it) => {
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
