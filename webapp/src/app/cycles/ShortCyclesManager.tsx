'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import type { ShortCycle } from '@/lib/data'
import { saveShortCycle, setShortCycleActive, type ShortCycleInput } from './actions'

const SUBJECTS = ['Reading', 'Writing', 'Math'] as const
const GRADES = ['PP', 'P', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12']
const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
]

function blankForm(): ShortCycleInput {
  return {
    id: null,
    assessmentType: 'Reading',
    cycleName: '',
    startDate: '',
    endDate: '',
    minGrade: 'PP',
    maxGrade: '12',
    benchmarkMonth: null,
    active: true,
  }
}

function toForm(c: ShortCycle): ShortCycleInput {
  return {
    id: c.id,
    assessmentType: c.assessmentType,
    cycleName: c.name,
    startDate: c.startDate,
    endDate: c.endDate,
    minGrade: c.minGrade,
    maxGrade: c.maxGrade,
    benchmarkMonth: c.benchmarkMonth,
    active: c.active,
  }
}

function statusClass(status: string): string {
  switch (status) {
    case 'Open': return 'badge badge-open'
    case 'ClosesToday': return 'badge badge-closestoday'
    case 'Upcoming': return 'badge badge-upcoming'
    default: return 'badge badge-closed'
  }
}

export default function ShortCyclesManager({ initialCycles }: { initialCycles: ShortCycle[] }) {
  const router = useRouter()
  const [form, setForm] = useState<ShortCycleInput | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()

  function validate(f: ShortCycleInput): string | null {
    if (!f.cycleName.trim()) return 'Cycle name is required.'
    if (!f.startDate || !f.endDate) return 'Start and end dates are required.'
    if (f.endDate < f.startDate) return 'End date must be on or after the start date.'
    if (GRADES.indexOf(f.minGrade) > GRADES.indexOf(f.maxGrade)) return 'Min grade must be at or below max grade.'
    return null
  }

  function submit(f: ShortCycleInput) {
    const v = validate(f)
    if (v) { setError(v); return }
    setError(null)
    startTransition(async () => {
      try {
        await saveShortCycle(f)
        setForm(null)
        router.refresh()
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e))
      }
    })
  }

  function toggleActive(c: ShortCycle) {
    setError(null)
    startTransition(async () => {
      try {
        await setShortCycleActive(toForm(c), !c.active)
        router.refresh()
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e))
      }
    })
  }

  const isReading = form?.assessmentType === 'Reading'

  return (
    <>
      <div className="cycles-toolbar">
        <button className="btn-primary" disabled={pending} onClick={() => { setError(null); setForm(blankForm()) }}>
          + New cycle
        </button>
      </div>

      {error && <div className="notice notice-error">{error}</div>}

      {form && (
        <div className="cycle-form">
          <h2 className="section-title">{form.id ? 'Edit cycle' : 'New cycle'}</h2>
          <div className="cycle-form-grid">
            <label>Subject
              <select value={form.assessmentType}
                      onChange={(e) => setForm({ ...form, assessmentType: e.target.value })}>
                {SUBJECTS.map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
            </label>
            <label>Cycle name
              <input type="text" value={form.cycleName} placeholder="e.g. Cycle 1 – Fall Reading"
                     onChange={(e) => setForm({ ...form, cycleName: e.target.value })} />
            </label>
            <label>Start date
              <input type="date" value={form.startDate}
                     onChange={(e) => setForm({ ...form, startDate: e.target.value })} />
            </label>
            <label>End date
              <input type="date" value={form.endDate}
                     onChange={(e) => setForm({ ...form, endDate: e.target.value })} />
            </label>
            <label>Min grade
              <select value={form.minGrade} onChange={(e) => setForm({ ...form, minGrade: e.target.value })}>
                {GRADES.map((g) => <option key={g} value={g}>{g}</option>)}
              </select>
            </label>
            <label>Max grade
              <select value={form.maxGrade} onChange={(e) => setForm({ ...form, maxGrade: e.target.value })}>
                {GRADES.map((g) => <option key={g} value={g}>{g}</option>)}
              </select>
            </label>
            {isReading && (
              <label>Benchmark month
                <select value={form.benchmarkMonth ?? ''}
                        onChange={(e) => setForm({ ...form, benchmarkMonth: e.target.value ? Number(e.target.value) : null })}>
                  <option value="">Auto (dominant month)</option>
                  {MONTHS.map((m, i) => <option key={m} value={i + 1}>{m}</option>)}
                </select>
              </label>
            )}
            <label className="cycle-form-check">
              <input type="checkbox" checked={form.active}
                     onChange={(e) => setForm({ ...form, active: e.target.checked })} />
              Active
            </label>
          </div>
          {isReading && (
            <p className="cycle-form-hint">
              Reading levels are scored on each student’s program scale (English → EN, French Immersion → FR).
              Benchmark month sets which grade-month expectation applies; leave on Auto to use the cycle’s
              dominant month.
            </p>
          )}
          <div className="cycle-form-actions">
            <button className="btn-primary" disabled={pending} onClick={() => submit(form)}>
              {pending ? 'Saving…' : 'Save cycle'}
            </button>
            <button className="btn-ghost" disabled={pending} onClick={() => { setForm(null); setError(null) }}>
              Cancel
            </button>
          </div>
        </div>
      )}

      {initialCycles.length === 0 ? (
        <div className="notice notice-empty">
          <div className="notice-title">No cycles defined yet.</div>
          <div>Create the first Short Cycle of Response above so teachers have somewhere to enter results.</div>
        </div>
      ) : (
        <table className="grid">
          <thead>
            <tr>
              <th>Cycle</th>
              <th>Subject</th>
              <th>Dates</th>
              <th>Grades</th>
              <th>Benchmark</th>
              <th>Status</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {initialCycles.map((c) => (
              <tr key={c.id} style={c.active ? undefined : { opacity: 0.5 }}>
                <td>{c.name}{!c.active && <span className="muted"> (inactive)</span>}</td>
                <td>{c.assessmentType}</td>
                <td className="muted">{c.startDate} → {c.endDate}</td>
                <td className="muted">{c.minGrade}–{c.maxGrade}</td>
                <td className="muted">
                  {c.assessmentType === 'Reading'
                    ? (c.benchmarkMonth ? MONTHS[c.benchmarkMonth - 1] : 'Auto')
                    : '—'}
                </td>
                <td><span className={statusClass(c.status)}>{c.status}</span></td>
                <td className="cycle-row-actions">
                  <button className="btn-ghost" disabled={pending}
                          onClick={() => { setError(null); setForm(toForm(c)) }}>Edit</button>
                  <button className="btn-ghost" disabled={pending}
                          onClick={() => toggleActive(c)}>{c.active ? 'Deactivate' : 'Activate'}</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  )
}
