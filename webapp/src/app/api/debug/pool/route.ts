// LOAD-TEST ONLY: connection-pool + event-loop telemetry. Key-gated, and 404 unless the bypass is on
// (so it can't leak on a normal build). Poll this during a run to SEE the pool saturate:
//   pending > 0 while borrowed == max  ⇒ the pool is the bottleneck (raise FABRIC_POOL_MAX).
//   eventLoop.p99 climbing              ⇒ the Node/VM is the bottleneck.
// This file must never reach main.
import { monitorEventLoopDelay } from 'node:perf_hooks'
import { poolSnapshot } from '@/lib/db'
import { loadtestBypassEnabled, keyMatches, LOADTEST_KEY_HEADER } from '@/lib/loadtest'

export const dynamic = 'force-dynamic'

// Started once when the route module loads; reset after each poll so each reading covers the interval
// since the previous poll (a usable time series rather than a since-boot cumulative).
const loopDelay = monitorEventLoopDelay({ resolution: 20 })
loopDelay.enable()

const nsToMs = (n: number) => (Number.isFinite(n) ? Math.round((n / 1e6) * 100) / 100 : null)

export async function GET(req: Request) {
  if (!loadtestBypassEnabled()) return new Response('Not found', { status: 404 })
  if (!keyMatches(req.headers.get(LOADTEST_KEY_HEADER))) {
    return new Response('Unauthorized (load-test key required)', { status: 401 })
  }
  const pool = await poolSnapshot()
  const eventLoop = { meanMs: nsToMs(loopDelay.mean), maxMs: nsToMs(loopDelay.max), p99Ms: nsToMs(loopDelay.percentile(99)) }
  loopDelay.reset()
  return Response.json({ ts: new Date().toISOString(), pool, eventLoop })
}
