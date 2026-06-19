import { NextResponse } from 'next/server'
import sql from 'mssql'

// TEMPORARY diagnostic — SP connectivity probe (Phase 3b/B3). Tries the Fabric SQL
// connection with cert verification OFF and ON to isolate TLS/cert vs transport issues.
// Remove before any real deployment.
export const dynamic = 'force-dynamic'

function cfg(trust: boolean): sql.config {
  return {
    server: process.env.FABRIC_SQL_SERVER ?? '',
    database: process.env.FABRIC_SQL_DATABASE ?? '',
    port: 1433,
    connectionTimeout: 30000,
    options: { encrypt: true, trustServerCertificate: trust },
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

async function tryConn(trust: boolean) {
  let pool: sql.ConnectionPool | null = null
  try {
    pool = await new sql.ConnectionPool(cfg(trust)).connect()
    const r = await pool.request().query('SELECT DB_NAME() AS db_name, CAST(CURRENT_USER AS VARCHAR(200)) AS connected_as')
    return { ok: true, ...r.recordset[0] }
  } catch (e) {
    const err = e as { message?: string; code?: string; originalError?: unknown }
    return {
      ok: false,
      message: err?.message,
      code: err?.code,
      original: err?.originalError instanceof Error ? err.originalError.message : err?.originalError ? String(err.originalError) : undefined,
    }
  } finally {
    try { await pool?.close() } catch {}
  }
}

export async function GET() {
  const trustFalse = await tryConn(false)
  const trustTrue = await tryConn(true)
  return NextResponse.json({ trustFalse, trustTrue })
}
