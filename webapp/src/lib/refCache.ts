import 'server-only'

/**
 * Per-process cache of STATIC reference data — reading-scale levels (`DimReadingScale`) and the
 * achievement bands (`DimAchievementLevel`).
 *
 * WHY: both are read on EVERY reading roster and every Reports load, serially, yet they are seeded
 * once and only ever change via a deploy — never through the weekly PowerSchool ingest. So the query
 * runs on each click for data that is effectively immutable at runtime. Caching removes two warehouse
 * round trips from the critical path of the slowest page we have (the roster).
 *
 * WHY THE LONG TTL IS SAFE: nothing at runtime mutates these tables. A scale/band change only lands
 * with a deploy, which restarts the container and empties this cache anyway. The TTL is just a
 * belt-and-suspenders refresh so a very long-lived process re-reads occasionally. Per-process, like
 * identityCache — each container holds its own copy; harmless, since the source only moves on deploy.
 */
const TTL_MS = 6 * 60 * 60_000 // 6 hours

type Entry<T> = { at: number; value: T }
const store = new Map<string, Entry<unknown>>()

export function readRef<T>(key: string): { hit: true; value: T } | { hit: false } {
  const e = store.get(key)
  if (!e) return { hit: false }
  if (Date.now() - e.at > TTL_MS) {
    store.delete(key)
    return { hit: false }
  }
  return { hit: true, value: e.value as T }
}

export function writeRef<T>(key: string, value: T): void {
  store.set(key, { at: Date.now(), value })
}

/** Drop all cached reference data (e.g. if a scale/band seed is redeployed without a restart). */
export function invalidateRefs(): void {
  store.clear()
}
