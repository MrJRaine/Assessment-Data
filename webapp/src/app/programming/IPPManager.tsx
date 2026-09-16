'use client'

import { useMemo, useState, useTransition } from 'react'
import { saveStudentIPPs, type IPPSaveResult } from './actions'
import type { IPPRow } from '@/lib/data'

const key = (r: IPPRow) => `${r.studentKey}|${r.subject}|${r.programFamily}`

// "English Reading" / "French Reading" — Literacy IPP confirms the type; the subject names which.
function subjectLabel(r: IPPRow): string {
  const fam = r.programFamily === 'French Immersion' ? 'French' : 'English'
  return `${fam} ${r.subject}`
}

type SortCol = 'name' | 'grade' | 'homeroom' | 'subject' | 'status'

export default function IPPManager({ rows }: { rows: IPPRow[] }) {
  // pending[key] = the unsaved value (true/false); absent = no change.
  const [pending, setPending] = useState<Record<string, boolean>>({})
  const [sortCol, setSortCol] = useState<SortCol>('name')
  const [asc, setAsc] = useState(true)
  const [busy, startTransition] = useTransition()
  const [result, setResult] = useState<IPPSaveResult | null>(null)

  const needCount = rows.filter((r) => r.isIPP === null).length
  const dirtyKeys = Object.keys(pending)

  function effective(r: IPPRow): boolean | null {
    const k = key(r)
    return k in pending ? pending[k] : r.isIPP
  }

  // Click a choice: revert if it matches the stored value, else stage the change.
  function choose(r: IPPRow, value: boolean) {
    const k = key(r)
    setPending((prev) => {
      const next = { ...prev }
      if (r.isIPP === value) delete next[k] // back to stored -> drop the pending change
      else next[k] = value
      return next
    })
  }

  function onSave() {
    const entries = dirtyKeys.map((k) => {
      const r = rows.find((x) => key(x) === k)!
      return { studentKey: r.studentKey, subject: r.subject, programFamily: r.programFamily, isIPP: pending[k] }
    })
    startTransition(async () => {
      const res = await saveStudentIPPs(entries)
      setResult(res)
      // Drop successfully-saved keys; revalidation refreshes rows with new stored values.
      const failed = new Set(res.errors.map((e) => e.studentKey))
      setPending((prev) => {
        const next = { ...prev }
        for (const k of dirtyKeys) {
          const r = rows.find((x) => key(x) === k)!
          if (!failed.has(r.studentKey)) delete next[k]
        }
        return next
      })
    })
  }

  const sorted = useMemo(() => {
    const dir = asc ? 1 : -1
    const statusRank = (r: IPPRow) => (effective(r) === null ? 0 : effective(r) ? 1 : 2)
    const copy = [...rows]
    copy.sort((a, b) => {
      let c = 0
      switch (sortCol) {
        case 'grade':
          c = (a.grade ?? '').localeCompare(b.grade ?? '')
          break
        case 'homeroom':
          c = (a.homeroom ?? '').localeCompare(b.homeroom ?? '')
          break
        case 'subject':
          c = subjectLabel(a).localeCompare(subjectLabel(b))
          break
        case 'status':
          c = statusRank(a) - statusRank(b)
          break
        default:
          c = `${a.lastName}${a.firstName}`.localeCompare(`${b.lastName}${b.firstName}`)
      }
      if (c === 0) c = `${a.lastName}${a.firstName}`.localeCompare(`${b.lastName}${b.firstName}`)
      return c * dir
    })
    return copy
    // effective() reads `pending`, so include it
  }, [rows, sortCol, asc, pending])

  function header(col: SortCol, label: string) {
    const active = sortCol === col
    return (
      <th
        className="sortable"
        onClick={() => {
          if (active) setAsc((a) => !a)
          else {
            setSortCol(col)
            setAsc(true)
          }
        }}
      >
        {label} {active ? (asc ? '↑' : '↓') : '↕'}
      </th>
    )
  }

  function statusText(r: IPPRow): { text: string; cls: string } {
    const k = key(r)
    if (k in pending) return { text: pending[k] ? 'Yes (pending)' : 'No (pending)', cls: 'ipp-status-pending' }
    if (r.isIPP === null) return { text: 'Needs confirmation', cls: 'ipp-status-need' }
    if (r.isIPP) return { text: 'Yes (IPP)', cls: 'ipp-status-yes' }
    return { text: 'No', cls: 'ipp-status-no' }
  }

  return (
    <>
      <div className="ipp-toolbar">
        <span className={needCount ? 'ipp-need-pill' : 'ipp-need-pill ipp-need-clear'}>
          {needCount} of {rows.length} still need confirmation
        </span>
        <span className="muted ipp-tip">Click a column heading to sort.</span>
      </div>

      <table className="grid">
        <thead>
          <tr>
            {header('name', 'Student')}
            {header('grade', 'Grade')}
            {header('homeroom', 'Homeroom')}
            {header('subject', 'IPP Subject')}
            {header('status', 'Status')}
            <th>Action</th>
          </tr>
        </thead>
        <tbody>
          {sorted.map((r) => {
            const eff = effective(r)
            const st = statusText(r)
            return (
              <tr key={key(r)}>
                <td>{r.lastName}, {r.firstName}</td>
                <td>{r.grade ?? '—'}</td>
                <td>{r.homeroom ?? '—'}</td>
                <td>{subjectLabel(r)}</td>
                <td className={st.cls}>{st.text}</td>
                <td>
                  <span className="ipp-seg">
                    <button
                      className={eff === true ? 'seg seg-yes-on' : 'seg'}
                      disabled={busy}
                      onClick={() => choose(r, true)}
                    >
                      Yes (Literacy IPP)
                    </button>
                    <button
                      className={eff === false ? 'seg seg-no-on' : 'seg'}
                      disabled={busy}
                      onClick={() => choose(r, false)}
                    >
                      No
                    </button>
                  </span>
                </td>
              </tr>
            )
          })}
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
