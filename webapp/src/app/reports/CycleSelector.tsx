'use client'

import Link from 'next/link'
import { usePathname, useSearchParams } from 'next/navigation'
import type { ReportCycle } from '@/lib/data'

/**
 * Shared cycle selector for the Reports pages. "Current" (lifetime / most-recent) plus one button per
 * this-year cycle that has started (open / grace / closed — Upcoming excluded). Selection rides the
 * `?cycle=<CycleGroupID>` URL param, preserving every other param (e.g. `?subject=writing`), so it
 * works uniformly across /reports, /reports?subject=writing, /reports/math and /reports/rwm. Hover a
 * cycle button to see its date range.
 */
export default function CycleSelector({ cycles }: { cycles: ReportCycle[] }) {
  const pathname = usePathname()
  const params = useSearchParams()
  const current = params.get('cycle')

  const hrefFor = (cycleId: string | null): string => {
    const p = new URLSearchParams(params.toString())
    if (cycleId) p.set('cycle', cycleId)
    else p.delete('cycle')
    const qs = p.toString()
    return qs ? `${pathname}?${qs}` : pathname
  }

  return (
    <div className="cycle-selector">
      <span className="cycle-label">Cycle</span>
      <Link href={hrefFor(null)} className={!current ? 'cycle-btn cycle-on' : 'cycle-btn'} title="Most recent result so far this year">
        Current
      </Link>
      {cycles.map((c) => (
        <Link
          key={c.cycleGroupId}
          href={hrefFor(c.cycleGroupId)}
          className={current === c.cycleGroupId ? 'cycle-btn cycle-on' : 'cycle-btn'}
          title={`${c.startDate} – ${c.endDate}`}
        >
          {c.name}
        </Link>
      ))}
    </div>
  )
}
