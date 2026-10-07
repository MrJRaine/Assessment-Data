/**
 * Client-side entry-draft persistence for the data-entry grids (reading / writing / math).
 *
 * WHY: a save-time crash or a hard refresh/closed tab would otherwise lose a teacher's unsaved
 * entries (the grid state is in-memory React state). This stashes the UNSAVED edits in localStorage
 * so they survive a reload for a short window, and restores them on the next open.
 *
 * PRIVACY: the draft is keyed by the grid's own keys — surrogate `studentKey` (reading/writing) or
 * `studentKey:taskKey` (math) — and stores ONLY scores/levels. It never contains a student number or
 * name, so the data at rest is far less identifying than the live grid (surrogate keys are
 * meaningless outside the warehouse). 90-minute TTL + reconcile-on-restore + auto-clear when the grid
 * is clean keep it short-lived. All access is wrapped in try/catch: localStorage can be unavailable
 * (private mode) or throw, in which case persistence silently no-ops and the grid still works.
 */

const TTL_MS = 90 * 60 * 1000 // 90 minutes

type Stored<T> = { t: number; v: Record<string, T> }

/** Namespaced key for one (subject, window, group) grid. */
export function draftKey(subject: string, windowId: string, groupKey: string): string {
  return `scor:draft:${subject}:${windowId}:${groupKey}`
}

/**
 * Read + reconcile a draft. Returns the entries whose student is still on the roster (the
 * studentKey portion of the entry key, before any ':', must be in validKeys), the count dropped
 * because their roster changed, or null if there's no fresh draft. Expired/garbage drafts are purged.
 */
export function readDraft<T>(key: string, validKeys: Set<string>): { v: Record<string, T>; dropped: number } | null {
  try {
    const raw = localStorage.getItem(key)
    if (!raw) return null
    const parsed = JSON.parse(raw) as Stored<T>
    if (!parsed || typeof parsed.t !== 'number' || !parsed.v || Date.now() - parsed.t > TTL_MS) {
      localStorage.removeItem(key)
      return null
    }
    const v: Record<string, T> = {}
    let dropped = 0
    for (const [k, val] of Object.entries(parsed.v)) {
      if (validKeys.has(k.split(':')[0])) v[k] = val
      else dropped++
    }
    if (Object.keys(v).length === 0) return dropped > 0 ? { v, dropped } : null
    return { v, dropped }
  } catch {
    return null
  }
}

/** Write the dirty subset; an empty map clears the key (so a clean grid leaves nothing behind). */
export function writeDraft<T>(key: string, v: Record<string, T>): void {
  try {
    if (!v || Object.keys(v).length === 0) {
      localStorage.removeItem(key)
      return
    }
    localStorage.setItem(key, JSON.stringify({ t: Date.now(), v }))
  } catch {
    /* storage unavailable/full — persistence is best-effort */
  }
}

export function clearDraft(key: string): void {
  try {
    localStorage.removeItem(key)
  } catch {
    /* no-op */
  }
}
