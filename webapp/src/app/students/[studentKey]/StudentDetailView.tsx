'use client'

import Link from 'next/link'
import { useCallback, useEffect, useRef, useState } from 'react'
import { PageHeader } from '@/components/ui'
import { loadStudentHistory } from './actions'
import type { HistoryRow, StudentNavItem } from '@/lib/data'

// Dependency-free SVG trend of reading level over time (Y axis 0..31, matching the Power App).
function TrendChart({ history }: { history: HistoryRow[] }) {
  const pts = history.filter((h) => h.levelOrder != null && h.assessmentDate)
  if (pts.length === 0) return null
  const W = 640
  const H = 200
  const padL = 32
  const padR = 16
  const padT = 12
  const padB = 28
  const yMax = 31
  const innerW = W - padL - padR
  const innerH = H - padT - padB
  const x = (i: number) => (pts.length === 1 ? padL + innerW / 2 : padL + (i * innerW) / (pts.length - 1))
  const y = (lo: number) => padT + innerH - (Math.min(lo, yMax) / yMax) * innerH
  const fmt = new Intl.DateTimeFormat('en-CA', { month: 'short', year: '2-digit' })
  const line = pts.map((p, i) => `${x(i)},${y(p.levelOrder!)}`).join(' ')

  return (
    <svg className="trend" viewBox={`0 0 ${W} ${H}`} role="img" aria-label="Reading level over time">
      {[0, 8, 16, 24, 31].map((g) => (
        <g key={g}>
          <line x1={padL} y1={y(g)} x2={W - padR} y2={y(g)} stroke="var(--border)" strokeWidth={1} />
          <text x={4} y={y(g) + 3} fontSize={9} fill="var(--muted)">{g}</text>
        </g>
      ))}
      <polyline points={line} fill="none" stroke="var(--primary)" strokeWidth={2} />
      {pts.map((p, i) => (
        <g key={p.readingAssessmentId}>
          <circle cx={x(i)} cy={y(p.levelOrder!)} r={4} fill="var(--primary)" />
          <text x={x(i)} y={H - 8} fontSize={9} fill="var(--muted)" textAnchor="middle">
            {fmt.format(new Date(p.assessmentDate!))}
          </text>
        </g>
      ))}
    </svg>
  )
}

export default function StudentDetailView({
  navList,
  initialKey,
  initialHistory,
}: {
  navList: StudentNavItem[]
  initialKey: string
  initialHistory: HistoryRow[]
}) {
  const [currentKey, setCurrentKey] = useState(initialKey)
  const [cache, setCache] = useState<Record<string, HistoryRow[]>>({ [initialKey]: initialHistory })
  const inFlight = useRef<Set<string>>(new Set())

  const idx = navList.findIndex((s) => s.studentKey === currentKey)
  const current = navList[idx]
  const prev = idx > 0 ? navList[idx - 1] : null
  const next = idx >= 0 && idx < navList.length - 1 ? navList[idx + 1] : null

  const ensureLoaded = useCallback(
    (key: string | null | undefined) => {
      if (!key || cache[key] !== undefined || inFlight.current.has(key)) return
      inFlight.current.add(key)
      loadStudentHistory(key)
        .then((rows) => setCache((c) => ({ ...c, [key]: rows })))
        .catch(() => setCache((c) => ({ ...c, [key]: [] })))
        .finally(() => inFlight.current.delete(key))
    },
    [cache],
  )

  // Load the current student + prefetch both neighbours so paging is instant.
  useEffect(() => {
    ensureLoaded(currentKey)
    ensureLoaded(prev?.studentKey)
    ensureLoaded(next?.studentKey)
  }, [currentKey, prev?.studentKey, next?.studentKey, ensureLoaded])

  function go(key: string) {
    setCurrentKey(key)
    // Keep the URL in sync for deep-linking/refresh without triggering a Next route navigation.
    window.history.replaceState(null, '', `/students/${key}`)
  }

  if (!current) return null
  const history = cache[currentKey]
  const loading = history === undefined
  const timeline = history ? [...history].reverse() : [] // newest-first table; trend reads asc

  const meta = [
    `Grade ${current.grade ?? '—'}`,
    current.programFamily ?? '—',
    current.schoolLabel ?? '—',
    current.homeroom ? `Homeroom ${current.homeroom}` : null,
    `IPP (Reading): ${current.ippStatusReading}`,
  ].filter(Boolean) as string[]

  return (
    <>
      <PageHeader title={current.fullName} />
      <div className="detail-nav">
        <Link href="/students" className="back-link">&larr; Back to students</Link>
        <span className="detail-counter muted">Student {idx + 1} of {navList.length}</span>
        <span className="detail-paging">
          <button className="btn-ghost" disabled={!prev} onClick={() => prev && go(prev.studentKey)}>&larr; Prev</button>
          <button className="btn-ghost" disabled={!next} onClick={() => next && go(next.studentKey)}>Next &rarr;</button>
        </span>
      </div>

      <div className="meta-strip">{meta.join('   ·   ')}</div>

      <h2 className="section-title">Assessment history</h2>
      {loading ? (
        <div className="loading"><span className="spinner" />Loading student history…</div>
      ) : timeline.length === 0 ? (
        <div className="notice notice-empty">
          <div className="notice-title">No reading assessments recorded for this student yet.</div>
        </div>
      ) : (
        <>
          <table className="grid">
            <thead>
              <tr>
                <th>Assessment window</th>
                <th>Date</th>
                <th>Level</th>
                <th>Δ</th>
                <th>Achievement</th>
              </tr>
            </thead>
            <tbody>
              {timeline.map((h) => (
                <tr key={h.readingAssessmentId} style={h.achievementHexColorTint ? { background: h.achievementHexColorTint } : undefined}>
                  <td>{h.windowName}{h.windowSchoolYear ? ` · ${h.windowSchoolYear}` : ''}</td>
                  <td className="muted">{h.assessmentDate ?? '—'}</td>
                  <td>{h.levelCode ?? '—'}</td>
                  <td style={h.achievementHexColor ? { color: h.achievementHexColor, fontWeight: 600 } : undefined}>
                    {h.delta == null ? '—' : h.delta > 0 ? `+${h.delta}` : h.delta}
                  </td>
                  <td>{h.achievementName ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>

          <h2 className="section-title">Reading level over time</h2>
          <div className="chart-card">
            <TrendChart history={history} />
          </div>
        </>
      )}
    </>
  )
}
