/**
 * LOAD-TEST AUTH BYPASS — isolated module. **This file must never appear on `main`.**
 *
 * It exists only on the `loadtest` branch (cut from `dev-impersonation`) to let a Locust cluster
 * drive the app WITHOUT Microsoft Entra sign-in, so the VM's serving capacity + the connection-pool
 * ceiling can be measured. It is active ONLY when LOADTEST_AUTH_BYPASS=true, and a boot-time guard
 * (assertLoadtestSafe, called from instrumentation.ts) REFUSES to start the container unless it is
 * pointed at a *_Dev warehouse, off the live host, with a key set. No production, no real data.
 *
 * Edge-safe: no `server-only`, no `next/headers`, no Node-only APIs — so the middleware (Edge bundle)
 * can import it. Server-side identity resolution (getCurrentUpn) imports it too.
 */

export const LOADTEST_KEY_HEADER = 'x-loadtest-key'
export const LOADTEST_USER_HEADER = 'x-loadtest-user'
const LIVE_HOST = 'data.tcrce.ca'

/** Master switch. Everything below is inert unless this is true. */
export function loadtestBypassEnabled(): boolean {
  return process.env.LOADTEST_AUTH_BYPASS === 'true'
}

/**
 * FAIL-CLOSED startup guard. Throws (⇒ container refuses to boot) if the bypass is enabled in any
 * configuration that could touch production. Called from instrumentation.register() at startup, where
 * the Node runtime makes process.env fully reliable.
 */
export function assertLoadtestSafe(env: NodeJS.ProcessEnv = process.env): void {
  if (env.LOADTEST_AUTH_BYPASS !== 'true') return
  const problems: string[] = []

  const authUrl = (env.AUTH_URL ?? '').toLowerCase()
  if (authUrl.includes(LIVE_HOST)) problems.push(`AUTH_URL points at the live host (${LIVE_HOST})`)

  const db = env.FABRIC_SQL_DATABASE ?? ''
  if (!/_dev$/i.test(db)) problems.push(`FABRIC_SQL_DATABASE is not a *_Dev warehouse (got "${db || '<unset>'}")`)

  if ((env.AUTH_MODE ?? '').toLowerCase() !== 'dev' || env.ALLOW_DEV_AUTH !== 'true') {
    problems.push('LOADTEST_AUTH_BYPASS requires AUTH_MODE=dev + ALLOW_DEV_AUTH=true (so the existing dev-auth guards stack)')
  }
  if (!env.LOADTEST_KEY) problems.push('LOADTEST_KEY is unset — the bypass gate would accept every request')

  if (problems.length > 0) {
    throw new Error(
      'REFUSING TO START — LOADTEST_AUTH_BYPASS=true in an unsafe configuration:\n  - ' +
        problems.join('\n  - ') +
        '\nThe load-test bypass may run ONLY against a *_Dev warehouse, off the live host, with a key set.',
    )
  }
}

/** Prominent startup banner, logged whenever the bypass is active. */
export function loadtestBanner(): string {
  return [
    '',
    '████████████████████████████████████████████████████████████████████',
    '█  LOAD-TEST AUTH BYPASS IS ACTIVE (LOADTEST_AUTH_BYPASS=true)      █',
    '█  Entra sign-in is DISABLED. Requests are gated by X-Loadtest-Key. █',
    `█  Warehouse: ${(process.env.FABRIC_SQL_DATABASE ?? '<unset>').padEnd(52)}█`,
    '█  This build MUST NOT run against production. Dev data only.       █',
    '████████████████████████████████████████████████████████████████████',
    '',
  ].join('\n')
}

/** Constant-time-ish equality is overkill here (dev-data-only), so a plain compare. */
export function keyMatches(headerVal: string | null | undefined): boolean {
  const key = process.env.LOADTEST_KEY
  return typeof key === 'string' && key.length > 0 && headerVal === key
}

/** Allow-list of impersonatable UPNs (comma/space separated), lowercased. Empty ⇒ only DEV_FAKE_UPN. */
export function allowedLoadtestUsers(): Set<string> {
  const list = (process.env.LOADTEST_USERS ?? '')
    .split(/[,\s]+/)
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean)
  if (list.length === 0 && process.env.DEV_FAKE_UPN) list.push(process.env.DEV_FAKE_UPN.toLowerCase())
  return new Set(list)
}

/** The impersonated identity for a request: the header value IF it's on the allow-list, else null. */
export function resolveLoadtestUser(headerVal: string | null | undefined): string | null {
  if (!headerVal) return null
  const upn = headerVal.trim()
  return upn.length > 0 && allowedLoadtestUsers().has(upn.toLowerCase()) ? upn : null
}

/** Best-effort client IP (no reverse proxy on this path, so usually null — see cidrAllowed). */
export function clientIp(req: { headers: { get(name: string): string | null } }): string | null {
  const xr = req.headers.get('x-real-ip')
  if (xr) return xr.trim()
  const xff = req.headers.get('x-forwarded-for')
  if (xff) return xff.split(',')[0]?.trim() || null
  return null
}

/**
 * Advisory CIDR allow-list (LOADTEST_ALLOWED_CIDRS, IPv4). Unset ⇒ allow (rely on the test VLAN +
 * the key). Because this path is DIRECT (no proxy) and Next 15 dropped NextRequest.ip, the app can't
 * reliably see the peer IP, so when CIDRs are set but the IP is unknown we ALLOW and let the network
 * be the perimeter — locking to "deny on unknown IP" would just break the test. The VLAN firewall is
 * the real boundary; the key is the app gate; this is defence-in-depth only.
 */
export function cidrAllowed(ip: string | null | undefined): boolean {
  const cidrs = (process.env.LOADTEST_ALLOWED_CIDRS ?? '').split(/[,\s]+/).map((s) => s.trim()).filter(Boolean)
  if (cidrs.length === 0) return true
  if (!ip) return true // unknown peer IP on a direct connection — advisory only
  return cidrs.some((c) => ipv4InCidr(ip, c))
}

function ipToInt(ip: string): number | null {
  const parts = ip.split('.')
  if (parts.length !== 4) return null
  let n = 0
  for (const p of parts) {
    const o = Number(p)
    if (!Number.isInteger(o) || o < 0 || o > 255) return null
    n = ((n << 8) | o) >>> 0
  }
  return n >>> 0
}
function ipv4InCidr(ip: string, cidr: string): boolean {
  const [base, bitsStr] = cidr.split('/')
  const bits = Number(bitsStr)
  const ipN = ipToInt(ip)
  const baseN = ipToInt(base)
  if (ipN == null || baseN == null || !Number.isInteger(bits) || bits < 0 || bits > 32) return false
  if (bits === 0) return true
  const mask = (bits === 32 ? 0xffffffff : ~((1 << (32 - bits)) - 1)) >>> 0
  return (ipN & mask) === (baseN & mask)
}
