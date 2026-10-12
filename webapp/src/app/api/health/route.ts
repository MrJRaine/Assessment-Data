import { NextResponse } from 'next/server'

export const dynamic = 'force-dynamic'

// Liveness probe (unauthenticated). Returns bare {status:'ok'} so it discloses no config posture.
export function GET() {
  return NextResponse.json({ status: 'ok' })
}
