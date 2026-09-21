'use client'

import { useRef, useState, useTransition } from 'react'
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

  // No countdown here on purpose: this schedules the SAME maintenance window as /admin/maintenance,
  // so the app-wide banner already shows the time and a live (mm:ss) on every page, this one
  // included. A second clock beside it would just be another thing to keep in sync.
  const [notice, setNotice] = useState<NoticeResult | null>(null)
  const [scheduling, startSchedule] = useTransition()

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
          <button className="btn-secondary" onClick={schedule} disabled={scheduling || running}>
            {scheduling ? 'Scheduling…' : `Schedule maintenance (${INGEST_NOTICE_MINUTES} min)`}
          </button>
          {notice?.ok ? (
            <span className="ingest-ok">Scheduled — see the banner for the time and countdown.</span>
          ) : notice ? (
            <span className="ingest-err">{notice.error}</span>
          ) : null}
        </div>

        {/* Step 2 — the run itself. Deliberately NOT gated on the window: it may have been set by
            hand or from the Maintenance page, and blocking on state this component cannot see would
            be worse than letting the admin read the banner and judge. */}
        <div className="actions">
          <button className="btn" onClick={run} disabled={running}>
            {running ? 'Running ingest cycle…' : 'Run ingest cycle'}
          </button>
          {runResult ? (
            <span className={runResult.ok ? 'ingest-ok' : 'ingest-err'}>{runResult.message}</span>
          ) : null}
        </div>
        {running ? (
          <p className="muted">The orchestrator runs all loads + merges + the data-quality gate; this can take a minute.</p>
        ) : null}
      </div>
    </>
  )
}
