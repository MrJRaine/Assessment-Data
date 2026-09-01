import { getReadiness } from '@/lib/readiness'
import { getCurrentUpn } from '@/lib/auth'
import { getCallerAccessLevel } from '@/lib/data'
import { PageHeader, CardLink } from '@/components/ui'

export const dynamic = 'force-dynamic'

// Derive a friendly display name from a UPN local-part (jeffrey.raine@tcrce.ca -> "Jeffrey Raine").
// The Power App landing used User().FullName; we only have the UPN server-side, so approximate it.
function friendlyName(upn: string): string {
  const local = (upn.split('@')[0] ?? upn).split(/[._-]+/).filter(Boolean)
  if (local.length === 0) return upn
  return local.map((p) => p.charAt(0).toUpperCase() + p.slice(1)).join(' ')
}

export default async function Home() {
  // Config strip is a dev-diagnostic only — don't disclose posture to unauthenticated visitors in prod.
  const devDiag = process.env.AUTH_MODE === 'dev' && process.env.ALLOW_DEV_AUTH === 'true'
  const r = devDiag ? getReadiness() : null

  // "/" is public, so there may be no signed-in user (entra mode, not yet signed in) — getCurrentUpn
  // throws in that case; fall back to no welcome line rather than erroring the landing page.
  let welcome: string | undefined
  let isAnalyst = false
  try {
    const upn = await getCurrentUpn()
    welcome = `Welcome back, ${friendlyName(upn)}`
    isAnalyst = (await getCallerAccessLevel(upn)) === 'RegionalAnalyst'
  } catch {
    welcome = undefined
  }

  return (
    <>
      <PageHeader title="Reading Assessment" subtitle={welcome} />
      <div className="card-grid">
        <CardLink
          href="/students"
          title="Student Data"
          desc="Browse your students with summary charts, then open any student for their full assessment history and progress trend."
          cta="View & analyze"
        />
        <CardLink
          href="/enter"
          title="Data Entry"
          desc="Record assessment results for a class during an open cycle. The roster grid lets you enter a whole class at once."
          cta="Enter Data"
        />
        <CardLink
          href="/ipp"
          title="Student IPPs"
          desc="Confirm which students have an Individual Program Plan by subject, so assessment data is interpreted correctly."
          cta="Confirm plans"
        />
        {isAnalyst ? (
          <CardLink
            href="/cycles"
            title="Short Cycles"
            desc="Create and manage the Short Cycles of Response — the assessment date ranges teachers enter results into. Regional analysts only."
            cta="Manage cycles"
          />
        ) : null}
        {isAnalyst ? (
          <CardLink
            href="/ingest"
            title="Ingest"
            desc="Upload the latest PowerSchool exports and run the ingestion cycle. Regional analysts only."
            cta="Run ingest"
          />
        ) : null}
      </div>
      {r ? (
        <div className="status-strip muted">
          Region: {r.region} {r.regionCompliant ? '(OK)' : '(check)'} &middot; Auth: {r.authMode} &middot;
          Fabric configured: {r.fabricConfigured ? 'yes' : 'no'}
        </div>
      ) : null}
    </>
  )
}
