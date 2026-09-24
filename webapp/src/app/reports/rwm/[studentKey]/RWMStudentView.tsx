'use client'

import Link from 'next/link'
import { useMemo, useState } from 'react'
import { PageHeader } from '@/components/ui'
import type { RWMStudent, RWMHistoryRow } from '@/lib/data'

const gradeLabel = (g: string) => (g === 'P' ? 'Primary' : g === 'PP' ? 'Pre-Primary' : `Grade ${g}`)
const SCORE_HEX: Record<number, string> = { 0: '#b23347', 1: '#c07d16', 2: '#2f8f4e', 3: '#0092c9' }

// Dependency-free SVG trend of the 0–3 score over the year's cycles.
function ScoreTrend({ points }: { points: { value: number; label: string }[] }) {
  if (points.length === 0) return null
  const W = 640, H = 200, padL = 28, padR = 16, padT = 12, padB = 34
  const innerW = W - padL - padR, innerH = H - padT - padB
  const x = (i: number) => (points.length === 1 ? padL + innerW / 2 : padL + (i * innerW) / (points.length - 1))
  const y = (v: number) => padT + innerH - (v / 3) * innerH
  const line = points.map((p, i) => `${x(i)},${y(p.value)}`).join(' ')
  return (
    <svg className="trend" viewBox={`0 0 ${W} ${H}`} role="img" aria-label="RWM score over cycles">
      {[0, 1, 2, 3].map((g) => (
        <g key={g}>
          <line x1={padL} y1={y(g)} x2={W - padR} y2={y(g)} stroke="var(--border)" strokeWidth={1} />
          <text x={4} y={y(g) + 3} fontSize={9} fill="var(--muted)">{g}</text>
        </g>
      ))}
      <polyline points={line} fill="none" stroke="var(--primary)" strokeWidth={2} />
      {points.map((p, i) => (
        <g key={i}>
          <circle cx={x(i)} cy={y(p.value)} r={4} fill={SCORE_HEX[p.value] ?? 'var(--primary)'} />
          <text x={x(i)} y={H - 8} fontSize={9} fill="var(--muted)" textAnchor="middle">{p.label}</text>
        </g>
      ))}
    </svg>
  )
}

function AreaSnapshot({ title, meeting, has, detail }: { title: string; meeting: boolean; has: boolean; detail?: string }) {
  const state = !has ? 'none' : meeting ? 'yes' : 'no'
  const label = !has ? 'No result yet' : meeting ? 'Meeting or exceeding' : 'Not yet meeting'
  return (
    <div className={`rwm-snap ${state}`}>
      <div className="rwm-snap-title">{title}</div>
      <div className="rwm-snap-state">{label}</div>
      {detail ? <div className="rwm-snap-detail muted">{detail}</div> : null}
    </div>
  )
}

