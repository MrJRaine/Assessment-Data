import Link from 'next/link'
import { PageHeader, EmptyState } from '@/components/ui'

export const dynamic = 'force-dynamic'

// Placeholder for the RWM report (item 5) — keeps the subject toggle's fourth tab from 404-ing while
// the 0–3 Reading/Writing/Math achievement roll-up is built.
export default function RwmReportsPage() {
  return (
    <>
      <PageHeader title="Reports" subtitle="RWM — Reading · Writing · Math achievement roll-up" />
      <div className="subject-toggle">
        <Link href="/reports" className="toggle">Reading</Link>
        <Link href="/reports?subject=writing" className="toggle">Writing</Link>
        <Link href="/reports/math" className="toggle">Math</Link>
        <Link href="/reports/rwm" className="toggle-on">RWM</Link>
      </div>
      <EmptyState
        title="RWM report coming next"
        hint="A 0–3 score per Primary–6 student counting how many of Reading, Writing, and Math they're currently meeting or exceeding (students with a confirmed IPP in any of the three are excluded)."
      />
    </>
  )
}
