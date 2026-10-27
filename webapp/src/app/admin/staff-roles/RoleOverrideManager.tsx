'use client'

import { useState, useTransition } from 'react'
import { setRoleOverride, findStaff } from './actions'
import { OVERRIDE_ROLES, type OverrideRole } from './constants'
import type { StaffRoleOverrideRow } from '@/lib/data'

// Friendly labels for the override roles (the stored codes are terse).
const ROLE_LABEL: Record<OverrideRole, string> = {
  Administrator: 'Administrator',
  RegionalAnalyst: 'Regional Analyst',
  SpecialistTeacher: 'Specialist Teacher',
  Maintenance: 'Tech Services (Maintenance)',
}

export default function RoleOverrideManager({ overrides }: { overrides: StaffRoleOverrideRow[] }) {
  const [rows, setRows] = useState<StaffRoleOverrideRow[]>(overrides)
  const [dirty, setDirty] = useState<Record<string, boolean>>({})
  const [saveSummary, setSaveSummary] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()
  const [filter, setFilter] = useState('')
  const [addEmail, setAddEmail] = useState('')
  const [addMsg, setAddMsg] = useState<string | null>(null)
  // Per-row notes returned by the last Save (migration: "…now on the Staff Access list"; held: "…not in
  // PowerSchool yet, applies at the next ingest").
  const [saveNotes, setSaveNotes] = useState<string[]>([])
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
    // Saving provisions each person in place: someone already in the PowerSchool data takes effect at
    // once; Tech Services (Maintenance) always works at once (it gets a logging identity even when not in
    // PS); a data-access override for someone NOT yet in PowerSchool is saved and applied at the next
    // ingest. Make that explicit before saving.
    let msg =
      'Saving applies each override immediately for anyone already in the PowerSchool data. Tech Services ' +
      '(Maintenance) always takes effect at once (capability only — no student data). A data-access ' +
      'override for someone not yet in PowerSchool is saved and applied at the next ingest.'
    if (activating.length > 0) {
      msg += `\n\nApplying: ${activating.map((r) => `${r.name} → ${ROLE_LABEL[r.overrideRole as OverrideRole] ?? r.overrideRole}`).join(', ')}.`
    }
    if (retiring.length > 0) {
      msg += `\n\nRetiring (access revoked now; reverts to their PowerSchool role): ${retiring.map((r) => r.name).join(', ')}.`
    }
    msg += '\n\nSave these changes?'
    if (!confirm(msg)) return
    setSaveSummary(null)
    setSaveNotes([])
    startTransition(async () => {
      let saved = 0
      const errs: string[] = []
      const notes: string[] = []
      for (const r of dirtyRows) {
        const res = await setRoleOverride({
          email: r.email,
          overrideRole: r.overrideRole as OverrideRole,
          notes: r.notes,
          active: r.active,
        })
        if (res.ok) {
          saved++
          if (res.note) notes.push(res.note)
          setDirty((d) => {
            const n = { ...d }
            delete n[r.email]
            return n
          })
          // A migrated row (Maintenance found in PS) has left this list — drop it from the grid.
          if (res.migrated) setRows((rs) => rs.filter((x) => x.email !== r.email))
        } else {
          errs.push(`${r.name}: ${res.message ?? 'failed'}`)
        }
      }
      setSaveNotes(notes)
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
        An override changes only the staff member&apos;s <strong>role classification</strong>; their school scope still
        derives from PowerSchool (their home / changeable schools). <strong>Saving applies it immediately</strong> for
        anyone already in the PowerSchool data. <strong>Tech Services (Maintenance)</strong> is a capability-only
        override — it grants the maintenance flag and a logging identity at once, with no student data. Someone not yet
        in PowerSchool is saved and picked up at the next ingest (Maintenance works right away; a coach waits to be matched).
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
      <label className="muted small" style={{ display: 'flex', gap: '0.4rem', alignItems: 'center', marginTop: '0.5rem' }}>
        <input
          type="checkbox"
          checked={addExternal}
          disabled={pending}
          onChange={(e) => {
            setAddExternal(e.target.checked)
            setAddMsg(null)
          }}
        />
        This person isn’t in the system yet (skip the staff lookup — for Instructional Coaches and others not yet in PowerSchool)
      </label>

      {/* Notes the last Save returned: a migration ("…now on the Staff Access list") or a held
          ("…not in PowerSchool yet, applies at the next ingest") message, per affected person. */}
      {saveNotes.length > 0 ? (
        <ul className="save-result" style={{ marginTop: '0.75rem', paddingLeft: '1.25rem' }}>
          {saveNotes.map((n, i) => (
            <li key={i}>{n}</li>
          ))}
        </ul>
      ) : null}
    </>
  )
}
