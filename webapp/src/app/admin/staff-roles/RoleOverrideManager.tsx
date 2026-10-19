'use client'

import { useState, useTransition } from 'react'
import { setRoleOverride, findStaff } from './actions'
import { OVERRIDE_ROLES, type OverrideRole } from './constants'
import type { StaffRoleOverrideRow } from '@/lib/data'

// Friendly labels for the three role tiers (the stored codes are terse).
const ROLE_LABEL: Record<OverrideRole, string> = {
  Administrator: 'Administrator',
  RegionalAnalyst: 'Regional Analyst',
  SpecialistTeacher: 'Specialist Teacher',
}

export default function RoleOverrideManager({ overrides }: { overrides: StaffRoleOverrideRow[] }) {
  const [rows, setRows] = useState<StaffRoleOverrideRow[]>(overrides)
  const [dirty, setDirty] = useState<Record<string, boolean>>({})
  const [saveSummary, setSaveSummary] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()
  const [filter, setFilter] = useState('')
  const [addEmail, setAddEmail] = useState('')
  const [addMsg, setAddMsg] = useState<string | null>(null)
  // Explicit "don't search" choice — add an email that isn't a current staff record (e.g. a coach already
  // excluded from active staff, or someone not yet in PowerSchool). Off by default so a typo is caught.
  const [addExternal, setAddExternal] = useState(false)

  function addStaff() {
    const email = addEmail.trim()
    if (!email) return
    if (rows.some((r) => r.email.toLowerCase() === email.toLowerCase())) {
      setAddMsg('That staff member is already in the list.')
      return
    }
    setAddMsg(null)
    startTransition(async () => {
      const res = await findStaff(email, addExternal)
      if (!res.ok || !res.staff) {
        setAddMsg(res.message ?? 'Not found.')
        return
      }
      const s = res.staff
      if (rows.some((r) => r.email.toLowerCase() === s.email.toLowerCase())) {
        setAddMsg('That staff member is already in the list.')
        return
      }
      const newRow: StaffRoleOverrideRow = {
        email: s.email,
        name: s.name,
        overrideRole: 'Administrator', // sensible default (the coach case); change before Save
        notes: null,
        active: true,
      }
      setRows((rs) => [newRow, ...rs])
      setDirty((d) => ({ ...d, [s.email]: true }))
      setAddEmail('')
      setAddExternal(false)
      setAddMsg(
        res.known
          ? `Added ${s.name} — set their role and click Save.`
          : `Added ${s.email} (not a current staff record) — set their role and click Save.`,
      )
    })
  }

  function patch(email: string, patch: Partial<StaffRoleOverrideRow>) {
    setRows((rs) => rs.map((r) => (r.email === email ? { ...r, ...patch } : r)))
    setDirty((d) => ({ ...d, [email]: true }))
    setSaveSummary(null)
  }

  const dirtyRows = rows.filter((r) => dirty[r.email])

  function saveAll() {
    if (dirtyRows.length === 0) return
    const activating = dirtyRows.filter((r) => r.active)
    const retiring = dirtyRows.filter((r) => !r.active)
    // Overrides are applied by the staff merge, so nothing changes until the next data ingest — which is
    // also when each person's school-level access is derived from PowerSchool and can be verified. Make
    // that explicit before saving so no one expects access to appear immediately.
    let msg =
      'Role override changes take effect on the NEXT data ingest — that is when each person’s school-level ' +
      'access is derived from PowerSchool and can be verified. They are not effective immediately.'
    if (activating.length > 0) {
      msg += `\n\nApplying: ${activating.map((r) => `${r.name} → ${r.overrideRole}`).join(', ')}.`
    }
    if (retiring.length > 0) {
      msg += `\n\nRetiring (revert to their PowerSchool role): ${retiring.map((r) => r.name).join(', ')}.`
    }
    msg += '\n\nSave these changes?'
    if (!confirm(msg)) return
    setSaveSummary(null)
    startTransition(async () => {
      let saved = 0
      const errs: string[] = []
      for (const r of dirtyRows) {
        const res = await setRoleOverride({
          email: r.email,
          overrideRole: r.overrideRole as OverrideRole,
          notes: r.notes,
          active: r.active,
        })
        if (res.ok) {
          saved++
          setDirty((d) => {
            const n = { ...d }
            delete n[r.email]
            return n
          })
        } else {
          errs.push(`${r.name}: ${res.message ?? 'failed'}`)
        }
      }
      setSaveSummary(
        errs.length ? `Saved ${saved} · ${errs.length} failed — ${errs.join('; ')}` : `Saved ${saved}`,
      )
    })
  }

  const shown = rows.filter(
    (r) => !filter || r.name.toLowerCase().includes(filter.toLowerCase()) || r.email.toLowerCase().includes(filter.toLowerCase()),
  )

  return (
    <>
      <p className="muted small" style={{ margin: '0 0 1rem' }}>
        An override changes only the staff member&apos;s <strong>role classification</strong>. Their school scope still
        derives from PowerSchool (their home / changeable schools), and it takes effect on the next ingest.
      </p>
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
            <th>Override role</th>
            <th>Notes</th>
            <th style={{ textAlign: 'center' }}>Active</th>
          </tr>
        </thead>
        <tbody>
          {shown.map((r) => (
            <tr key={r.email} className={dirty[r.email] ? 'row-dirty' : undefined}>
              <td>
                {r.name}
                <br />
                <span className="muted small">{r.email}</span>
              </td>
              <td>
                <select
                  value={r.overrideRole}
                  disabled={pending}
                  aria-label={`Override role for ${r.name}`}
                  onChange={(e) => patch(r.email, { overrideRole: e.target.value })}
                >
                  {OVERRIDE_ROLES.map((role) => (
                    <option key={role} value={role}>
                      {ROLE_LABEL[role]}
                    </option>
                  ))}
                </select>
              </td>
              <td>
                <input
                  type="text"
                  value={r.notes ?? ''}
                  placeholder="e.g. Instructional Coach"
                  disabled={pending}
                  aria-label={`Notes for ${r.name}`}
                  onChange={(e) => patch(r.email, { notes: e.target.value })}
                  style={{ padding: '0.4rem 0.6rem', width: 'min(240px, 100%)' }}
                />
              </td>
              <td style={{ textAlign: 'center' }}>
                <input
                  type="checkbox"
                  checked={r.active}
                  disabled={pending}
                  aria-label={`Active for ${r.name}`}
                  onChange={(e) => patch(r.email, { active: e.target.checked })}
                />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {rows.length === 0 ? (
        <p className="muted">No role overrides yet. Add someone by email below.</p>
      ) : (
        <p className="muted small" style={{ marginTop: '0.75rem' }}>
          Tip: to stop an override, uncheck <strong>Active</strong> and Save — the person reverts to their PowerSchool role.
        </p>
      )}
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
        <div style={{ marginLeft: 'auto', display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
          {saveSummary ? <span className="save-result">{saveSummary}</span> : null}
          <button className="btn" onClick={saveAll} disabled={pending || dirtyRows.length === 0}>
            {pending ? 'Saving…' : dirtyRows.length ? `Save ${dirtyRows.length} change(s)` : 'Save'}
          </button>
        </div>
      </div>
    </>
  )
}
