'use client'

import Link from 'next/link'
import { useCallback, useEffect, useRef, useState } from 'react'
import { PageHeader } from '@/components/ui'
import type { HistoryRow, WritingHistoryRow, StudentNavItem } from '@/lib/data'

type AnyHistory = HistoryRow[] | WritingHistoryRow[]
type Subject = 'Reading' | 'Writing'

// Dependency-free SVG trend: plots value-over-time on a fixed Y scale with gridlines.
function TrendChart({
  points,
  yMin,
  yMax,
  gridlines,
  label,
}: {
  points: { value: number; date: string; key: string }[]
  yMin: number
  yMax: number
  gridlines: number[]
  label: string
}) {
  if (points.length === 0) return null
  const W = 640
  const H = 200
  const padL = 32
  const padR = 16
  const padT = 12
  const padB = 28
  const innerW = W - padL - padR
  const innerH = H - padT - padB
  const x = (i: number) => (points.length === 1 ? padL + innerW / 2 : padL + (i * innerW) / (points.length - 1))
  const y = (v: number) => padT + innerH - ((Math.min(Math.max(v, yMin), yMax) - yMin) / (yMax - yMin)) * innerH
  const fmt = new Intl.DateTimeFormat('en-CA', { month: 'short', year: '2-digit' })
  const line = points.map((p, i) => `${x(i)},${y(p.value)}`).join(' ')

  return (
    <svg className="trend" viewBox={`0 0 ${W} ${H}`} role="img" aria-label={label}>
      {gridlines.map((g) => (
        <g key={g}>
          <line x1={padL} y1={y(g)} x2={W - padR} y2={y(g)} stroke="var(--border)" strokeWidth={1} />
          <text x={4} y={y(g) + 3} fontSize={9} fill="var(--muted)">{g}</text>
        </g>
      ))}
      <polyline points={line} fill="none" stroke="var(--primary)" strokeWidth={2} />
      {points.map((p, i) => (
        <g key={p.key}>
          <circle cx={x(i)} cy={y(p.value)} r={4} fill="var(--primary)" />
          <text x={x(i)} y={H - 8} fontSize={9} fill="var(--muted)" textAnchor="middle">
            {fmt.format(new Date(p.date))}
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
  subject,
  loadHistory,
}: {
  navList: StudentNavItem[]
  initialKey: string
  initialHistory: AnyHistory
  subject: Subject
  loadHistory: (studentKey: string) => Promise<AnyHistory>
}) {
  const [currentKey, setCurrentKey] = useState(initialKey)
  const [cache, setCache] = useState<Record<string, AnyHistory>>({ [initialKey]: initialHistory })
  const inFlight = useRef<Set<string>>(new Set())

  const idx = navList.findIndex((s) => s.studentKey === currentKey)
  const current = navList[idx]
  const prev = idx > 0 ? navList[idx - 1] : null
  const next = idx >= 0 && idx < navList.length - 1 ? navList[idx + 1] : null

  const ensureLoaded = useCallback(
    (key: string | null | undefined) => {
      if (!key || cache[key] !== undefined || inFlight.current.has(key)) return
      inFlight.current.add(key)
      loadHistory(key)
        .then((rows) => setCache((c) => ({ ...c, [key]: rows })))
        .catch(() => setCache((c) => ({ ...c, [key]: [] })))
        .finally(() => inFlight.current.delete(key))
    },
    [cache, loadHistory],
  )

  useEffect(() => {
    ensureLoaded(currentKey)
    ensureLoaded(prev?.studentKey)
    ensureLoaded(next?.studentKey)
  }, [currentKey, prev?.studentKey, next?.studentKey, ensureLoaded])

  function go(key: string) {
    setCurrentKey(key)
    // Keep the URL in sync (preserve the subject query) without a Next route navigation.
    const suffix = subject === 'Writing' ? '?subject=writing' : ''
    window.history.replaceState(null, '', `/students/${key}${suffix}`)
  }

  if (!current) return null
  const isWriting = subject === 'Writing'
  const history = cache[currentKey]
  const loading = history === undefined
  const timeline = history ? [...history].reverse() : [] // newest-first table

  // IPP students follow an individualized plan: tracked for personal progress but NOT measured
  // against benchmarks — suppress the achievement band/colour (and Δ for reading). Mirrors the roster.
  const measured = current.ippStatus === 'Not IPP' || current.ippStatus === 'N/A'
  const ippConfirmed = current.ippStatus === 'IPP'

  const meta = [
    `Grade ${current.grade ?? '—'}`,
    current.programFamily ?? '—',
    current.schoolLabel ?? '—',
    current.homeroom ? `Homeroom ${current.homeroom}` : null,
    `IPP (${subject}): ${current.ippStatus}`,
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

      <div className="subject-toggle">
        <Link href={`/students/${currentKey}`} className={!isWriting ? 'toggle-on' : ''}>Reading</Link>
        <Link href={`/students/${currentKey}?subject=writing`} className={isWriting ? 'toggle-on' : ''}>Writing</Link>
      </div>

      <div className="meta-strip">{meta.join('   ·   ')}</div>

      {ippConfirmed ? (
        <div className="ipp-note">
          On an individualized program plan — {subject.toLowerCase()} is tracked for personal progress and is
          <strong> not measured against grade-level benchmarks</strong>, so no achievement band is shown.
        </div>
      ) : current.ippStatus === 'Unresolved' ? (
        <div className="ipp-note">
          {subject} IPP needs confirmation — achievement is not shown until the IPP type is confirmed
          (on the roster or the IPPs screen).
        </div>
      ) : null}

      <h2 className="section-title">Assessment history</h2>
      {loading ? (
        <div className="loading"><span className="spinner" />Loading student history…</div>
      ) : timeline.length === 0 ? (
        <div className="notice notice-empty">
          <div className="notice-title">No {subject.toLowerCase()} assessments recorded for this student yet.</div>
        </div>
      ) : isWriting ? (
        <>
          <table className="grid">
            <thead>
              <tr>
                <th>Assessment window</th>
                <th>Date</th>
                <th>Ideas</th>
                <th>Org.</th>
                <th>Lang.</th>
                <th>Conv.</th>
                <th>Avg</th>
                <th>Achievement</th>
              </tr>
            </thead>
            <tbody>
              {(timeline as WritingHistoryRow[]).map((h) => (
                <tr key={h.writingAssessmentId} style={measured && h.achievementHexColorTint ? { background: h.achievementHexColorTint } : undefined}>
                  <td>{h.windowName}{h.windowSchoolYear ? ` · ${h.windowSchoolYear}` : ''}</td>
                  <td className="muted">{h.assessmentDate ?? '—'}</td>
                  <td>{h.ideas ?? '—'}</td>
                  <td>{h.organization ?? '—'}</td>
                  <td>{h.language ?? '—'}</td>
                  <td>{h.conventions ?? '—'}</td>
                  <td>{h.avgScore == null ? '—' : h.avgScore.toFixed(2)}</td>
                  <td style={measured && h.achievementHexColor ? { color: h.achievementHexColor, fontWeight: 600 } : undefined}>
                    {!measured ? (ippConfirmed ? 'IPP' : '—') : h.achievementName ?? '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          <h2 className="section-title">Writing average over time</h2>
          <div className="chart-card">
            <TrendChart
              points={(history as WritingHistoryRow[])
                .filter((h) => h.avgScore != null && h.assessmentDate)
                .map((h) => ({ value: h.avgScore!, date: h.assessmentDate!, key: h.writingAssessmentId }))}
              yMin={1}
              yMax={4}
              gridlines={[1, 2, 3, 4]}
              label="Writing average over time"
            />
          </div>
        </>
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
              {(timeline as HistoryRow[]).map((h) => (
                <tr key={h.readingAssessmentId} style={measured && h.achievementHexColorTint ? { background: h.achievementHexColorTint } : undefined}>
                  <td>{h.windowName}{h.windowSchoolYear ? ` · ${h.windowSchoolYear}` : ''}</td>
                  <td className="muted">{h.assessmentDate ?? '—'}</td>
                  <td>{h.levelCode ?? '—'}</td>
                  <td style={measured && h.achievementHexColor ? { color: h.achievementHexColor, fontWeight: 600 } : undefined}>
                    {!measured ? (ippConfirmed ? 'IPP' : '—') : h.delta == null ? '—' : h.delta > 0 ? `+${h.delta}` : h.delta}
                  </td>
                  <td>{!measured ? (ippConfirmed ? 'IPP' : '—') : h.achievementName ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>

          <h2 className="section-title">Reading level over time</h2>
          <div className="chart-card">
            <TrendChart
              points={(history as HistoryRow[])
                .filter((h) => h.levelOrder != null && h.assessmentDate)
                .map((h) => ({ value: h.levelOrder!, date: h.assessmentDate!, key: h.readingAssessmentId }))}
              yMin={0}
              yMax={31}
              gridlines={[0, 8, 16, 24, 31]}
              label="Reading level over time"
            />
          </div>
        </>
      )}
    </>
  )
}
