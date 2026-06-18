import 'server-only'
import sql from 'mssql'

/**
 * Fabric Warehouse connection -- SERVER-ONLY. The `server-only` import above makes the
 * build fail if this module is ever pulled into a client component, so the connection /
 * credentials can never ship to the browser.
 *
 * NOTE (residency): the deploy target must be a Canadian region (PIIDPA). The warehouse
 * itself is Canada East; the container running this code must be too.
 *
 * NOTE (OLTP vs OLAP): Fabric Warehouse is an analytics engine, fine for pilot-scale write
 * volume but not built for hundreds of concurrent single-row writes. This connection is the
 * "keep the DB for now" bridge; the long-term home is Postgres/Supabase behind this same
 * module (swap the driver + dialect, leave callers untouched).
 */

function buildConfig(): sql.config {
  const server = process.env.FABRIC_SQL_SERVER
  const database = process.env.FABRIC_SQL_DATABASE
  if (!server || !database) {
    throw new Error('FABRIC_SQL_SERVER and FABRIC_SQL_DATABASE must be set')
  }
  return {
    server,
    database,
    port: 1433,
    options: { encrypt: true, trustServerCertificate: false },
    authentication: {
      type: 'azure-active-directory-service-principal-secret',
      options: {
        clientId: process.env.ENTRA_CLIENT_ID ?? '',
        clientSecret: process.env.ENTRA_CLIENT_SECRET ?? '',
        tenantId: process.env.ENTRA_TENANT_ID ?? '',
      },
    },
  }
}

let poolPromise: Promise<sql.ConnectionPool> | null = null

/** Lazily-created shared connection pool (no connection attempt until first query). */
export function getPool(): Promise<sql.ConnectionPool> {
  if (!poolPromise) {
    poolPromise = new sql.ConnectionPool(buildConfig()).connect()
  }
  return poolPromise
}

/**
 * Run a read AS a specific teacher.
 *
 * Fabric RLS views filter on USERPRINCIPALNAME(). Under this service-principal connection,
 * CURRENT_USER is the SP -- NOT the teacher -- so the caller's UPN must be passed explicitly
 * as @UPN, and the secured view/proc must accept and filter on it. (If we later switch to
 * user-token / OBO auth, native RLS holds and @UPN becomes unnecessary.)
 */
export async function queryAsUser(upn: string, query: string): Promise<sql.IRecordSet<Record<string, unknown>>> {
  const pool = await getPool()
  const request = pool.request()
  request.input('UPN', sql.VarChar(256), upn)
  const result = await request.query<Record<string, unknown>>(query)
  return result.recordset
}
