'use client'

import { useState, useTransition } from 'react'
import { setStaffAccess, findStaff } from './actions'
import type { StaffAccessRow } from '@/lib/data'

// Capability columns, in display order. IsSysAdmin is special (implies all the rest).
const CAPS: { key: keyof StaffAccessRow; label: string }[] = [
  { key: 'isSysAdmin', label: 'Sysadmin' },
  { key: 'canManageCycles', label: 'Manage Cycles' },
  { key: 'canRunIngest', label: 'Run Ingest' },
  { key: 'canOverrideMath', label: 'Math Override' },
  { key: 'canOverrideLiteracy', label: 'Literacy Override' },
]

export default function StaffAccessManager({ staff, selfUpn }: { staff: StaffAccessRow[]; selfUpn: string }) {
  const [rows, setRows] = useState<StaffAccessRow[]>(staff)
  const [dirty, setDirty] = useState<Record<string, boolean>>({})
  const [saved, setSaved] = useState<Record<string, string>>({}) // email -> 'Saved' | error message
  const [busyEmail, setBusyEmail] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()
  const [filter, setFilter] = useState('')
  // "Add staff by email" — looks the email up in DimStaff, then adds an all-false row the sysadmin
  // toggles + Saves (the DB row is created on that first Save, not on add).
  const [addEmail, setAddEmail] = useState('')
  const [addMsg, setAddMsg] = useState<string | null>(null)

  function addStaff() {
    const email = addEmail.trim()
    if (!email) return
    if (rows.some((r) => r.email.toLowerCase() === email.toLowerCase())) {
      setAddMsg('That staff member is already in the list.')
      return
    }
    setAddMsg(null)
    startTransition(async () => {
      const res = await findStaff(email)
      if (!res.ok || !res.staff) {
        setAddMsg(res.message ?? 'Not found.')
        return
      }
      const s = res.staff
      if (rows.some((r) => r.email.toLowerCase() === s.email.toLowerCase())) {
        setAddMsg('That staff member is already in the list.')
        return
      }
      const newRow: StaffAccessRow = {
        email: s.email,
        name: s.name,
        isSysAdmin: false,
        canManageCycles: false,
        canRunIngest: false,
        canOverrideMath: false,
        canOverrideLiteracy: false,
      }
      setRows((rs) => [newRow, ...rs]) // top of the list so it's visible
      setDirty((d) => ({ ...d, [s.email]: true })) // dirty -> Save enabled; Save creates the DB row
      setAddEmail('')
      setAddMsg(`Added ${s.name} — set their roles and click Save.`)
    })
  }

  // The saved-on-server value (to detect a NEW sysadmin grant for the confirm prompt).
  const original = new Map(staff.map((s) => [s.email, s] as const))

  function patch(email: string, key: keyof StaffAccessRow, val: boolean) {
    setRows((rs) => rs.map((r) => (r.email === email ? { ...r, [key]: val } : r)))
    setDirty((d) => ({ ...d, [email]: true }))
    setSaved((s) => {
      const n = { ...s }
      delete n[email]
      return n
    })
  }

  function save(r: StaffAccessRow) {
    // Confirm before minting a NEW sysadmin (they can then change everyone's access).
    if (r.isSysAdmin && !original.get(r.email)?.isSysAdmin) {
      if (!confirm(`Grant System Administrator to ${r.name}? They will be able to change everyone's access, including yours.`)) return
    }
    setBusyEmail(r.email)
    startTransition(async () => {
      const res = await setStaffAccess({
        email: r.email,
        isSysAdmin: r.isSysAdmin,
        canManageCycles: r.canManageCycles,
        canRunIngest: r.canRunIngest,
        canOverrideMath: r.canOverrideMath,
        canOverrideLiteracy: r.canOverrideLiteracy,
      })
      setBusyEmail(null)
      if (res.ok) {
        setDirty((d) => {
          const n = { ...d }
          delete n[r.email]
          return n
        })
        setSaved((s) => ({ ...s, [r.email]: 'Saved' }))
      } else {
        setSaved((s) => ({ ...s, [r.email]: res.message ?? 'Failed' }))
      }
    })
  }

  const shown = rows.filter(
    (r) => !filter || r.name.toLowerCase().includes(filter.toLowerCase()) || r.email.toLowerCase().includes(filter.toLowerCase()),
  )

  return (
    <>
      <input
        type="text"
        placeholder="Filter by name or email…"
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
        style={{ margin: '0 0 1rem', padding: '0.5rem 0.75rem', width: 'min(360px, 100%)' }}
      />
      <table className="grid">
        <thead>
          <tr>
            <th>Staff</th>
            {CAPS.map((c) => (
              <th key={c.key} style={{ textAlign: 'center' }}>
                {c.label}
              </th>
            ))}
            <th></th>
          </tr>
        </thead>
        <tbody>
          {shown.map((r) => {
            const isSelf = r.email.toLowerCase() === selfUpn.toLowerCase()
            return (
              <tr key={r.email} className={dirty[r.email] ? 'row-dirty' : undefined}>
                <td>
                  {r.name}
                  <br />
                  <span className="muted small">{r.email}</span>
                </td>
                {CAPS.map((c) => {
                  const isSys = c.key === 'isSysAdmin'
                  // Sysadmin implies every other capability -> show them checked + locked when sysadmin is on.
                  // Can't revoke your OWN sysadmin here (prevents locking yourself out).
                  const checked = isSys ? r.isSysAdmin : r.isSysAdmin || (r[c.key] as boolean)
                  const disabled = pending || (isSys ? isSelf : r.isSysAdmin)
                  return (
                    <td key={c.key} style={{ textAlign: 'center' }}>
                      <input
                        type="checkbox"
                        checked={checked}
                        disabled={disabled}
                        aria-label={`${c.label} for ${r.name}`}
                        onChange={(e) => patch(r.email, c.key, e.target.checked)}
                      />
                    </td>
                  )
                })}
                <td>
                  <button className="btn" disabled={!dirty[r.email] || (pending && busyEmail === r.email)} onClick={() => save(r)}>
                    {pending && busyEmail === r.email ? 'Saving…' : 'Save'}
                  </button>
                  {saved[r.email] ? <span className="save-result"> {saved[r.email]}</span> : null}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
      {rows.length === 0 ? (
        <p className="muted">No staff have been granted access yet. Add someone by email below.</p>
      ) : null}
      <div style={{ marginTop: '1.25rem', display: 'flex', gap: '0.5rem', alignItems: 'center', flexWrap: 'wrap' }}>
        <input
          type="email"
          placeholder="Add staff by email…"
          value={addEmail}
          onChange={(e) => {
            setAddEmail(e.target.value)
            setAddMsg(null)
          }}
          onKeyDown={(e) => {
            if (e.key === 'Enter') addStaff()
          }}
          style={{ padding: '0.5rem 0.75rem', width: 'min(320px, 100%)' }}
        />
        <button className="btn" onClick={addStaff} disabled={pending || !addEmail.trim()}>
          Add
        </button>
        {addMsg ? <span className="muted small">{addMsg}</span> : null}
      </div>
    </>
  )
}
