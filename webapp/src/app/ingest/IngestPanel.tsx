'use client'

import { useRef, useState, useTransition } from 'react'
import { uploadIngestFile, runIngestCycle, type UploadResult, type RunResult } from './actions'

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
