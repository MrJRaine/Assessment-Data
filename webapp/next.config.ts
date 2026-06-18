import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  // 'standalone' emits a minimal self-contained server (server.js + traced node_modules)
  // so the container image stays small. See Dockerfile runner stage.
  output: 'standalone',
}

export default nextConfig
