'use client'

import { usePathname, useSearchParams } from 'next/navigation'
import { ToggleLink } from '@/components/ToggleLink'
import type { ReportCycle } from '@/lib/data'

/**
 * Shared cycle selector for the Reports pages. "Current" (lifetime / most-recent) plus one button per
 * this-year cycle that has started (open / grace / closed — Upcoming excluded). Selection rides the
 * `?cycle=<CycleGroupID>` URL param, preserving every other param (e.g. `?subject=writing`), so it
 * works uniformly across /reports, /reports?subject=writing, /reports/math and /reports/rwm. Hover a
 * cycle button to see its date range.
 *
 * `cyclesOnly` (Missing results): no "Current" chip — the report is inherently per-cycle, so a
 * most-recent-result-per-student mode has no meaning there. With no `?cycle` param the NEWEST listed
 * cycle shows as selected, matching the page's server-side default.
 */
export default function CycleSelector({ cycles, cyclesOnly }: { cycles: ReportCycle[]; cyclesOnly?: boolean }) {
  const pathname = usePathname()
  const params = useSearchParams()
  const current = params.get('cycle') ?? (cyclesOnly ? cycles[cycles.length - 1]?.cycleGroupId ?? null : null)

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
      {cyclesOnly ? null : (
        <ToggleLink href={hrefFor(null)} className={!current ? 'cycle-btn cycle-on' : 'cycle-btn'} title="Most recent result so far this year">
          Current
        </ToggleLink>
      )}
      {cycles.map((c) => (
        <ToggleLink
          key={c.cycleGroupId}
          href={hrefFor(c.cycleGroupId)}
          className={current === c.cycleGroupId ? 'cycle-btn cycle-on' : 'cycle-btn'}
          title={`${c.startDate} – ${c.endDate}`}
        >
          {c.name}
        </ToggleLink>
      ))}
    </div>
  )
}
