'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import type { ShortCycle, ShortCycleInstance } from '@/lib/data'
import { saveCycleHeader, saveShortCycle, type CycleInstanceInput } from './actions'

const SUBJECTS = ['Reading', 'Writing', 'Math'] as const
// Cycle program-scope buckets (match DimProgram.ScopeBucket). Non-immersion folds into English.
const PROGRAM_SCOPE = ['English', 'Early Immersion', 'Late Immersion'] as const
const GRADES = ['PP', 'P', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', 'RG']
const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
]
// Standard grade band per subject, prefilled when a new instance picks that subject (stays editable).
const SUBJECT_DEFAULT_GRADES: Record<string, { minGrade: string; maxGrade: string }> = {
  Reading: { minGrade: 'P', maxGrade: '8' },
  Writing: { minGrade: 'P', maxGrade: 'RG' },
  Math: { minGrade: 'P', maxGrade: '6' },
}

function gradeLabel(g: string): string {
  if (g === 'PP') return 'Pre-Primary'
  if (g === 'P') return 'Primary'
  if (g === 'RG') return 'Returning Grad'
  return `Grade ${g}`
}

function statusClass(status: string): string {
  switch (status) {
    case 'Open': return 'badge badge-open'
    case 'ClosesToday': return 'badge badge-closestoday'
    case 'Upcoming': return 'badge badge-upcoming'
    default: return 'badge badge-closed'
  }
}

// ---- form drafts ----
// graceDays + graceHours are the two UI fields; they compose to a single GraceHours total on save.
type HeaderDraft = { cycleGroupId: string | null; displayName: string; startDate: string; endDate: string; active: boolean; graceDays: number; graceHours: number }
type InstanceDraft = CycleInstanceInput & { key: string }
type InstancesDraft = { cycleGroupId: string; displayName: string; startDate: string; endDate: string; instances: InstanceDraft[] }

let keySeq = 0
function newKey(): string { return `i${keySeq++}` }

function toDraft(i: ShortCycleInstance): InstanceDraft {
  return {
    key: newKey(), existingId: i.id, subject: i.subject, language: i.language,
    programScope: [...i.programScope], minGrade: i.minGrade, maxGrade: i.maxGrade,
    benchmarkMonth: i.benchmarkMonth, active: i.active,
  }
}
function blankInstance(): InstanceDraft {
  return {
    key: newKey(), existingId: null, subject: 'Reading', language: null, programScope: [],
    ...SUBJECT_DEFAULT_GRADES.Reading, benchmarkMonth: null, active: true,
  }
}

function instanceSummary(c: ShortCycle) {
  const rows = c.instances.filter((i) => i.active)
  if (rows.length === 0) return <span className="muted">No instances yet</span>
  return (
    <div className="cycle-grade-cell">
      {rows.map((i) => (
        <div key={i.id}>
          {i.subject}{i.language ? ` · ${i.language}` : ''} · {i.programScope.length ? i.programScope.join('/') : 'All'} · {i.minGrade}–{i.maxGrade}
        </div>
      ))}
    </div>
  )
}

