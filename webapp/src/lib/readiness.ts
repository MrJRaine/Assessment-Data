import 'server-only'

/** Lightweight self-check surfaced on the landing page and /api/health. Reads env presence
 *  only -- it does NOT open a DB connection, so it is safe to call on every request. */
export interface Readiness {
  fabricConfigured: boolean
  authMode: string
  entraConfigured: boolean
  onelakeConfigured: boolean
  region: string
  regionCompliant: boolean
}

export function getReadiness(): Readiness {
  const region = process.env.DATA_REGION ?? '(unset)'
  return {
    fabricConfigured: Boolean(process.env.FABRIC_SQL_SERVER && process.env.FABRIC_SQL_DATABASE),
    authMode: process.env.AUTH_MODE ?? 'dev',
    entraConfigured: Boolean(
      process.env.ENTRA_TENANT_ID && process.env.ENTRA_CLIENT_ID && process.env.ENTRA_CLIENT_SECRET,
    ),
    // OneLake upload (ingest screen) needs the workspace + landing-lakehouse GUIDs.
    onelakeConfigured: Boolean(process.env.ONELAKE_WORKSPACE && process.env.ONELAKE_LANDING_LAKEHOUSE),
    region,
    regionCompliant: region.toLowerCase().startsWith('canada'),
  }
}
