// Teacher-facing release notes for the in-app "What's new" popup (opened from the version footer).
//
// SINGLE SOURCE for the footer: APP_VERSION is the newest entry's version, and every release adds
// its entry at the TOP of PATCH_NOTES — so the footer version always matches the running build and
// the popup always has notes for it. Keep this in sync with CHANGELOG.md + webapp/package.json at
// each release, but write these lines for TEACHERS: plain language, no developer jargon, and avoid
// the word "assessment" (the app's user-facing copy rule). Newest first.

export interface PatchNote {
  version: string
  date: string // ISO date the version shipped
  kind: 'feature' | 'fix'
  summary: string
}

export const PATCH_NOTES: PatchNote[] = [
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

// "0.4.1" -> "0.4"
function minorOf(version: string): string {
  const parts = version.split('.')
  return `${parts[0]}.${parts[1]}`
}

// The running build's version = the newest note (releases always add their entry on top).
export const APP_VERSION: string = PATCH_NOTES[0].version
export const CURRENT_MINOR: string = minorOf(APP_VERSION)

// Notes for the current minor line only — the .0 plus any hotfixes (e.g. every 0.4.x entry).
export function currentMinorNotes(): PatchNote[] {
  return PATCH_NOTES.filter((n) => minorOf(n.version) === CURRENT_MINOR)
}
