'use client'

import { useState, useTransition } from 'react'
import { saveReadingAssessments, type SaveResult } from './actions'
import type { RosterStudent, ScaleLevel, AchievementBand } from '@/lib/data'

function ippText(s: RosterStudent): string {
  if (s.ippStatus === true) return 'IPP'
  if (s.ippStatus === false) return 'Not IPP'
  return s.ippNeedsConfirmation ? 'Confirm' : '—'
}

// ReadingDelta from a level's order vs the expected [min,max] range -- mirrors the server
// formula in usp_UpsertReadingAssessment so the live (pre-save) value matches what Save stores.
function computeDelta(order: number | null, minOrder: number | null, maxOrder: number | null): number | null {
  if (order == null || minOrder == null || maxOrder == null) return null
  if (order >= minOrder && order <= maxOrder) return 0
  if (order < minOrder) return order - minOrder
  return order - maxOrder
}

// Match a delta to an achievement band (same bounds logic as DimAchievementLevel / the TVF join).
function matchBand(delta: number | null, bands: AchievementBand[]): AchievementBand | null {
  if (delta == null) return null
  for (const b of bands) {
    const lo =
      b.lowerBound == null ||
      (b.lowerOp === '>=' && delta >= b.lowerBound) ||
      (b.lowerOp === '>' && delta > b.lowerBound) ||
      (b.lowerOp === '=' && delta === b.lowerBound)
    const hi =
      b.upperBound == null ||
      (b.upperOp === '<=' && delta <= b.upperBound) ||
      (b.upperOp === '<' && delta < b.upperBound) ||
      (b.upperOp === '=' && delta === b.upperBound)
    if (lo && hi) return b
  }
  return null
}

export default function RosterEntry({
  windowId,
  groupKey,
  roster,
  levels,
  achievementLevels,
}: {
  windowId: string
  groupKey: string
  roster: RosterStudent[]
  levels: ScaleLevel[]
  achievementLevels: AchievementBand[]
}) {
  const codeToId = new Map(levels.map((l) => [l.levelCode, l.readingScaleId] as const))
  const orderById = new Map(levels.map((l) => [l.readingScaleId, l.levelOrder] as const))
  const orderByCode = new Map(levels.map((l) => [l.levelCode, l.levelOrder] as const))
  const numByKey = new Map(roster.map((s) => [s.studentKey, s.studentNumber] as const))

  const baselineFromProps: Record<string, string> = {}
  for (const s of roster) baselineFromProps[s.studentKey] = s.currentLevel ? codeToId.get(s.currentLevel) ?? '' : ''

  const [baseline, setBaseline] = useState(baselineFromProps)
  const [sel, setSel] = useState(baselineFromProps)
  const [pending, startTransition] = useTransition()
  const [result, setResult] = useState<SaveResult | null>(null)

  const changedKeys = roster.map((s) => s.studentKey).filter((k) => sel[k] && sel[k] !== baseline[k])

  function onSave() {
    const entries = changedKeys.map((k) => ({ studentNumber: numByKey.get(k)!, readingScaleId: sel[k] }))
    startTransition(async () => {
      const r = await saveReadingAssessments(windowId, groupKey, entries)
      setResult(r)
      const erroredNums = new Set(r.errors.map((e) => e.studentNumber))
      setBaseline((prev) => {
        const next = { ...prev }
        for (const k of changedKeys) if (!erroredNums.has(numByKey.get(k)!)) next[k] = sel[k]
        return next
      })
    })
  }

  return (
    <>
      <table className="grid">
        <thead>
          <tr>
            <th>Student</th>
            <th>Grade</th>
            <th>Current</th>
            <th>Expected</th>
            <th>Δ</th>
            <th>New level</th>
            <th>IPP</th>
          </tr>
        </thead>
        <tbody>
          {roster.map((s) => {
            const selId = sel[s.studentKey] ?? ''
            const dirty = selId !== (baseline[s.studentKey] ?? '')
            // Live delta + colour from the CURRENT selection (recomputes as the dropdown changes).
            const order = selId ? orderById.get(selId) ?? null : null
            const minOrder = s.expectedMin ? orderByCode.get(s.expectedMin) ?? null : null
            const maxOrder = s.expectedMax ? orderByCode.get(s.expectedMax) ?? null : null
            const delta = computeDelta(order, minOrder, maxOrder)
            const band = matchBand(delta, achievementLevels)
            return (
              <tr
                key={s.studentKey}
                className={dirty ? 'row-dirty' : undefined}
                style={band ? { background: band.hexColorTint } : undefined}
              >
                <td>
                  {s.lastName}, {s.firstName}
                </td>
                <td>{s.grade ?? '—'}</td>
                <td>{s.currentLevel ?? <span className="muted">—</span>}</td>
                <td className="muted">
                  {s.expectedMin && s.expectedMax ? `${s.expectedMin}–${s.expectedMax}` : '—'}
                </td>
                <td style={band ? { color: band.hexColor, fontWeight: 600 } : undefined} title={band?.name}>
                  {delta == null ? '—' : delta > 0 ? `+${delta}` : delta}
                </td>
                <td>
                  <select
                    value={selId}
                    disabled={pending || levels.length === 0}
                    onChange={(e) => setSel((p) => ({ ...p, [s.studentKey]: e.target.value }))}
                  >
                    <option value="">—</option>
                    {levels.map((l) => (
                      <option key={l.readingScaleId} value={l.readingScaleId}>
                        {l.levelCode}
                      </option>
                    ))}
                  </select>
                </td>
                <td className={s.ippNeedsConfirmation ? 'ipp-confirm' : undefined}>{ippText(s)}</td>
              </tr>
            )
          })}
        </tbody>
      </table>

      <div className="actions">
        <button className="btn" onClick={onSave} disabled={pending || changedKeys.length === 0}>
          {pending ? 'Saving…' : changedKeys.length ? `Save ${changedKeys.length} change(s)` : 'Save'}
        </button>
        {result ? (
          <span className="save-result">
            Saved {result.saved}
            {result.errors.length ? ` · ${result.errors.length} failed` : ''}
          </span>
        ) : null}
      </div>

      {result?.errors.length ? (
        <ul className="save-errors">
          {result.errors.map((e, i) => (
            <li key={i}>
              Student {e.studentNumber}: {e.message}
            </li>
          ))}
        </ul>
      ) : null}
    </>
  )
}
