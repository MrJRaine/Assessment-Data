'use client'

import { useState, useTransition } from 'react'
import { setStaffAccess } from './actions'
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
    </>
  )
}
