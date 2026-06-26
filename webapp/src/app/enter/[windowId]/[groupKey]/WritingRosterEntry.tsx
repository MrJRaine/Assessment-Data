'use client'

import { useState, useTransition } from 'react'
import { saveWritingAssessments, confirmRosterIPPs, type WritingEntry, type IppEntry } from './actions'
import type { WritingRosterStudent } from '@/lib/data'

const TRAITS = [
  { key: 'ideas', label: 'Ideas' },
  { key: 'organization', label: 'Org.' },
  { key: 'language', label: 'Lang.' },
  { key: 'conventions', label: 'Conv.' },
] as const
type TraitKey = (typeof TRAITS)[number]['key']
type ScoreSet = Record<TraitKey, number | null>

// Writing achievement band from the 4-trait average — mirrors DimAchievementLevel codes 1-4 and the
// 1.75/2.75/3.50 cut scores, so the live (pre-save) colour matches what the writing TVFs compute.
function writingBand(avg: number | null): { name: string; hex: string; tint: string } | null {
  if (avg == null) return null
  if (avg >= 3.5) return { name: 'Exceeding', hex: '#2E7D5B', tint: '#CCE8DB' }
  if (avg >= 2.75) return { name: 'Meeting', hex: '#8FB339', tint: '#EEF4D6' }
  if (avg >= 1.75) return { name: 'Approaching', hex: '#E8A33D', tint: '#FDF4E6' }
  return { name: 'Not Yet Meeting', hex: '#D1495B', tint: '#FCEDEF' }
}

function avgOf(s: ScoreSet): number | null {
  if (s.ideas == null || s.organization == null || s.language == null || s.conventions == null) return null
  return (s.ideas + s.organization + s.language + s.conventions) / 4
}
function eqSet(a: ScoreSet, b: ScoreSet): boolean {
  return a.ideas === b.ideas && a.organization === b.organization && a.language === b.language && a.conventions === b.conventions
}

type SaveSummary = { saved: number; errors: { label: string; message: string }[] }

