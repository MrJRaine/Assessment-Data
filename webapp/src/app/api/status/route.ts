import { NextResponse } from 'next/server'
import { getMaintenanceWindow } from '@/lib/data'

export const dynamic = 'force-dynamic'

// Public status endpoint for the client maintenance poller. Returns the scheduled window (UTC) plus
// the SERVER clock so each client can offset its own possibly-skewed laptop clock. The warehouse read
// is cached briefly so hundreds of polling tabs hit the DB at most once per CACHE_MS.
const CACHE_MS = 4_000

// NOTE: there is deliberately NO auto-expire (removed 2026-09-18). A window used to lapse ~10 min
// past T so a forgotten one would self-heal — but that could bring the app back UP in the middle of a
// long maintenance job (e.g. deploying a batch of SQL scripts), with teachers writing against a
// half-migrated warehouse. The window now stays until it is EXPLICITLY cleared. That's safe because
// the sysadmin can clear from the banner, from the down overlay (which also offers sign-in, so a
// locked-out admin can switch accounts), or directly via usp_ClearMaintenanceWindow.

let cache: { at: string | null; message: string | null; fetchedAt: number } | null = null

export async function GET() {
  const now = Date.now()
  if (!cache || now - cache.fetchedAt > CACHE_MS) {
    try {
      const w = await getMaintenanceWindow()
      cache = { at: w.maintenanceAt, message: w.message, fetchedAt: now }
    } catch {
      // Fail OPEN: a transient DB error must not lock everyone out — report no window.
      cache = { at: null, message: null, fetchedAt: now }
    }
  }

  const maintenanceAt = cache.at

  return NextResponse.json(
    {
      maintenanceAt,
      message: maintenanceAt ? cache.message : null,
      serverNow: new Date().toISOString(),
    },
    { headers: { 'Cache-Control': 'no-store' } },
  )
}
