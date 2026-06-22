import Link from 'next/link'
import { PageHeader, ErrorNote } from '@/components/ui'
import { getCurrentUpn } from '@/lib/auth'
import { getStudentCohort, getStudentHistory, type HistoryRow } from '@/lib/data'

export const dynamic = 'force-dynamic'

// Simple dependency-free SVG trend of reading level over time (Y axis 0..31, matching the Power App).
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

export default async function StudentDetail({ params }: { params: Promise<{ studentKey: string }> }) {
  const { studentKey } = await params
  const upn = await getCurrentUpn()

  let error: string | null = null
  let history: HistoryRow[] = []
  let cohort: Awaited<ReturnType<typeof getStudentCohort>> = []
  try {
    ;[cohort, history] = await Promise.all([getStudentCohort(upn), getStudentHistory(upn, studentKey)])
  } catch (e) {
    error = e instanceof Error ? e.message : String(e)
  }

  const student = cohort.find((s) => s.studentKey === studentKey)
  const idx = cohort.findIndex((s) => s.studentKey === studentKey)
  const prev = idx > 0 ? cohort[idx - 1] : null
  const next = idx >= 0 && idx < cohort.length - 1 ? cohort[idx + 1] : null

  if (error) {
    return (
      <>
        <PageHeader title="Student detail" />
        <ErrorNote message={error} />
      </>
    )
  }
  if (!student) {
    return (
      <>
        <PageHeader title="Student detail" />
        <p>
          <Link href="/students" className="back-link">&larr; Back to students</Link>
        </p>
        <div className="notice notice-empty">
          <div className="notice-title">Student not in your scope</div>
        </div>
      </>
    )
  }

  // Newest-first for the timeline table (the trend reads oldest-first).
  const timeline = [...history].reverse()
  const meta = [
    `Grade ${student.grade ?? '—'}`,
    student.programFamily ?? '—',
    student.schoolAbbreviation ?? student.schoolName ?? student.schoolId ?? '—',
    student.homeroom ? `Homeroom ${student.homeroom}` : null,
    `IPP (Reading): ${student.ippStatusReading}`,
  ].filter(Boolean) as string[]

  return (
    <>
      <PageHeader title={student.fullName} />
      <div className="detail-nav">
        <Link href="/students" className="back-link">&larr; Back to students</Link>
        <span className="detail-counter muted">
          Student {idx + 1} of {cohort.length}
        </span>
        <span className="detail-paging">
          {prev ? (
            <Link href={`/students/${prev.studentKey}`} className="btn-ghost">&larr; Prev</Link>
          ) : (
            <span className="btn-ghost btn-ghost-disabled">&larr; Prev</span>
          )}
          {next ? (
            <Link href={`/students/${next.studentKey}`} className="btn-ghost">Next &rarr;</Link>
          ) : (
            <span className="btn-ghost btn-ghost-disabled">Next &rarr;</span>
          )}
        </span>
      </div>

      <div className="meta-strip">{meta.join('   ·   ')}</div>

      <h2 className="section-title">Assessment history</h2>
      {timeline.length === 0 ? (
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
