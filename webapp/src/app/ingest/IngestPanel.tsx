'use client'

import { useEffect, useRef, useState, useTransition } from 'react'
import {
  uploadIngestFile,
  runIngestCycle,
  scheduleIngestMaintenance,
  type UploadResult,
  type RunResult,
  type NoticeResult,
} from './actions'
import { INGEST_NOTICE_MINUTES } from './constants'

const TOPICS: { topic: string; label: string }[] = [
  { topic: 'students', label: 'Students' },
  { topic: 'staff', label: 'Staff' },
  { topic: 'sections', label: 'Sections' },
  { topic: 'enrollments', label: 'Enrollments' },
  { topic: 'section-teachers', label: 'Section teachers (co-teachers)' },
]

type RowState = { file: File | null; status: 'idle' | 'uploading' | UploadResult }

export default function IngestPanel() {
  const [rows, setRows] = useState<Record<string, RowState>>(
    Object.fromEntries(TOPICS.map((t) => [t.topic, { file: null, status: 'idle' as const }])),
  )
  const [skipCo, setSkipCo] = useState(false)
  const [running, startRun] = useTransition()
  const [runResult, setRunResult] = useState<RunResult | null>(null)
  const inputs = useRef<Record<string, HTMLInputElement | null>>({})

  function setRow(topic: string, patch: Partial<RowState>) {
    setRows((r) => ({ ...r, [topic]: { ...r[topic], ...patch } }))
  }

  function upload(topic: string) {
    const file = rows[topic].file
    if (!file) return
    setRow(topic, { status: 'uploading' })
    const fd = new FormData()
    fd.append('file', file)
    uploadIngestFile(topic, fd).then((res) => setRow(topic, { status: res }))
  }

  // Countdown to the scheduled pause. Ticks locally off the returned timestamp rather than polling:
  // the maintenance poller already owns the authoritative state, so this exists only so the admin can
  // see how long is left instead of watching a clock.
  const [notice, setNotice] = useState<NoticeResult | null>(null)
  const [scheduling, startSchedule] = useTransition()
  const [countdown, setCountdown] = useState<number | null>(null)

  useEffect(() => {
    if (!notice?.ok || !notice.at) return
    const target = new Date(notice.at).getTime()
    const tick = () => setCountdown(Math.max(0, Math.round((target - Date.now()) / 1000)))
    tick()
    const id = setInterval(tick, 1000)
    return () => clearInterval(id)
  }, [notice])

  function schedule() {
    setNotice(null)
    startSchedule(async () => setNotice(await scheduleIngestMaintenance()))
  }

  function run() {
    setRunResult(null)
    startRun(async () => setRunResult(await runIngestCycle(skipCo)))
  }

  function statusCell(topic: string) {
    const st = rows[topic].status
    if (st === 'idle') return <span className="muted">—</span>
    if (st === 'uploading') return <span className="muted">Uploading…</span>
    if (st.ok) return <span className="ingest-ok">✓ {st.filename}</span>
    return <span className="ingest-err">{st.message}</span>
  }

  return (
    <>
      <p className="muted">
        Upload the latest PowerSchool export for each topic (each upload replaces that folder&apos;s
        contents), then run the cycle. Files must match the deployed <code>COPY INTO</code> format.
      </p>

      <table className="grid">
        <thead>
          <tr>
            <th>Topic</th>
            <th>File</th>
            <th></th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          {TOPICS.map((t) => (
            <tr key={t.topic}>
              <td>{t.label}</td>
              <td>
                <input
                  ref={(el) => {
                    inputs.current[t.topic] = el
                  }}
                  type="file"
                  accept=".csv,.txt,.text,text/csv,text/plain"
                  disabled={rows[t.topic].status === 'uploading' || running}
                  onChange={(e) => setRow(t.topic, { file: e.target.files?.[0] ?? null, status: 'idle' })}
                />
              </td>
              <td>
                <button
                  className="btn-ghost"
                  disabled={!rows[t.topic].file || rows[t.topic].status === 'uploading' || running}
                  onClick={() => upload(t.topic)}
                >
                  Upload
                </button>
              </td>
              <td>{statusCell(t.topic)}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <div className="ingest-run">
        <label className="ingest-skip">
          <input type="checkbox" checked={skipCo} onChange={(e) => setSkipCo(e.target.checked)} />
          Skip co-teachers (no section-teachers file this cycle)
        </label>
        {/* Step 1 — warn teachers. An ingest moves students between sections, and the save path
            scope-checks against the roster, so a teacher saving mid-ingest loses the entry to a
            message that sounds like their fault. The staged banner -> lock -> auto-save flushes
            their work first. See docs/ingest-runbook.md. */}
        <div className="actions">
          <button className="btn-secondary" onClick={schedule} disabled={scheduling || running || countdown !== null}>
            {scheduling ? 'Scheduling…' : `Schedule maintenance (${INGEST_NOTICE_MINUTES} min)`}
          </button>
          {countdown !== null ? (
            <span className={countdown > 0 ? 'muted' : 'ingest-ok'}>
              {countdown > 0
                ? `App pauses in ${Math.floor(countdown / 60)}:${String(countdown % 60).padStart(2, '0')} — wait for it before running.`
                : 'App is paused. Safe to run the ingest.'}
            </span>
          ) : notice && !notice.ok ? (
            <span className="ingest-err">{notice.error}</span>
          ) : null}
        </div>

        {/* Step 2 — the run itself. Deliberately NOT gated on the countdown: a window may already
            have been set by hand or from the Maintenance page, and blocking on state this component
            cannot see would be worse than letting an admin judge it. */}
        <div className="actions">
          <button className="btn" onClick={run} disabled={running}>
            {running ? 'Running ingest cycle…' : 'Run ingest cycle'}
          </button>
          {runResult ? (
            <span className={runResult.ok ? 'ingest-ok' : 'ingest-err'}>{runResult.message}</span>
          ) : null}
        </div>
        {countdown !== null && countdown > 0 && !running ? (
          <p className="muted">
            Running now would cut the warning short — background tabs only check every 8 minutes, so
            some teachers&apos; work may not have saved yet.
          </p>
        ) : null}
        {running ? (
          <p className="muted">The orchestrator runs all loads + merges + the data-quality gate; this can take a minute.</p>
        ) : null}
      </div>
    </>
  )
}