export default function WritingRosterEntry({
  windowId,
  groupKey,
  roster,
}: {
  windowId: string
  groupKey: string
  roster: WritingRosterStudent[]
}) {
  const numByKey = new Map(roster.map((s) => [s.studentKey, s.studentNumber] as const))
  const nameByKey = new Map(roster.map((s) => [s.studentKey, `${s.lastName}, ${s.firstName}`] as const))
  const nameByNum = new Map(roster.map((s) => [s.studentNumber, `${s.lastName}, ${s.firstName}`] as const))
  const pfByKey = new Map(roster.map((s) => [s.studentKey, s.programFamily] as const))

  const baselineFromProps: Record<string, ScoreSet> = {}
  for (const s of roster)
    baselineFromProps[s.studentKey] = { ideas: s.ideas, organization: s.organization, language: s.language, conventions: s.conventions }

  const [base, setBase] = useState(baselineFromProps)
  const [sel, setSel] = useState(baselineFromProps)
  // Staged writing-IPP confirmations, committed on Save (like the reading grid); re-click un-stages.
  const [ippSel, setIppSel] = useState<Record<string, boolean>>({})
  const [pending, startTransition] = useTransition()
  const [result, setResult] = useState<SaveSummary | null>(null)

  const changedKeys = roster.map((s) => s.studentKey).filter((k) => !eqSet(sel[k], base[k]))
  const ippKeys = Object.keys(ippSel)
  const dirtyCount = changedKeys.length + ippKeys.length

  function setTrait(sk: string, trait: TraitKey, val: number | null) {
    setSel((p) => ({ ...p, [sk]: { ...p[sk], [trait]: val } }))
  }
  function chooseIPP(studentKey: string, value: boolean) {
    setIppSel((prev) => {
      const next = { ...prev }
      if (next[studentKey] === value) delete next[studentKey]
      else next[studentKey] = value
      return next
    })
  }

  function onSave() {
    // A writing result needs ALL FOUR traits; changed rows missing any trait are flagged, not sent.
    const ready = changedKeys.filter((k) => avgOf(sel[k]) != null)
    const incomplete = changedKeys.filter((k) => avgOf(sel[k]) == null)
    const writingEntries: WritingEntry[] = ready.map((k) => ({
      studentNumber: numByKey.get(k)!,
      ideas: sel[k].ideas!,
      organization: sel[k].organization!,
      language: sel[k].language!,
      conventions: sel[k].conventions!,
    }))
    const missingPf = ippKeys.filter((k) => !pfByKey.get(k))
    const ippEntries: IppEntry[] = ippKeys
      .map((k) => (pfByKey.get(k) ? { studentKey: k, programFamily: pfByKey.get(k)!, isIPP: ippSel[k] } : null))
      .filter((e): e is IppEntry => e !== null)

    startTransition(async () => {
      const wRes = writingEntries.length
        ? await saveWritingAssessments(windowId, groupKey, writingEntries)
        : { saved: 0, errors: [] as { studentNumber: string; message: string }[] }
      const ippRes = ippEntries.length
        ? await confirmRosterIPPs(windowId, groupKey, ippEntries, 'Writing')
        : { saved: 0, errors: [] as { studentKey: string; message: string }[] }

      const errs: SaveSummary['errors'] = []
      for (const e of wRes.errors) errs.push({ label: nameByNum.get(e.studentNumber) ?? `Student ${e.studentNumber}`, message: e.message })
      for (const e of ippRes.errors) errs.push({ label: nameByKey.get(e.studentKey) ?? 'Student', message: e.message })
      for (const k of incomplete) errs.push({ label: nameByKey.get(k) ?? 'Student', message: 'All four traits required — not saved.' })
      for (const k of missingPf) errs.push({ label: nameByKey.get(k) ?? 'Student', message: 'Missing program family — redeploy tvf_TeacherRosterWriting.' })
      setResult({ saved: wRes.saved + ippRes.saved, errors: errs })

      const erroredNums = new Set(wRes.errors.map((e) => e.studentNumber))
      setBase((prev) => {
        const next = { ...prev }
        for (const k of ready) if (!erroredNums.has(numByKey.get(k)!)) next[k] = { ...sel[k] }
        return next
      })
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
            {TRAITS.map((t) => (
              <th key={t.key}>{t.label}</th>
            ))}
            <th>Avg</th>
            <th>Achievement</th>
            <th>IPP</th>
          </tr>
        </thead>
        <tbody>
          {roster.map((s) => {
            const cur = sel[s.studentKey]
            const needsConfirm = s.ippNeedsConfirmation
            const isIPP = s.ippStatus === true
            const ippStaged = s.studentKey in ippSel
            const dirty = !eqSet(cur, base[s.studentKey]) || ippStaged
            const avg = avgOf(cur)
            // IPP students + unresolved gates carry no achievement band (mirrors the reading grid).
            const band = isIPP || needsConfirm ? null : writingBand(avg)
            return (
              <tr key={s.studentKey} className={dirty ? 'row-dirty' : undefined} style={band ? { background: band.tint } : undefined}>
                <td>
                  {s.lastName}, {s.firstName}
                </td>
                <td>{s.grade ?? '—'}</td>
                {TRAITS.map((t) => (
                  <td key={t.key}>
                    {needsConfirm ? (
                      <span className="muted">—</span>
                    ) : (
                      <select
                        value={cur[t.key] ?? ''}
                        disabled={pending}
                        onChange={(e) => setTrait(s.studentKey, t.key, e.target.value ? Number(e.target.value) : null)}
                      >
                        <option value="">—</option>
                        {[1, 2, 3, 4].map((n) => (
                          <option key={n} value={n}>
                            {n}
                          </option>
                        ))}
                      </select>
                    )}
                  </td>
                ))}
                <td>{isIPP ? 'IPP' : avg == null ? '—' : avg.toFixed(2)}</td>
                <td style={band ? { color: band.hex, fontWeight: 600 } : undefined}>
                  {isIPP ? 'IPP' : band ? band.name : '—'}
                </td>
                <td>
                  {needsConfirm ? (
                    <span className="ipp-seg">
                      <button
                        className={ippSel[s.studentKey] === true ? 'seg seg-yes-on' : 'seg'}
                        disabled={pending}
                        onClick={() => chooseIPP(s.studentKey, true)}
                      >
                        Yes (Literacy IPP)
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
