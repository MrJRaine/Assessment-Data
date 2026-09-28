// Auth.js (NextAuth v5) middleware, with the LOAD-TEST bypass layered in front.
//
// Normal path (bypass OFF): delegate to Auth.js `auth` — an unauthenticated request to a protected
// route redirects to /login → Entra. (In dev mode the `authorized` callback returns true, so nothing
// is gated; that's why plain dev mode is local-only.)
//
// Bypass path (LOADTEST_AUTH_BYPASS=true, loadtest branch only): NO Entra involvement. Every request
// to a protected route must carry X-Loadtest-Key matching LOADTEST_KEY (else 401) and pass the
// advisory CIDR allow-list (else 403). Identity is then resolved from X-Loadtest-User in getCurrentUpn.
// This file must never reach main.
import { NextResponse, type NextRequest, type NextFetchEvent } from 'next/server'
import { auth } from '@/auth'
import { keyMatches, cidrAllowed, clientIp, LOADTEST_KEY_HEADER } from '@/lib/loadtest'

export default function middleware(req: NextRequest, ev: NextFetchEvent) {
  if (process.env.LOADTEST_AUTH_BYPASS === 'true') {
    if (!keyMatches(req.headers.get(LOADTEST_KEY_HEADER))) {
      return new NextResponse('Unauthorized (load-test key required)', { status: 401 })
    }
    if (!cidrAllowed(clientIp(req))) {
      return new NextResponse('Forbidden (source not in LOADTEST_ALLOWED_CIDRS)', { status: 403 })
    }
    return NextResponse.next()
  }
  // Delegate to Auth.js for the normal Entra-gated path.
  return (auth as unknown as (req: NextRequest, ev: NextFetchEvent) => ReturnType<typeof NextResponse.next>)(req, ev)
}

export const config = {
  // Protect the functional routes that read Fabric data (all call getCurrentUpn()).
  // The landing page (/) stays public; NextAuth's /api/auth/*, /login, /api/health, and static assets
  // are intentionally excluded (health stays reachable for the pre-test sanity check).
  matcher: ['/enter/:path*', '/reports/:path*', '/programming/:path*', '/ipp/:path*', '/ingest/:path*', '/cycles/:path*', '/admin/:path*'],
}
