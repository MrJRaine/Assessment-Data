import { NextResponse } from 'next/server'
import { query } from '@/lib/db'

// TEMPORARY diagnostic -- SP connectivity probe (Phase 3b/B3). Runs one trivial query to
// confirm the service principal can reach Fabric via the @azure/identity token + mssql path.
// Remove before any real deployment (unauthenticated + touches the DB).
export const dynamic = 'force-dynamic'

export async function GET() {
  try {
    const rows = await query<{ db_name: string; connected_as: string }>(
      'SELECT DB_NAME() AS db_name, CAST(CURRENT_USER AS VARCHAR(200)) AS connected_as',
    )
    return NextResponse.json({ ok: true, auth: 'entra-access-token', result: rows[0] ?? null })
  } catch (e) {
    const err = e as { message?: string; code?: string; originalError?: unknown }
    return NextResponse.json({
      ok: false,
      auth: 'entra-access-token',
      message: err?.message,
      code: err?.code,
      original: err?.originalError instanceof Error ? err.originalError.message : undefined,
    })
  }
}
