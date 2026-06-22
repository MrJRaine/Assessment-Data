'use client'

import { useState, useTransition } from 'react'
import { saveReadingAssessments, type SaveResult } from './actions'
import type { RosterStudent, ScaleLevel } from '@/lib/data'

function ippText(s: RosterStudent): string {
  if (s.ippStatus === true) return 'IPP'
  if (s.ippStatus === false) return 'Not IPP'
  return s.ippNeedsConfirmation ? 'Confirm' : '—'
}

export default function RosterEntry({
  windowId,
  groupKey,
  roster,
  levels,
}: {
  windowId: string
  groupKey: string
  roster: RosterStudent[]
  levels: ScaleLevel[]
}) {
  const codeToId = new Map(levels.map((l) => [l.levelCode, l.readingScaleId] as const))
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
            <th>New level</th>
            <th>IPP</th>
          </tr>
        </thead>
        <tbody>
          {roster.map((s) => {
            const dirty = (sel[s.studentKey] ?? '') !== (baseline[s.studentKey] ?? '')
            return (
              <tr key={s.studentKey} className={dirty ? 'row-dirty' : undefined}>
                <td>
                  {s.lastName}, {s.firstName}
                </td>
                <td>{s.grade ?? '—'}</td>
                <td>{s.currentLevel ?? <span className="muted">—</span>}</td>
                <td className="muted">
                  {s.expectedMin && s.expectedMax ? `${s.expectedMin}–${s.expectedMax}` : '—'}
                </td>
                <td>
                  <select
                    value={sel[s.studentKey] ?? ''}
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
