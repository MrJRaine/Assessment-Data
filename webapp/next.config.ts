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
}

export default nextConfig
