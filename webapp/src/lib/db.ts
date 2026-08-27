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
 * The pool authenticates with the access token at connect time. The token lives ~1h; the live TDS
 * session survives token expiry, BUT once the connection drops (Fabric idle-closes it) the pool
 * reconnects with the now-EXPIRED token baked into its config and every query fails with
 * "authentication failed" until the process restarts. So callers run through `runOnPool`, which
 * resets the pool on a connection/auth error and retries once with a freshly-minted token
 * (`buildConfig` re-acquires via `@azure/identity`, which refreshes near expiry).
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

// Connection/auth-level failures that mean "the pooled connection is dead / its token expired" —
// as opposed to a SQL error from the query itself (e.g. a proc THROW). On these we rebuild the pool.
function isStalePoolError(err: unknown): boolean {
  const e = err as { code?: unknown; message?: unknown }
  const code = typeof e?.code === 'string' ? e.code : ''
  const msg = (typeof e?.message === 'string' ? e.message : '').toLowerCase()
  return (
    code === 'ELOGIN' ||
    code === 'ESOCKET' ||
    code === 'ECONNCLOSED' ||
    code === 'ECONNRESET' ||
    code === 'ETIMEOUT' ||
    msg.includes('authentication failed') ||
    msg.includes('login failed') ||
    msg.includes('socket hang up') ||
    msg.includes('connection is closed') ||
    msg.includes('connection lost')
  )
}

/**
 * Run an operation against the pool, self-healing a stale/expired connection: on a connection-level
 * error, drop the cached pool (so the next getPool re-acquires a fresh token) and retry ONCE. Safe to
 * retry our writes too — the wrapper procs are idempotent on (Student, Window, Date), so a re-run is
 * a no-op/correction, not a duplicate. A genuine SQL error (proc THROW, bad param) is NOT a stale-pool
 * error, so it propagates immediately without a retry.
 */
async function runOnPool<T>(fn: (pool: sql.ConnectionPool) => Promise<T>): Promise<T> {
  try {
    return await fn(await getPool())
  } catch (err) {
    if (!isStalePoolError(err)) throw err
    const stale = poolPromise
    poolPromise = null
    if (stale) stale.then((p) => p.close()).catch(() => {}) // best-effort close of the dead pool
    return await fn(await getPool())
  }
}

/** Run a query that takes no per-user filtering (e.g. reference/lookup reads). */
export async function query<T extends Record<string, unknown> = Record<string, unknown>>(
  text: string,
  params: Record<string, unknown> = {},
): Promise<T[]> {
  return runOnPool(async (pool) => {
    const request = pool.request()
    for (const [name, value] of Object.entries(params)) {
      request.input(name, value)
    }
    const result = await request.query<T>(text)
    return result.recordset
  })
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
  return runOnPool(async (pool) => {
    const request = pool.request()
    request.input('UPN', sql.VarChar(256), upn)
    for (const [name, value] of Object.entries(params)) {
      request.input(name, value)
    }
    const result = await request.query<T>(text)
    return result.recordset
  })
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
  await runOnPool(async (pool) => {
    const request = pool.request()
    for (const [name, value] of Object.entries(inputs)) {
      request.input(name, value)
    }
    await request.execute(procName)
  })
}
