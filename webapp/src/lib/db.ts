import 'server-only'
import sql from 'mssql'
import { ClientSecretCredential } from '@azure/identity'

/**
 * Fabric Warehouse connection -- SERVER-ONLY. The `server-only` import above makes the
 * build fail if this module is ever pulled into a client component, so the connection /
 * credentials can never ship to the browser.
 *
 * AUTH (why a pre-acquired token, not tedious's built-in SP-secret auth):
 *   Microsoft Fabric's SQL endpoint REJECTS the token tedious mints under its own
 *   `azure-active-directory-service-principal-secret` flow -- the login is dropped right after
 *   Login7 with a bare "Connection lost - socket hang up" (the symptom behind tediousjs/tedious
 *   #1563). The fix is to acquire the access token ourselves with `@azure/identity`
 *   (ClientSecretCredential -> https://database.windows.net/.default) and hand tedious a ready
 *   token via `azure-active-directory-access-token`. That connects cleanly. @azure/identity is a
 *   standard library (it just calls login.microsoftonline.com) -- no premium connector, $0.
 *
 * RESIDENCY (PIIDPA): the deploy target must be a Canadian region. The warehouse is Canada
 * East; the container running this code must be too.
 *
 * OLTP vs OLAP: Fabric Warehouse is an analytics engine -- fine for pilot-scale write volume,
 * not for hundreds of concurrent single-row writes. This is the "keep the DB for now" bridge;
 * the long-term home is Postgres/Supabase behind this same module (swap driver + dialect, leave
 * callers untouched).
 */

// AAD scope for the SQL data plane (Fabric accepts database.windows.net audience tokens).
const SQL_SCOPE = 'https://database.windows.net/.default'

let credential: ClientSecretCredential | null = null

export function getCredential(): ClientSecretCredential {
  if (!credential) {
    const tenantId = process.env.ENTRA_TENANT_ID
    const clientId = process.env.ENTRA_CLIENT_ID
    const clientSecret = process.env.ENTRA_CLIENT_SECRET
    if (!tenantId || !clientId || !clientSecret) {
      throw new Error('ENTRA_TENANT_ID, ENTRA_CLIENT_ID and ENTRA_CLIENT_SECRET must be set')
    }
    // ClientSecretCredential caches tokens internally and refreshes them near expiry.
    credential = new ClientSecretCredential(tenantId, clientId, clientSecret)
  }
  return credential
}

async function buildConfig(): Promise<sql.config> {
  const server = process.env.FABRIC_SQL_SERVER
  const database = process.env.FABRIC_SQL_DATABASE
  if (!server || !database) {
    throw new Error('FABRIC_SQL_SERVER and FABRIC_SQL_DATABASE must be set')
  }
  const token = await getCredential().getToken(SQL_SCOPE)
  if (!token?.token) {
    throw new Error('Failed to acquire an Entra access token for Fabric')
  }
  return {
    server,
    database,
    port: 1433,
    options: { encrypt: true, trustServerCertificate: false },
    authentication: { type: 'azure-active-directory-access-token', options: { token: token.token } },
  }
}

let poolPromise: Promise<sql.ConnectionPool> | null = null

/**
 * Lazily-created shared connection pool (no connection attempt until first query).
 *
 * The pool authenticates with the access token at connect time; the live TDS session then
 * persists, so token expiry (~1h) does not break an open connection. If the connect attempt
 * fails we clear the cached promise so the next call retries with a freshly-minted token.
 * (TODO before full rollout: also reset the pool on a connection-level query error so a long
 * idle period followed by a reconnect always uses a current token.)
 */
export function getPool(): Promise<sql.ConnectionPool> {
  if (!poolPromise) {
    poolPromise = buildConfig().then((cfg) => new sql.ConnectionPool(cfg).connect())
    poolPromise.catch(() => {
      poolPromise = null
    })
  }
  return poolPromise
}

/** Run a query that takes no per-user filtering (e.g. reference/lookup reads). */
export async function query<T extends Record<string, unknown> = Record<string, unknown>>(
  text: string,
  params: Record<string, unknown> = {},
): Promise<T[]> {
  const pool = await getPool()
  const request = pool.request()
  for (const [name, value] of Object.entries(params)) {
    request.input(name, value)
  }
  const result = await request.query<T>(text)
  return result.recordset
}

/**
 * Run a read AS a specific teacher.
 *
 * Fabric RLS views filter on USERPRINCIPALNAME(). Under this service-principal connection,
 * CURRENT_USER is the SP -- NOT the teacher -- so the caller's UPN is passed explicitly as
 * @UPN, and the secured view/proc must accept and filter on it. (If we later switch to
 * user-token / OBO auth, native RLS holds and @UPN becomes unnecessary.)
 */
export async function queryAsUser<T extends Record<string, unknown> = Record<string, unknown>>(
  upn: string,
  text: string,
  params: Record<string, unknown> = {},
): Promise<T[]> {
  const pool = await getPool()
  const request = pool.request()
  request.input('UPN', sql.VarChar(256), upn)
  for (const [name, value] of Object.entries(params)) {
    request.input(name, value)
  }
  const result = await request.query<T>(text)
  return result.recordset
}

/**
 * Call a writeable wrapper stored proc. This is the ONLY write path: the SP has no direct
 * INSERT/UPDATE/DELETE -- ownership chaining lets each proc write its own fact tables, so we
 * only ever EXECUTE the procs (see `sql/security/grant_webapp_sp.sql`). Wrapper procs have no
 * OUTPUT clause (a Fabric Warehouse limitation), so this resolves to void; read the row back
 * with a follow-up query if confirmation is needed. `inputs` maps proc param name -> value;
 * mssql infers SQL types from the JS values (our wrapper params are VARCHAR / INT).
 *
 * Proven against `usp_InsertSubmissionAudit` 2026-06-19 (B4): the audit row lands and reads back.
 */
export async function execProc(procName: string, inputs: Record<string, unknown> = {}): Promise<void> {
  const pool = await getPool()
  const request = pool.request()
  for (const [name, value] of Object.entries(inputs)) {
    request.input(name, value)
  }
  await request.execute(procName)
}
