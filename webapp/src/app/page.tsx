import { getReadiness } from '@/lib/readiness'
import { getCurrentUpn } from '@/lib/auth'
import { getCallerCapabilities } from '@/lib/data'
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
  let caps = { isSysAdmin: false, canManageCycles: false, canRunIngest: false }
  try {
    const upn = await getCurrentUpn()
    // First name only for the welcome line (friendlyName gives "Jeffrey Raine" -> "Jeffrey").
    welcome = `Welcome back, ${friendlyName(upn).split(' ')[0]}`
    caps = await getCallerCapabilities(upn)
  } catch {
    welcome = undefined
  }

  return (
    <>
      <PageHeader title="The SCoR Hub" subtitle={welcome} />
      <div className="card-grid">
        <CardLink
          href="/enter"
          title="Data Entry"
          desc="Record assessment results for a class during an open cycle. The roster grid lets you enter a whole class at once."
          cta="Enter Data"
        />
        <CardLink
          href="/reports"
          title="Reports"
          desc="Browse your students with summary charts, then open any student for their full results history and progress trend."
          cta="View & analyze"
        />
        <CardLink
          href="/programming"
          title="Programming"
          desc="Record each student's Individual Program Plans and Adaptations by subject, so results are interpreted correctly."
          cta="Open Programming"
        />
      </div>

      {/* Administration — cycle setup, PowerSchool ingest, and maintenance windows. The whole section
          (heading included) appears only if the caller holds at least one of these capabilities, so a
          teacher never sees an admin heading or an empty grid. */}
      {(caps.canManageCycles || caps.canRunIngest || caps.isSysAdmin) ? (
        <section className="window-section home-admin">
          <h2 className="section-heading">Admin Tools</h2>
          <div className="card-grid">
            {caps.canManageCycles ? (
              <CardLink
                href="/cycles"
                title="Short Cycles"
                desc="Create and manage the Short Cycles of Response — the date ranges teachers enter results into. Regional analysts only."
                cta="Manage cycles"
              />
            ) : null}
            {caps.canRunIngest ? (
              <CardLink
                href="/ingest"
                title="Ingest"
                desc="Upload the latest PowerSchool exports and run the ingestion cycle. Regional analysts only."
                cta="Run ingest"
              />
            ) : null}
            {caps.isSysAdmin ? (
              <CardLink
                href="/admin/maintenance"
                title="Maintenance"
                desc="Schedule or clear a maintenance window before a deploy or data refresh — teachers' work is saved before the app pauses. System administrators only."
                cta="Open maintenance"
              />
            ) : null}
            {caps.isSysAdmin ? (
              <CardLink
                href="/admin/staff-access"
                title="Staff Access"
                desc="Grant app capabilities to staff — cycle management, ingest, and the grace-lock overrides. System administrators only."
                cta="Manage access"
              />
            ) : null}
          </div>
        </section>
      ) : null}
      {r ? (
        <div className="status-strip muted">
          Region: {r.region} {r.regionCompliant ? '(OK)' : '(check)'} &middot; Auth: {r.authMode} &middot;
          Fabric configured: {r.fabricConfigured ? 'yes' : 'no'}
        </div>
      ) : null}
    </>
  )
}
