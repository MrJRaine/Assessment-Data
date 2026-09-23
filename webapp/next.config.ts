import type { NextConfig } from 'next'
import { readFileSync } from 'node:fs'

// Single source of truth for the app version = webapp/package.json. Exposed to the browser so the
// footer always shows the ACTUAL running version (no drift vs. the patch-notes list).
const appVersion = (JSON.parse(readFileSync('./package.json', 'utf8')) as { version: string }).version

const nextConfig: NextConfig = {
  env: { NEXT_PUBLIC_APP_VERSION: appVersion },
  // 'standalone' emits a minimal self-contained server (server.js + traced node_modules)
  // so the container image stays small. See Dockerfile runner stage.
  output: 'standalone',
  // Disable Next's built-in gzip. The app is reverse-proxied by IIS/ARR, and Next's compression
  // BUFFERS the response to compress it — which killed streaming (Suspense) on the slow roster
  // routes behind the proxy: the loading shell never flushed, so a click looked like a dead hang.
  // Setting Content-Encoding here is the origin buffer that responseBufferLimit=0 and disabling IIS
  // dynamic compression could not fix (both are downstream of it). Streamed responses now go out
  // uncompressed + chunked and flush immediately. IIS DYNAMIC COMPRESSION MUST STAY OFF (else it
  // re-gzips + re-buffers the now-uncompressed HTML). Static JS/CSS compression is separate. (0.6.1)
  compress: false,
  // The DB stack must NOT be webpack-bundled: tedious's connection internals break when
  // bundled (the socket opens then drops -> ESOCKET). Keep them external so they are required
  // from node_modules at runtime (traced into the standalone output). Verified: token auth
  // works un-bundled on both Alpine and Debian; only the bundled build failed.
  serverExternalPackages: ['mssql', 'tedious', '@azure/identity'],
  // Ingest uploads PS exports via a Server Action (default body cap is 1 MB — too small for a
  // full-rollout enrollments export). Raise to 30 MB; the action enforces a 25 MB per-file cap.
  experimental: {
    serverActions: { bodySizeLimit: '30mb' },
  },
  // Baseline security headers on every response. (CSP intentionally omitted for now — a strict
  // policy needs per-request nonces for Next's inline bootstrap scripts; add via middleware as a
  // follow-up. X-Frame-Options=DENY for now; relax to frame-ancestors for the Teams embed later.)
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          { key: 'Strict-Transport-Security', value: 'max-age=31536000; includeSubDomains' },
        ],
      },
    ]
  },
  // The Student Data page was renamed to "Reports" and its route moved /students -> /reports
  // (2026-09-21). Keep the old path working so existing bookmarks / any Teams-embedded links don't
  // 404. permanent:true (308) preserves the request method and tells browsers/crawlers it's final.
  // These run BEFORE middleware, so an unauthenticated hit on /students redirects to /reports and
  // is then auth-gated there.
  async redirects() {
    return [
      { source: '/students', destination: '/reports', permanent: true },
      { source: '/students/:path*', destination: '/reports/:path*', permanent: true },
    ]
  },
}

export default nextConfig
