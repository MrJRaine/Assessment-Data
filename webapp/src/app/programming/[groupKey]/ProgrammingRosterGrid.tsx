'use client'

import { useMemo, useState, useTransition } from 'react'
import type { ProgrammingRosterRow } from '@/lib/data'
import { saveProgramming, type ProgrammingKind, type ProgrammingSaveEntry, type ProgrammingSaveResult } from './actions'
import { useEntryLock } from '@/components/maintenance/useEntryLock'
import ProgrammingProgress, { type ProgStat } from '../ProgrammingProgress'

// Column order for the subject columns.
const SUBJECT_ORDER: Record<string, number> = { Reading: 0, Writing: 1, Math: 2 }
const FR = 'French Immersion'
const EN = 'English'

type FourWay = 'No' | 'FLA Only' | 'ELA Only' | 'Both'

// One student's rows for a subject, filtered to the rows that EXIST for the active kind.
interface Cell {
  families: { programFamily: string; value: boolean | null }[] // 1 (2-way) or 2 (EN+FR, 4-way)
}

const pkey = (studentKey: string, subject: string, programFamily: string) =>
  `${studentKey}|${subject}|${programFamily}`

export default function ProgrammingRosterGrid({ groupKey, rows }: { groupKey: string; rows: ProgrammingRosterRow[] }) {
  const [kind, setKind] = useState<ProgrammingKind>('IPP')
  // pending[studentKey|subject|family] = staged boolean; absent = unchanged.
  const [pending, setPending] = useState<Record<string, boolean>>({})
  const [busy, startTransition] = useTransition()
  const [result, setResult] = useState<ProgrammingSaveResult | null>(null)

  // Rows that carry a row of the active kind.
  const kindRows = useMemo(
    () => rows.filter((r) => (kind === 'IPP' ? r.ippExists : r.adaptationExists)),
    [rows, kind],
  )

  // Students shown for this kind (distinct), sorted by name.
  const students = useMemo(() => {
    const seen = new Map<string, ProgrammingRosterRow>()
    for (const r of kindRows) if (!seen.has(r.studentKey)) seen.set(r.studentKey, r)
    return [...seen.values()].sort(
      (a, b) => `${a.lastName}${a.firstName}`.localeCompare(`${b.lastName}${b.firstName}`),
    )
  }, [kindRows])

  // Subject columns present for this kind, in Reading/Writing/Math order.
  const subjects = useMemo(
    () =>
      [...new Set(kindRows.map((r) => r.subject))].sort(
        (a, b) => (SUBJECT_ORDER[a] ?? 9) - (SUBJECT_ORDER[b] ?? 9),
      ),
    [kindRows],
  )

  // (studentKey|subject) -> Cell, from the existing rows of the active kind.
  const cells = useMemo(() => {
    const m = new Map<string, Cell>()
    for (const r of kindRows) {
      const k = `${r.studentKey}|${r.subject}`
      const c = m.get(k) ?? { families: [] }
      c.families.push({ programFamily: r.programFamily, value: kind === 'IPP' ? r.isIPP : r.hasAdaptation })
      m.set(k, c)
    }
    return m
  }, [kindRows, kind])

  const effective = (studentKey: string, subject: string, family: string, storedVal: boolean | null): boolean | null => {
    const k = pkey(studentKey, subject, family)
    return k in pending ? pending[k] : storedVal
  }

  // A cell "needs confirmation" when any of its family values is still unset (null) after staging.
  const cellNeedsConfirm = (studentKey: string, subject: string): boolean => {
    const c = cells.get(`${studentKey}|${subject}`)
    if (!c) return false
    return c.families.some((f) => effective(studentKey, subject, f.programFamily, f.value) === null)
  }
  // Students in this roster with at least one unconfirmed cell.
  const needStudents = students.filter((st) => subjects.some((s) => cellNeedsConfirm(st.studentKey, s)))

  // Group-level progress for BOTH kinds (pending-aware, so it moves as cells are set) — shown at the
  // top regardless of the active toggle, so remaining work in the OTHER kind is still visible.
  const summarize = (k: ProgrammingKind): ProgStat => {
    const byStu = new Map<string, boolean>()
    for (const r of rows) {
      const has = k === 'IPP' ? r.ippExists : r.adaptationExists
      if (!has) continue
      const storedVal = k === 'IPP' ? r.isIPP : r.hasAdaptation
      const set = effective(r.studentKey, r.subject, r.programFamily, storedVal) !== null
      const prev = byStu.get(r.studentKey)
      byStu.set(r.studentKey, prev === undefined ? set : prev && set)
    }
    let confirmed = 0
    for (const done of byStu.values()) if (done) confirmed++
    return { confirmed, total: byStu.size }
  }
  const ippStat = summarize('IPP')
  const adaptationStat = summarize('Adaptation')

  // Stage one family value; revert to stored (drop the pending key) if it matches.
  function stage(studentKey: string, subject: string, family: string, value: boolean, storedVal: boolean | null) {
    const k = pkey(studentKey, subject, family)
    setPending((prev) => {
      const next = { ...prev }
      if (storedVal === value) delete next[k]
      else next[k] = value
      return next
    })
  }

  const dirtyKeys = Object.keys(pending)

  // Maintenance lock: per-(subject,family) upserts are independent, so the T-1 auto-save is safe.
  const { inputsLocked, markSaved } = useEntryLock({ dirty: dirtyKeys.length > 0, onSave: () => onSave() })

  function onSave() {
    const byKey = new Map(rows.map((r) => [pkey(r.studentKey, r.subject, r.programFamily), r]))
    const entries: ProgrammingSaveEntry[] = dirtyKeys.map((k) => {
      const r = byKey.get(k)!
      return { studentKey: r.studentKey, subject: r.subject, programFamily: r.programFamily, kind, value: pending[k] }
    })
    startTransition(async () => {
      const res = await saveProgramming(groupKey, entries)
      setResult(res)
      const failed = new Set(res.errors.map((e) => e.studentKey))
      setPending((prev) => {
        const next = { ...prev }
        for (const k of dirtyKeys) if (!failed.has(byKey.get(k)!.studentKey)) delete next[k]
        return next
      })
      markSaved() // at T-5 the next save is what locks input
    })
  }

  // ---- cell renderers -------------------------------------------------------
  function twoWay(studentKey: string, subject: string, fam: { programFamily: string; value: boolean | null }) {
    const eff = effective(studentKey, subject, fam.programFamily, fam.value)
    return (
      <span className="ipp-seg">
        <button className={eff === false ? 'seg seg-no-on' : 'seg'} disabled={busy || inputsLocked}
          onClick={() => stage(studentKey, subject, fam.programFamily, false, fam.value)}>No</button>
        <button className={eff === true ? 'seg seg-yes-on' : 'seg'} disabled={busy || inputsLocked}
          onClick={() => stage(studentKey, subject, fam.programFamily, true, fam.value)}>Yes</button>
      </span>
    )
  }

  function fourWay(studentKey: string, subject: string, cell: Cell) {
    const frRow = cell.families.find((f) => f.programFamily === FR)
    const enRow = cell.families.find((f) => f.programFamily === EN)
    if (!frRow || !enRow) return twoWay(studentKey, subject, cell.families[0]) // safety fallback
    const frEff = effective(studentKey, subject, FR, frRow.value)
    const enEff = effective(studentKey, subject, EN, enRow.value)
    // Current selection (null if either side is still unconfirmed).
    let sel: FourWay | null = null
    if (frEff !== null && enEff !== null) {
      sel = frEff && enEff ? 'Both' : frEff ? 'FLA Only' : enEff ? 'ELA Only' : 'No'
    }
    const pick = (opt: FourWay) => {
      const fr = opt === 'FLA Only' || opt === 'Both'
      const en = opt === 'ELA Only' || opt === 'Both'
      stage(studentKey, subject, FR, fr, frRow.value)
      stage(studentKey, subject, EN, en, enRow.value)
    }
    const opts: FourWay[] = ['No', 'FLA Only', 'ELA Only', 'Both']
    return (
      <span className="ipp-seg ipp-seg-4">
        {opts.map((o) => (
          <button key={o} className={sel === o ? 'seg seg-yes-on' : 'seg'} disabled={busy || inputsLocked} onClick={() => pick(o)}>
            {o}
          </button>
        ))}
      </span>
    )
  }

  function cellNode(studentKey: string, subject: string) {
    const c = cells.get(`${studentKey}|${subject}`)
    if (!c || c.families.length === 0) return <span className="muted">—</span>
    if (c.families.length === 1) return twoWay(studentKey, subject, c.families[0])
    return fourWay(studentKey, subject, c)
  }

  if (students.length === 0) {
    return (
      <>
        <ProgrammingProgress ipp={ippStat} adaptation={adaptationStat} />
        <RosterToggle kind={kind} setKind={setKind} />
        <p className="muted" style={{ marginTop: '1rem' }}>
          No {kind === 'IPP' ? 'IPP' : 'Adaptation'} records for this group.
        </p>
      </>
    )
  }

  return (
    <>
      <ProgrammingProgress ipp={ippStat} adaptation={adaptationStat} />
      <RosterToggle kind={kind} setKind={setKind} />

      <div className="ipp-toolbar">
        {kind === 'IPP' ? (
          <span className={needStudents.length ? 'ipp-need-pill' : 'ipp-need-pill ipp-need-clear'}>
            {needStudents.length} of {students.length} still need IPP confirmation
          </span>
        ) : (
          <span className="muted">Adaptations are recorded per subject (no confirmation gate). Unset cells are highlighted.</span>
        )}
      </div>

      <table className="grid">
        <thead>
          <tr>
            <th>Student</th>
            <th>Grade</th>
            {subjects.map((s) => (
              <th key={s}>{s}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {students.map((st) => (
            <tr key={st.studentKey}>
              <td>{st.lastName}, {st.firstName}</td>
              <td>{st.grade ?? '—'}</td>
              {subjects.map((s) => (
                <td key={s} className={cellNeedsConfirm(st.studentKey, s) ? 'pgm-need' : undefined}>
                  {cellNode(st.studentKey, s)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>

      <div className="actions">
        <button className="btn" onClick={onSave} disabled={busy || dirtyKeys.length === 0}>
          {busy ? 'Saving…' : dirtyKeys.length ? `Save ${dirtyKeys.length} change(s)` : 'Save'}
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
            <li key={i}>Student {e.studentKey}: {e.message}</li>
          ))}
        </ul>
      ) : null}
    </>
  )
}

function RosterToggle({ kind, setKind }: { kind: ProgrammingKind; setKind: (k: ProgrammingKind) => void }) {
  return (
    <div className="subject-toggle" role="tablist" style={{ marginTop: '0.25rem' }}>
      <button type="button" role="tab" className={kind === 'IPP' ? 'toggle-on' : ''} onClick={() => setKind('IPP')}>
        IPP
      </button>
      <button type="button" role="tab" className={kind === 'Adaptation' ? 'toggle-on' : ''} onClick={() => setKind('Adaptation')}>
        Adaptations
      </button>
    </div>
  )
}
