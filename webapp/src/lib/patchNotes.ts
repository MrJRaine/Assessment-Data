// Teacher-facing release notes for the in-app "What's new" popup (opened from the version footer).
//
// The footer VERSION comes from webapp/package.json (via NEXT_PUBLIC_APP_VERSION) so it always matches
// the running build. This file is the teacher-facing note list the popup shows — the current minor
// line PLUS the previous one (so a reader sees changes back through the last minor, e.g. 0.5.x shows
// 0.5.x + all 0.4.x). Add an entry when a user-VISIBLE change ships; keep it in sync with CHANGELOG.md
// (the full developer history) — and write these for TEACHERS: plain language, no developer jargon,
// avoid the word "assessment". Newest first.

export interface PatchNote {
  version: string
  date: string // ISO date the version shipped (for dev entries, the date last touched)
  kind: 'feature' | 'fix'
  summary: string
}

export const PATCH_NOTES: PatchNote[] = [
  {
    version: '0.5.0-dev',
    date: '2026-09-17',
    kind: 'feature',
    summary:
      'The “IPPs” area is now “Programming” — confirm both Individual Program Plans and Adaptations for each student by subject (Reading, Writing, Math), with a colour cue showing how much is left to confirm.',
  },
  {
    version: '0.5.0-dev',
    date: '2026-09-17',
    kind: 'feature',
    summary:
      'Math Short Cycles for Primary–grade 6: record can-do / not-yet for each task, with by-task and by-student summaries.',
  },
  {
    version: '0.5.0-dev',
    date: '2026-09-17',
    kind: 'feature',
    summary:
      'Choosing a class is easier — pick by homeroom, by course section, or by a whole grade, with school and grade filters.',
  },
  {
    version: '0.5.0-dev',
    date: '2026-09-17',
    kind: 'feature',
    summary:
      'A heads-up banner now appears ahead of scheduled maintenance so you have time to save your work before the app briefly restarts.',
  },
  {
    version: '0.4.1',
    date: '2026-09-11',
    kind: 'fix',
    summary:
      'The “Diff from Prev Cycle” column now fills in on the first cycle of the year — it compares back to the student’s June starting point, so it reads the same as “Since June” until a second cycle exists.',
  },
  {
    version: '0.4.0',
    date: '2026-09-10',
    kind: 'feature',
    summary:
      'Reading rosters now show each student’s June starting level (“Prev June”) and how many levels they’ve moved since (“Since June”).',
  },
  {
    version: '0.4.0',
    date: '2026-09-10',
    kind: 'feature',
    summary:
      'In grade 7 and 8, students who already meet the expected level are hidden at the start of a cycle to keep the list focused — open the Students list to show them.',
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
