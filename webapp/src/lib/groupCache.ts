import 'server-only'
import type { TeacherGroup } from './data'

/**
 * Short-lived, per-process cache for tvf_TeacherGroups results.
 *
 * WHY: that TVF measures 1.4-2.2s, and the entry flow calls it TWICE for a single journey -- once on
 * the picker to draw the cards, then again on the roster page, which needs the same rows for the
 * class label, its language, and which cycle instance(s) it falls under. The second call re-derives
 * something we computed seconds earlier.
 *
 * WHY NOT pass those values through the URL instead: they would become user-controlled input on a
 * page that decides which window a save is routed to. The roster TVF enforces access on its own, so
 * it would not leak another teacher's students -- but "probably safe" is not a good enough reason to
 * move an access-adjacent value into the query string.
 *
 * STALENESS: keyed per (user, cycle, subject) and 30s TTL, so a teacher navigating picker -> roster
 * hits the cache while a teacher returning minutes later does not. The cached rows carry entered /
 * applicable COUNTS, which change the moment someone saves -- so the save actions call
 * `invalidateGroups(upn)` and the next read is fresh. Without that a teacher would save, go back, and
 * see their old progress, which is exactly the kind of thing that erodes trust in the numbers.
 *
 * Per-process: with several app containers each keeps its own copy. That is fine at this TTL -- the
 * worst case is one container serving 30s-old counts, and a save invalidates the container that
 * handled it, which is the same one the user is talking to.
 */
const TTL_MS = 30_000

type Entry = { at: number; groups: TeacherGroup[] }
const cache = new Map<string, Entry>()

const keyOf = (upn: string, cycleGroupId: string, assessmentType: string) =>
  `${upn.toLowerCase()}|${cycleGroupId}|${assessmentType}`

export function readGroups(upn: string, cycleGroupId: string, assessmentType: string): TeacherGroup[] | null {
  const hit = cache.get(keyOf(upn, cycleGroupId, assessmentType))
  if (!hit) return null
  if (Date.now() - hit.at > TTL_MS) return null
  return hit.groups
}

export function writeGroups(upn: string, cycleGroupId: string, assessmentType: string, groups: TeacherGroup[]): void {
  // Opportunistic sweep of expired entries -- keeps the map from growing unbounded across a long
  // uptime without needing a timer. Cheap: this map holds one entry per (user, cycle, subject).
  const now = Date.now()
  for (const [k, v] of cache) if (now - v.at > TTL_MS) cache.delete(k)
  cache.set(keyOf(upn, cycleGroupId, assessmentType), { at: now, groups })
}

/** Drop every cached entry for one user — called after a save, so progress counts are never stale. */
export function invalidateGroups(upn: string): void {
  const prefix = `${upn.toLowerCase()}|`
  for (const k of cache.keys()) if (k.startsWith(prefix)) cache.delete(k)
}

/** Everyone — called after an ingest, which is precisely what moves students between sections. */
export function invalidateAllGroups(): void {
  cache.clear()
}
