# syntax=docker/dockerfile:1
# Multi-stage build for the Next.js (standalone) app. OCI-standard, so it builds and runs
# unchanged under Podman (`podman build` / `podman run`) or any other OCI engine.
#
# Driver note: the Fabric connection is pure JavaScript -- `@azure/identity` mints an Entra
# access token and `mssql` (tedious) connects with it (azure-active-directory-access-token).
# No native ODBC driver is needed, so the image stays on a minimal Alpine base.
#
# node_modules note: `mssql` loads its `tedious` driver via a DYNAMIC require, which Next's
# standalone file-tracer cannot follow -- so tedious is omitted from the traced output and the
# connection dies (ESOCKET). We therefore ship the full PRODUCTION node_modules into the runner
# (proddeps stage) and overlay the standalone server on top, so the dynamic require resolves to
# the real, un-bundled driver. `serverExternalPackages` keeps the DB stack out of the webpack
# bundle (the bundled tedious is broken), so the runtime uses these node_modules.

# ---- deps: full install (dev + prod) for the build ----
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci || npm install

# ---- builder: compile the standalone server ----
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

# ---- proddeps: production-only node_modules for the runtime ----
FROM node:20-alpine AS proddeps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev || npm install --omit=dev

# ---- runner: minimal non-root runtime image ----
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

# run as an unprivileged user (aligns with Podman's rootless model)
RUN addgroup -g 1001 -S nodejs && adduser -S nextjs -u 1001

# production node_modules first -- includes the dynamically-required `tedious` driver, which
# Next's standalone file-tracer cannot follow (mssql loads it via a dynamic require), so it must
# be present on disk rather than relying on the trace...
COPY --from=proddeps --chown=nextjs:nodejs /app/node_modules ./node_modules
# ...then overlay the standalone server (its curated next runtime + server.js win on conflict).
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# secret preloader: maps any *_FILE-mounted secrets to env vars before the server starts
# (run via --require so it executes in-process ahead of server.js; no-op when no *_FILE set).
COPY --chown=nextjs:nodejs load-secrets.cjs ./

USER nextjs
EXPOSE 3000
CMD ["node", "--require", "./load-secrets.cjs", "server.js"]
