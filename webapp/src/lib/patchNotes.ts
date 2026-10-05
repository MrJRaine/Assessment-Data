// Teacher-facing release notes for the in-app "What's new" popup (opened from the version footer).
//
// The footer VERSION comes from webapp/package.json (via NEXT_PUBLIC_APP_VERSION) so it always matches
// the running build. This list STARTS FRESH at the 1.0.0 production launch — it holds ONLY the 1.0.0
// entry, by deliberate decision (the in-app What's New shows the v1.0.0 launch and nothing before it).
// The full pre-1.0 history lives in CHANGELOG.md, NOT here. Going forward, add an entry when a
// user-VISIBLE change ships; write for TEACHERS: plain language, no developer jargon, avoid the word
// "assessment". Newest first.

export interface PatchNote {
  version: string
  date: string // ISO date the version shipped (for dev entries, the date last touched)
  kind: 'feature' | 'fix'
  summary: string
}

export const PATCH_NOTES: PatchNote[] = [
  {
    version: '1.1.0',
    date: '2026-10-05',
    kind: 'feature',
    summary:
      'On the Reports cohort table you can now sort by any column — click a heading to sort, click it again to reverse. The table shows Homeroom instead of Program (Program is still a filter), and Reading adds a "Diff from Expected" column showing how far each student’s latest level is above or below the expected benchmark. The total now counts only the students actually assessed for the subject (e.g. Reading grades Primary–8) — flip "Assessable grades only" off to include everyone.',
  },
  {
    version: '1.0.0',
    date: '2026-10-02',
    kind: 'feature',
    summary: 'Version 1.0 — the first full release of the SCoR Dashboard.',
  },
]

// The running build's version — from package.json (NEXT_PUBLIC_APP_VERSION), so the footer never
// drifts from the actual build. Falls back to the newest note if the env isn't set.
export const APP_VERSION: string = process.env.NEXT_PUBLIC_APP_VERSION ?? PATCH_NOTES[0]?.version ?? '0.0.0'

// Numeric key for a minor line: "0.5.0-dev" -> 5, "0.4.1" -> 4 (major*1000 + minor).
function minorKey(version: string): number {
  const [maj, min] = version.split('.')
  return Number(maj) * 1000 + Number(min)
}

// Notes for the CURRENT minor line plus the PREVIOUS one — so the popup shows changes back through
// the last minor (e.g. on 0.5.x it lists every 0.5.x AND 0.4.x note).
export function recentNotes(): PatchNote[] {
  const cur = minorKey(APP_VERSION)
  const below = PATCH_NOTES.map((n) => minorKey(n.version)).filter((k) => k < cur)
  const prev = below.length ? Math.max(...below) : cur
  return PATCH_NOTES.filter((n) => {
    const k = minorKey(n.version)
    return k === cur || k === prev
  })
}
