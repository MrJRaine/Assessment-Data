'use client'

import { useMemo } from 'react'
import { useSearchParams } from 'next/navigation'
import type { AchievementBand, ReportCycle } from '@/lib/data'

// Shared top-of-report charts for Reading/Writing (1.3.0): the achievement-distribution donut and the
// by-cycle achievement trend. Fed by plain {code,date} rows so BOTH the teacher flat cohort and the
// oversight roll-up feed can drive it.
//
// Two SEPARATE inputs, deliberately:
//   - donutRows  — the "current" distribution; RESPECTS the cycle selector (and, for teachers, the table
//                  filters), so it reflects whatever the page is scoped to.
//   - trendRows  — the by-cycle progression. It is NOT scoped to one cycle, but the cycle selector sets
//                  its RIGHT EDGE (user rule 2026-11-10): the selected cycle is always the rightmost bar,
//                  so the bar graph ends at the data being displayed with the earlier cycles alongside to
//                  compare against. No selection = all started cycles, rightmost = current.

export interface DonutDatum { code: number | null }
export interface TrendDatum { code: number | null; date: string | null }

export default function CohortCharts({
  donutRows,
  trendRows,
  bands,
  cycles,
}: {
  donutRows: DonutDatum[]
  trendRows: TrendDatum[]
  bands: AchievementBand[]
  cycles: ReportCycle[]
}) {
  const orderedBands = useMemo(() => [...bands].sort((a, b) => Number(a.code) - Number(b.code)), [bands])
  const bandByCode = useMemo(() => new Map(orderedBands.map((b) => [Number(b.code), b])), [orderedBands])

  // The donut RESPECTS the cycle selector, so its title must too — a static "Current" misreads when a
  // specific cycle is selected and the count changes. "Current" = no ?cycle param (lifetime most-recent);
  // otherwise the selected cycle's name (matched by CycleGroupID, same param CycleSelector writes).
  const selectedCycleId = useSearchParams().get('cycle')
  const scopeLabel = useMemo(
    () => cycles.find((c) => c.cycleGroupId === selectedCycleId)?.name ?? 'Current',
    [cycles, selectedCycleId],
  )

  // Donut: achievement distribution over ASSESSED rows (a band assigned → code != null; IPP / unresolved /
  // no-result are null and excluded, matching the roll-up's % Meeting/Exceeding denominator).
  const donut = useMemo(() => {
    const assessed = donutRows.filter((r) => r.code != null)
    const counts = new Map<number, number>()
    for (const r of assessed) counts.set(r.code!, (counts.get(r.code!) ?? 0) + 1)
    const total = assessed.length
    let acc = 0
    const slices = orderedBands.map((b) => {
      const code = Number(b.code)
      const count = counts.get(code) ?? 0
      const startPct = total ? (acc / total) * 100 : 0
      acc += count
      const endPct = total ? (acc / total) * 100 : 0
      return { code, name: b.name, color: b.hexColor, count, pct: total ? (count / total) * 100 : 0, startPct, endPct }
    })
    const gradient = total
      ? slices.filter((s) => s.count > 0).map((s) => `${s.color} ${s.startPct.toFixed(2)}% ${s.endPct.toFixed(2)}%`).join(', ')
      : 'var(--border) 0% 100%'
    return { slices, total, gradient }
  }, [donutRows, orderedBands])

  // By-cycle bar: up to 6 cycles (oldest → newest), cumulative most-recent achievement AS-OF each
  // cycle's end date — the cycle-based successor to the old "last 6 months" chart. cycles come from
  // getReportCycles (this year's started cycles, StartDate-ascending). The SELECTED cycle caps the
  // window — it is always the rightmost bar (cycles after it are dropped), so the graph ends at the
  // data on display; with no selection the window ends at the most recent cycle.
  const cycleBuckets = useMemo(() => {
    const idx = cycles.findIndex((c) => c.cycleGroupId === selectedCycleId)
    return (idx >= 0 ? cycles.slice(0, idx + 1) : cycles).slice(-6)
  }, [cycles, selectedCycleId])
  const cycleSeries = useMemo(
    () =>
      cycleBuckets.map((c) => {
        const counts: Record<number, number> = { 1: 0, 2: 0, 3: 0, 4: 0 }
        let total = 0
        for (const r of trendRows) {
          if (r.code == null || !r.date) continue
          if (r.date <= c.endDate) {
            counts[r.code] = (counts[r.code] ?? 0) + 1
            total++
          }
        }
        return { label: c.name, counts, total }
      }),
    [cycleBuckets, trendRows],
  )
  const cycleMax = useMemo(() => Math.max(1, ...cycleSeries.map((m) => m.total)), [cycleSeries])

  return (
    <div className="cohort-charts">
      <div className="chart-card">
        <div className="chart-title">{scopeLabel} achievement distribution</div>
        <div className="donut-wrap">
          <div className="donut" style={{ background: `conic-gradient(${donut.gradient})` }}>
            <div className="donut-hole">
              <div className="donut-total">{donut.total}</div>
              <div className="donut-label">ASSESSED</div>
            </div>
          </div>
          <ul className="donut-legend">
            {donut.slices.map((s) => (
              <li key={s.code}>
                <span className="swatch" style={{ background: s.color }} />
                <span className="legend-name">{s.name}</span>
                <span className="legend-val">{s.pct.toFixed(1)}% · {s.count}</span>
              </li>
            ))}
          </ul>
        </div>
        {donut.total === 0 ? <div className="muted chart-empty">No assessed, chart-eligible students match.</div> : null}
      </div>

      <div className="chart-card">
        <div className="chart-title">Achievement by cycle</div>
        {cycleBuckets.length === 0 ? (
          <div className="muted chart-empty">No cycles have started yet this year.</div>
        ) : (
          <>
            <div className="monthbars">
              {cycleSeries.map((m) => (
                <div key={m.label} className="monthbar">
                  <div className="monthbar-stack">
                    {[1, 2, 3, 4].map((c) => {
                      const v = m.counts[c] ?? 0
                      if (!v) return null
                      const band = bandByCode.get(c)
                      const h = (v / cycleMax) * 100
                      return (
                        <div
                          key={c}
                          className="monthbar-seg"
                          style={{ height: `${h}%`, background: band?.hexColor ?? 'var(--border)' }}
                          title={`${band?.name ?? c}: ${v}`}
                        />
                      )
                    })}
                  </div>
                  <div className="monthbar-label">{m.label}</div>
                </div>
              ))}
            </div>
            <ul className="bar-legend">
              {orderedBands.map((b) => (
                <li key={b.code}>
                  <span className="swatch" style={{ background: b.hexColor }} />
                  {b.name}
                </li>
              ))}
            </ul>
          </>
        )}
      </div>
    </div>
  )
}
