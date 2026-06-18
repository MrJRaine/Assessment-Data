import { NextResponse } from 'next/server'
import { getReadiness } from '@/lib/readiness'

export const dynamic = 'force-dynamic'

// Liveness + config readiness. Does NOT open a DB connection.
export function GET() {
  return NextResponse.json({ status: 'ok', ...getReadiness() })
}
