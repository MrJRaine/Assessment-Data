import { NextResponse } from 'next/server'
import { getReadiness } from '@/lib/readiness'

export const dynamic = 'force-dynamic'

// Liveness probe (unauthenticated). Returns bare {status:'ok'} in production so it discloses no
// config posture; the detailed readiness is exposed only in the explicit dev-diagnostic mode.
export function GET() {
  const devDiag = process.env.AUTH_MODE === 'dev' && process.env.ALLOW_DEV_AUTH === 'true'
  return NextResponse.json(devDiag ? { status: 'ok', ...getReadiness() } : { status: 'ok' })
}
