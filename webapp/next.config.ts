import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  // 'standalone' emits a minimal self-contained server (server.js + traced node_modules)
  // so the container image stays small. See Dockerfile runner stage.
  output: 'standalone',
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
}

export default nextConfig
