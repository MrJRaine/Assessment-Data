import { NextResponse } from 'next/server'
import { getMaintenanceWindow } from '@/lib/data'

export const dynamic = 'force-dynamic'

// Public status endpoint for the client maintenance poller. Returns the scheduled window (UTC) plus
// the SERVER clock so each client can offset its own possibly-skewed laptop clock. The warehouse read
// is cached briefly so hundreds of polling tabs hit the DB at most once per CACHE_MS.
const CACHE_MS = 4_000
// Ignore a window well past T (a forgotten "all clear") so the app self-heals after a swap; an
// explicit clear lifts it immediately.
const AUTO_EXPIRE_MS = 10 * 60_000

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

  let maintenanceAt = cache.at
  if (maintenanceAt && Date.now() > new Date(maintenanceAt).getTime() + AUTO_EXPIRE_MS) {
    maintenanceAt = null // auto-expired
  }

  return NextResponse.json(
    {
      maintenanceAt,
      message: maintenanceAt ? cache.message : null,
      serverNow: new Date().toISOString(),
    },
    { headers: { 'Cache-Control': 'no-store' } },
  )
}