export default function RWMStudentView({
  student,
  history,
  position,
  total,
  prevKey,
  nextKey,
}: {
  student: RWMStudent
  history: RWMHistoryRow[]
  position: number
  total: number
  prevKey: string | null
  nextKey: string | null
}) {
  // Blanks toggle affects only the Math component (see the cohort view). Recompute client-side.
  const [blankMode, setBlankMode] = useState<'exclude' | 'zero'>('exclude')

  const meta = [
    gradeLabel(student.grade ?? '—'),
    student.programFamily ?? '—',
    student.schoolName ?? '—',
    student.homeroom ? `Homeroom ${student.homeroom}` : null,
  ].filter(Boolean) as string[]

  const effMathPct = blankMode === 'zero' ? student.mathRollupPctZero : student.mathRollupPct
  const mathMeeting = effMathPct != null && effMathPct >= 0.75
  const rwmScore = (student.readingMeeting ? 1 : 0) + (student.writingMeeting ? 1 : 0) + (mathMeeting ? 1 : 0)
  const mathPct = effMathPct == null ? null : (effMathPct * 100).toFixed(1)
  const missing = [
    !student.hasReading && 'Reading',
    !student.hasWriting && 'Writing',
    !student.hasMath && 'Math',
  ].filter(Boolean) as string[]

  const cycles = useMemo(
    () => history.map((h) => {
      const pct = blankMode === 'zero' ? h.mathRollupPctZero : h.mathRollupPct
      const mMeet = pct != null && pct >= 0.75
      const score = (h.readingMeeting ? 1 : 0) + (h.writingMeeting ? 1 : 0) + (mMeet ? 1 : 0)
      return { ...h, mMeet, mPct: pct, score }
    }),
    [history, blankMode],
  )
  const points = cycles.map((h) => ({ value: h.score, label: h.cycleLabel.split(' ')[0].slice(0, 3) }))

  return (
    <>
      <PageHeader title={student.fullName} />
      <div className="detail-nav">
        <Link href="/reports/rwm" className="back-link">&larr; Back to RWM</Link>
        <span className="detail-counter muted">Student {position} of {total}</span>
        <span className="detail-paging">
          {prevKey ? <Link className="btn-ghost" href={`/reports/rwm/${prevKey}`}>&larr; Prev</Link> : <button className="btn-ghost" disabled>&larr; Prev</button>}
          {nextKey ? <Link className="btn-ghost" href={`/reports/rwm/${nextKey}`}>Next &rarr;</Link> : <button className="btn-ghost" disabled>Next &rarr;</button>}
        </span>
      </div>

      <div className="meta-strip">{meta.join('   ·   ')}</div>

      <div className="cohort-bar">
        <button
          className="btn-ghost"
          onClick={() => setBlankMode((m) => (m === 'exclude' ? 'zero' : 'exclude'))}
          title="How un-recorded Math tasks affect the roll-up (Reading/Writing are unaffected)"
        >
          Blanks: {blankMode === 'exclude' ? 'excluded' : 'count as 0'}
        </button>
      </div>

      <div className="rwm-hero">
        <span className="rwm-score lg" style={{ background: SCORE_HEX[rwmScore] }}>{rwmScore}</span>
        <span className="rwm-hero-label">of 3 areas currently meeting or exceeding</span>
      </div>

      {missing.length > 0 ? (
        <div className="ipp-note">
          No result yet in <strong>{missing.join(', ')}</strong> — this student doesn&apos;t have a score in
          all three areas, so their RWM score reflects only the areas with evidence.
        </div>
      ) : null}

      <div className="rwm-snaps">
        <AreaSnapshot title="Reading" meeting={student.readingMeeting} has={student.hasReading} />
        <AreaSnapshot title="Writing" meeting={student.writingMeeting} has={student.hasWriting} />
        <AreaSnapshot title="Math" meeting={mathMeeting} has={student.hasMath} detail={mathPct == null ? undefined : `Roll-up ${mathPct}%`} />
      </div>

      <h2 className="section-title">Score by cycle</h2>
      {history.length === 0 ? (
        <div className="notice notice-empty"><div className="notice-title">No cycles with results yet this year.</div></div>
      ) : (
        <>
          <div className="chart-card">
            <ScoreTrend points={points} />
          </div>
          <table className="grid">
            <thead>
              <tr>
                <th>Cycle</th>
                <th>Reading</th>
                <th>Writing</th>
                <th>Math</th>
                <th>RWM</th>
              </tr>
            </thead>
            <tbody>
              {cycles.map((h) => (
                <tr key={h.cycleDate ?? h.cycleLabel}>
                  <td>{h.cycleLabel}</td>
                  <td className={h.readingMeeting ? 'rwm-meet' : 'muted'}>{h.readingCode == null ? '—' : h.readingMeeting ? 'Meeting+' : 'Not yet'}</td>
                  <td className={h.writingMeeting ? 'rwm-meet' : 'muted'}>{h.writingCode == null ? '—' : h.writingMeeting ? 'Meeting+' : 'Not yet'}</td>
                  <td className={h.mMeet ? 'rwm-meet' : 'muted'}>{h.mPct == null ? '—' : `${(h.mPct * 100).toFixed(1)}%`}</td>
                  <td><span className="rwm-score sm" style={{ background: SCORE_HEX[h.score] }}>{h.score}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </>
  )
}