export default function ShortCyclesManager({ initialCycles }: { initialCycles: ShortCycle[] }) {
  const router = useRouter()
  const [headerForm, setHeaderForm] = useState<HeaderDraft | null>(null)
  const [instForm, setInstForm] = useState<InstancesDraft | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()

  function run(fn: () => Promise<void>) {
    setError(null)
    startTransition(async () => {
      try { await fn(); router.refresh() } catch (e) { setError(e instanceof Error ? e.message : String(e)) }
    })
  }

  // ---- header ----
  function submitHeader(f: HeaderDraft) {
    if (!f.displayName.trim()) { setError('Cycle name is required.'); return }
    if (!f.startDate || !f.endDate) { setError('Start and end dates are required.'); return }
    if (f.endDate < f.startDate) { setError('End date must be on or after the start date.'); return }
    run(async () => {
      // Compose the two UI fields into the single stored GraceHours total (days*24 + hours).
      const graceHours = Math.max(0, Math.trunc(f.graceDays) * 24 + Math.trunc(f.graceHours))
      const id = await saveCycleHeader({
        cycleGroupId: f.cycleGroupId, displayName: f.displayName, startDate: f.startDate,
        endDate: f.endDate, active: f.active, graceHours,
      })
      setHeaderForm(null)
      // Jump straight into managing this cycle's instances (dates now established).
      const existing = initialCycles.find((c) => c.cycleGroupId === id)
      setInstForm({
        cycleGroupId: id, displayName: f.displayName.trim(), startDate: f.startDate, endDate: f.endDate,
        instances: existing ? existing.instances.map(toDraft) : [],
      })
    })
  }

  // ---- instances ----
  function manageInstances(c: ShortCycle) {
    setError(null)
    setInstForm({
      cycleGroupId: c.cycleGroupId, displayName: c.displayName, startDate: c.startDate, endDate: c.endDate,
      instances: c.instances.map(toDraft),
    })
  }
  function patchInstance(key: string, patch: Partial<InstanceDraft>) {
    if (!instForm) return
    setInstForm({ ...instForm, instances: instForm.instances.map((i) => (i.key === key ? { ...i, ...patch } : i)) })
  }
  function setInstanceSubject(key: string, subject: string) {
    const band = SUBJECT_DEFAULT_GRADES[subject] ?? { minGrade: 'PP', maxGrade: '12' }
    patchInstance(key, { subject, ...band, ...(subject === 'Math' ? { language: null } : {}) })
  }
  function toggleInstanceScope(key: string, bucket: string) {
    const inst = instForm?.instances.find((i) => i.key === key)
    if (!inst) return
    const has = inst.programScope.includes(bucket)
    patchInstance(key, { programScope: has ? inst.programScope.filter((b) => b !== bucket) : [...inst.programScope, bucket] })
  }
  function removeInstance(key: string) {
    if (!instForm) return
    const inst = instForm.instances.find((i) => i.key === key)
    if (!inst) return
    if (inst.existingId) patchInstance(key, { active: false }) // keep the row; deactivate on save
    else setInstForm({ ...instForm, instances: instForm.instances.filter((i) => i.key !== key) }) // drop unsaved
  }
  function addInstance() {
    if (!instForm) return
    setInstForm({ ...instForm, instances: [...instForm.instances, blankInstance()] })
  }
  function submitInstances(f: InstancesDraft) {
    for (const i of f.instances) {
      if (GRADES.indexOf(i.minGrade) > GRADES.indexOf(i.maxGrade)) { setError(`${i.subject}: min grade must be at or below max grade.`); return }
    }
    run(async () => {
      await saveShortCycle({
        cycleGroupId: f.cycleGroupId, displayName: f.displayName, startDate: f.startDate, endDate: f.endDate,
        instances: f.instances.map(({ key, ...rest }) => rest),
      })
      setInstForm(null)
    })
  }

  return (
    <>
      <div className="cycles-toolbar">
        <button className="btn-primary" disabled={pending}
                onClick={() => { setError(null); setInstForm(null); setHeaderForm({ cycleGroupId: null, displayName: '', startDate: '', endDate: '', active: true, graceDays: 7, graceHours: 0 }) }}>
          + New cycle
        </button>
      </div>

      {pending && <div className="loading"><span className="spinner" />Saving changes…</div>}
      {error && <div className="notice notice-error">{error}</div>}

      {/* ---- Cycle header form (name + dates only) ---- */}
      {headerForm && (
        <div className="cycle-form">
          <h2 className="section-title">{headerForm.cycleGroupId ? 'Edit cycle dates' : 'New cycle'}</h2>
          <p className="cycle-form-hint">Set the display name and date range once. You’ll add the scoped
            assessment instances (subject · language · program · grades) next — they all share these dates.</p>
          <div className="cycle-form-grid">
            <label>Cycle name
              <input type="text" value={headerForm.displayName} placeholder="e.g. SCoR 1"
                     onChange={(e) => setHeaderForm({ ...headerForm, displayName: e.target.value })} />
            </label>
            <label>Start date
              <input type="date" value={headerForm.startDate}
                     onChange={(e) => setHeaderForm({ ...headerForm, startDate: e.target.value })} />
            </label>
            <label>End date
              <input type="date" value={headerForm.endDate}
                     onChange={(e) => setHeaderForm({ ...headerForm, endDate: e.target.value })} />
            </label>
            {/* Late-entry grace: how long AFTER the end date the cycle stays editable before it locks
                to read-only. Two fields for a friendly compose; saved as one total in hours. */}
            <label>Grace after close · days
              <input type="number" min={0} step={1} value={headerForm.graceDays}
                     onChange={(e) => setHeaderForm({ ...headerForm, graceDays: Math.max(0, Math.trunc(Number(e.target.value) || 0)) })} />
            </label>
            <label>Grace · hours
              <input type="number" min={0} max={23} step={1} value={headerForm.graceHours}
                     onChange={(e) => setHeaderForm({ ...headerForm, graceHours: Math.max(0, Math.trunc(Number(e.target.value) || 0)) })} />
            </label>
            <label className="cycle-form-check">
              <input type="checkbox" checked={headerForm.active}
                     onChange={(e) => setHeaderForm({ ...headerForm, active: e.target.checked })} />
              Active
            </label>
          </div>
          <div className="cycle-form-actions">
            <button className="btn-primary" disabled={pending} onClick={() => submitHeader(headerForm)}>
              {pending ? 'Saving…' : (headerForm.cycleGroupId ? 'Save dates' : 'Create cycle & add instances')}
            </button>
            <button className="btn-ghost" disabled={pending} onClick={() => { setHeaderForm(null); setError(null) }}>Cancel</button>
          </div>
        </div>
      )}

      {/* ---- Instance builder (a list of scoped instances under one cycle) ---- */}
      {instForm && (
        <div className="cycle-form">
          <h2 className="section-title">Instances · {instForm.displayName}
            <span className="muted"> ({instForm.startDate} → {instForm.endDate})</span>
          </h2>
          <p className="cycle-form-hint">Each instance is one scoped assessment. Add as many as the cycle needs
            (e.g. Reading · French · Early Immersion · P–8). Dates come from the cycle header (edit them there).</p>

          <div className="cycle-instances">
            {instForm.instances.length === 0 && <span className="muted">No instances yet — add one below.</span>}
            {instForm.instances.map((inst) => (
              <div key={inst.key} className="cycle-instance-row" style={inst.active ? undefined : { opacity: 0.5 }}>
                <select value={inst.subject} onChange={(e) => setInstanceSubject(inst.key, e.target.value)}>
                  {SUBJECTS.map((s) => <option key={s} value={s}>{s}</option>)}
                </select>
                {inst.subject !== 'Math' ? (
                  <select value={inst.language ?? ''} onChange={(e) => patchInstance(inst.key, { language: e.target.value || null })}>
                    <option value="">Both</option>
                    <option value="English">English</option>
                    <option value="French">French</option>
                  </select>
                ) : <span className="muted cycle-inst-na">—</span>}
                <span className="cycle-inst-scope">
                  {PROGRAM_SCOPE.map((b) => (
                    <label key={b} title={b}>
                      <input type="checkbox" checked={inst.programScope.includes(b)} onChange={() => toggleInstanceScope(inst.key, b)} />
                      {b === 'English' ? 'Eng' : b === 'Early Immersion' ? 'Early' : 'Late'}
                    </label>
                  ))}
                </span>
                <select value={inst.minGrade} onChange={(e) => patchInstance(inst.key, { minGrade: e.target.value })}>
                  {GRADES.map((g) => <option key={g} value={g}>{gradeLabel(g)}</option>)}
                </select>
                <span className="cycle-grade-dash">to</span>
                <select value={inst.maxGrade} onChange={(e) => patchInstance(inst.key, { maxGrade: e.target.value })}>
                  {GRADES.map((g) => <option key={g} value={g}>{gradeLabel(g)}</option>)}
                </select>
                {inst.subject === 'Reading' ? (
                  <select value={inst.benchmarkMonth ?? ''} title="Benchmark month (reading)"
                          onChange={(e) => patchInstance(inst.key, { benchmarkMonth: e.target.value ? Number(e.target.value) : null })}>
                    <option value="">Auto</option>
                    {MONTHS.map((m, i) => <option key={m} value={i + 1}>{m.slice(0, 3)}</option>)}
                  </select>
                ) : <span className="cycle-inst-na" />}
                <button className="btn-ghost cycle-inst-remove" disabled={pending} onClick={() => removeInstance(inst.key)}>
                  {inst.active ? 'Remove' : 'Removed'}
                </button>
              </div>
            ))}
          </div>

          <div className="cycle-form-actions">
            <button className="btn-ghost" disabled={pending} onClick={addInstance}>+ Add instance</button>
            <button className="btn-primary" disabled={pending} onClick={() => submitInstances(instForm)}>
              {pending ? 'Saving…' : 'Save instances'}
            </button>
            <button className="btn-ghost" disabled={pending} onClick={() => { setInstForm(null); setError(null) }}>Close</button>
          </div>
        </div>
      )}

      {/* ---- Cycle list ---- */}
      {initialCycles.length === 0 ? (
        <div className="notice notice-empty">
          <div className="notice-title">No cycles defined yet.</div>
          <div>Create the first cycle above (name + dates), then add its assessment instances.</div>
        </div>
      ) : (
        <table className="grid cycles-grid">
          <thead>
            <tr><th>Cycle</th><th>Dates</th><th>Instances</th><th>Status</th><th></th></tr>
          </thead>
          <tbody>
            {initialCycles.map((c) => (
              <tr key={c.cycleGroupId} style={c.active ? undefined : { opacity: 0.5 }}>
                <td>{c.displayName}{!c.active && <span className="muted"> (inactive)</span>}</td>
                <td className="muted"><div className="cycle-dates"><span>{c.startDate}</span><span>{c.endDate}</span></div></td>
                <td className="muted">{instanceSummary(c)}</td>
                <td><span className={statusClass(c.status)}>{c.status}</span></td>
                <td className="cycle-row-actions">
                  <button className="btn-ghost" disabled={pending} onClick={() => manageInstances(c)}>Instances</button>
                  <button className="btn-ghost" disabled={pending}
                          onClick={() => { setError(null); setInstForm(null); setHeaderForm({ cycleGroupId: c.cycleGroupId, displayName: c.displayName, startDate: c.startDate, endDate: c.endDate, active: c.active, graceDays: Math.floor((c.graceHours ?? 168) / 24), graceHours: (c.graceHours ?? 168) % 24 }) }}>
                    Edit dates
                  </button>
                  <button className="btn-ghost" disabled={pending}
                          onClick={() => run(() => saveCycleHeader({ cycleGroupId: c.cycleGroupId, displayName: c.displayName, startDate: c.startDate, endDate: c.endDate, active: !c.active }).then(() => {}))}>
                    {c.active ? 'Deactivate' : 'Activate'}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  )
}
