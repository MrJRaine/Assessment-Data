'use client'

import { useState, useTransition } from 'react'
import { saveReadingAssessments, confirmRosterIPPs, type SaveResult, type IppEntry } from './actions'
import type { RosterStudent, ScaleLevel, AchievementBand } from '@/lib/data'

// ReadingDelta from a level's order vs the expected [min,max] range -- mirrors the server
// formula in usp_UpsertReadingAssessment so the live (pre-save) value matches what Save stores.
function computeDelta(order: number | null, minOrder: number | null, maxOrder: number | null): number | null {
  if (order == null || minOrder == null || maxOrder == null) return null
  if (order >= minOrder && order <= maxOrder) return 0
  if (order < minOrder) return order - minOrder
  return order - maxOrder
}

// IPP "type" label shown on the confirm prompt. The teacher already knows the student is on an
// IPP; this confirms WHICH type. Reading + Writing both roll up to "Literacy"; Math stands alone.
function ippTypeLabel(subject: string): string {
  return subject === 'Math' ? 'Math IPP' : 'Literacy IPP'
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

type SaveSummary = { saved: number; errors: { label: string; message: string }[] }

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
  const nameByKey = new Map(roster.map((s) => [s.studentKey, `${s.lastName}, ${s.firstName}`] as const))
  const nameByNum = new Map(roster.map((s) => [s.studentNumber, `${s.lastName}, ${s.firstName}`] as const))
  const pfByKey = new Map(roster.map((s) => [s.studentKey, s.programFamily] as const))

  const baselineFromProps: Record<string, string> = {}
  for (const s of roster) baselineFromProps[s.studentKey] = s.currentLevel ? codeToId.get(s.currentLevel) ?? '' : ''

  const [baseline, setBaseline] = useState(baselineFromProps)
  const [sel, setSel] = useState(baselineFromProps)
  // Staged IPP confirmations: studentKey -> chosen value. Committed on Save (not per click), so
  // the screen never freezes mid-click; clicking the chosen value again un-stages it.
  const [ippSel, setIppSel] = useState<Record<string, boolean>>({})
  const [pending, startTransition] = useTransition()
  const [result, setResult] = useState<SaveSummary | null>(null)

  const changedLevelKeys = roster.map((s) => s.studentKey).filter((k) => sel[k] && sel[k] !== baseline[k])
  const ippKeys = Object.keys(ippSel)
  const dirtyCount = changedLevelKeys.length + ippKeys.length

  function chooseIPP(studentKey: string, value: boolean) {
    setIppSel((prev) => {
      const next = { ...prev }
      if (next[studentKey] === value) delete next[studentKey] // re-click the same choice -> un-stage
      else next[studentKey] = value
      return next
    })
  }

  function onSave() {
    const levelEntries = changedLevelKeys.map((k) => ({ studentNumber: numByKey.get(k)!, readingScaleId: sel[k] }))
    const missingPf = ippKeys.filter((k) => !pfByKey.get(k))
    const ippEntries: IppEntry[] = ippKeys
      .map((k) => (pfByKey.get(k) ? { studentKey: k, programFamily: pfByKey.get(k)!, isIPP: ippSel[k] } : null))
      .filter((e): e is IppEntry => e !== null)

    startTransition(async () => {
      const levelRes: SaveResult = levelEntries.length
        ? await saveReadingAssessments(windowId, groupKey, levelEntries)
        : { saved: 0, errors: [] }
      const ippRes = ippEntries.length
        ? await confirmRosterIPPs(windowId, groupKey, ippEntries)
        : { saved: 0, errors: [] as { studentKey: string; message: string }[] }

      const errs: SaveSummary['errors'] = []
      for (const e of levelRes.errors) errs.push({ label: nameByNum.get(e.studentNumber) ?? `Student ${e.studentNumber}`, message: e.message })
      for (const e of ippRes.errors) errs.push({ label: nameByKey.get(e.studentKey) ?? 'Student', message: e.message })
      for (const k of missingPf) errs.push({ label: nameByKey.get(k) ?? 'Student', message: 'Missing program family — redeploy tvf_TeacherRoster.' })
      setResult({ saved: levelRes.saved + ippRes.saved, errors: errs })

      // Clear saved level baselines (skip errored).
      const erroredNums = new Set(levelRes.errors.map((e) => e.studentNumber))
      setBaseline((prev) => {
        const next = { ...prev }
        for (const k of changedLevelKeys) if (!erroredNums.has(numByKey.get(k)!)) next[k] = sel[k]
        return next
      })
      // Clear staged IPPs that saved (keep errored / missing-PF ones staged).
      const erroredKeys = new Set([...ippRes.errors.map((e) => e.studentKey), ...missingPf])
      setIppSel((prev) => {
        const next = { ...prev }
        for (const k of ippKeys) if (!erroredKeys.has(k)) delete next[k]
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
            const needsConfirm = s.ippNeedsConfirmation
            const isIPP = s.ippStatus === true
            const ippStaged = s.studentKey in ippSel
            const dirty = selId !== (baseline[s.studentKey] ?? '') || ippStaged
            // IPP students and unresolved gates carry no achievement colour/delta (mirrors the app).
            const suppress = isIPP || needsConfirm
            const order = selId ? orderById.get(selId) ?? null : null
            const minOrder = s.expectedMin ? orderByCode.get(s.expectedMin) ?? null : null
            const maxOrder = s.expectedMax ? orderByCode.get(s.expectedMax) ?? null : null
            const delta = suppress ? null : computeDelta(order, minOrder, maxOrder)
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
                  {needsConfirm ? (
                    <span className="ipp-confirm">Confirm IPP</span>
                  ) : isIPP ? (
                    // IPP students follow an individualized plan — the standard-curriculum
                    // benchmark range doesn't apply, so show "IPP" instead of an expectation.
                    <span className="ipp-badge">IPP</span>
                  ) : s.expectedMin && s.expectedMax ? (
                    `${s.expectedMin}–${s.expectedMax}`
                  ) : (
                    '—'
                  )}
                </td>
                <td style={band ? { color: band.hexColor, fontWeight: 600 } : undefined} title={band?.name}>
                  {isIPP ? 'IPP' : delta == null ? '—' : delta > 0 ? `+${delta}` : delta}
                </td>
                <td>
                  {needsConfirm ? (
                    <span className="muted">—</span>
                  ) : (
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
                  )}
                </td>
                <td>
                  {needsConfirm ? (
                    // Staged segmented choice — saved with the Save button (not on click).
                    <span className="ipp-seg">
                      <button
                        className={ippSel[s.studentKey] === true ? 'seg seg-yes-on' : 'seg'}
                        disabled={pending}
                        onClick={() => chooseIPP(s.studentKey, true)}
                      >
                        Yes ({ippTypeLabel('Reading')})
                      </button>
                      <button
                        className={ippSel[s.studentKey] === false ? 'seg seg-no-on' : 'seg'}
                        disabled={pending}
                        onClick={() => chooseIPP(s.studentKey, false)}
                      >
                        No
                      </button>
                    </span>
                  ) : isIPP ? (
                    <span className="ipp-badge">IPP</span>
                  ) : s.ippStatus === false ? (
                    <span className="muted">Not IPP</span>
                  ) : (
                    <span className="muted">—</span>
                  )}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>

      <div className="actions">
        <button className="btn" onClick={onSave} disabled={pending || dirtyCount === 0}>
          {pending ? 'Saving…' : dirtyCount ? `Save ${dirtyCount} change(s)` : 'Save'}
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
              {e.label}: {e.message}
            </li>
          ))}
        </ul>
      ) : null}
    </>
  )
}
