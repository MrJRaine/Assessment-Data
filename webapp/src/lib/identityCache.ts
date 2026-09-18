import 'server-only'
import type { CallerCapabilities } from './data'

/**
 * Per-process cache of the signed-in user's ACCESS LEVEL and CAPABILITIES.
 *
 * WHY: AppShell resolves both on EVERY navigation — `DimStaff.AccessLevel` and the `StaffAppAccess`
 * allowlist — so each page load pays two warehouse round trips before rendering anything. Measured
 * between 106ms and 1201ms for the same trivial lookup, which at ~200 teachers is tax on every click.
 *
 * WHY A 1 HOUR TTL IS SAFE HERE: staff data lands through the WEEKLY PowerSchool ingest, not
 * continuously, so a role or capability changing mid-session is effectively impossible — and the
 * ingest run clears this cache anyway (`invalidateAllIdentities`). The only thing a stale entry could
 * do is let someone keep a capability slightly past its revocation; with a weekly, controlled ingest
 * window that is not a live risk, and the invalidation closes it the moment the data changes.
 *
 * Kept SERVER-SIDE rather than folded into the NextAuth JWT deliberately: a cookie-borne capability
 * cannot be revoked before it expires, whereas this can be dropped the instant the data behind it
 * moves. Per-process, so several containers each hold their own copy — fine, since the same ingest
 * clears all of them and the worst case is one extra lookup per container.
 *
 * The two halves are cached INDEPENDENTLY: they come from different queries and different callers,
 * and pairing them would mean either a partially-filled entry or a fake dependency between them.
 */
const TTL_MS = 60 * 60_000 // 1 hour

type Entry<T> = { at: number; value: T }

const accessLevels = new Map<string, Entry<string | null>>()
const capabilities = new Map<string, Entry<CallerCapabilities>>()

const keyOf = (upn: string) => upn.toLowerCase()

function read<T>(store: Map<string, Entry<T>>, upn: string): { hit: true; value: T } | { hit: false } {
  const e = store.get(keyOf(upn))
  if (!e) return { hit: false }
  if (Date.now() - e.at > TTL_MS) {
    store.delete(keyOf(upn))
    return { hit: false }
  }
  // Wrapped rather than returned bare: `null` is a VALID access level (a classroom teacher), so a
  // bare return could not distinguish "cached as teacher" from "not cached".
  return { hit: true, value: e.value }
}

function write<T>(store: Map<string, Entry<T>>, upn: string, value: T): void {
  const now = Date.now()
  for (const [k, v] of store) if (now - v.at > TTL_MS) store.delete(k) // opportunistic sweep
  store.set(keyOf(upn), { at: now, value })
}

export const readAccessLevel = (upn: string) => read(accessLevels, upn)
export const writeAccessLevel = (upn: string, v: string | null) => write(accessLevels, upn, v)
export const readCapabilities = (upn: string) => read(capabilities, upn)
export const writeCapabilities = (upn: string, v: CallerCapabilities) => write(capabilities, upn, v)

/** One user — e.g. their capabilities were just edited. */
export function invalidateIdentity(upn: string): void {
  accessLevels.delete(keyOf(upn))
  capabilities.delete(keyOf(upn))
}

/**
 * Everyone — call after an ingest cycle, which rewrites DimStaff and can change roles or school
 * access. This is what keeps the 1h TTL honest: capabilities are never stale past the moment the
 * data behind them actually changed.
 */
export function invalidateAllIdentities(): void {
  accessLevels.clear()
  capabilities.clear()
}
