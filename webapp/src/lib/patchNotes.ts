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
    version: '0.7.0',
    date: '2026-09-24',
    kind: 'feature',
    summary:
      'Reports now has a Math view and an RWM view. Pick a class or grade to see a read-only Math results grid (laid out like the entry screen) with class and per-student roll-ups and charts. RWM gives each Primary–6 student a 0–3 score for how many of Reading, Writing, and Math they are currently meeting or exceeding.',
  },
  {
    version: '0.7.0',
    date: '2026-09-24',
    kind: 'feature',
    summary:
      'On the Reading report, each student now shows the expected level beside their current level, and the trend graph starts from last June so you can see the change across the year. The cohort table adds a "Diff from Prev June" column.',
  },
  {
    version: '0.7.0',
    date: '2026-09-24',
    kind: 'feature',
    summary:
      'After a Short Cycle closes you can still enter results for a grace period (7 days by default) — the cycle shows "Late entry" with the time left, then becomes view-only. If you need to enter something after that, designated staff can briefly unlock a group.',
  },
  {
    version: '0.7.0',
    date: '2026-09-24',
    kind: 'feature',
    summary:
      'Data Entry cards now show how many students are done. Reading and Writing show one "done" count (a single result finishes a student); Math splits it into "started" and "done", since a student can still have tasks left to record.',
  },
  {
    version: '0.6.3',
    date: '2026-09-24',
    kind: 'fix',
    summary:
      'On the Programming page, the IPPs and Adaptations progress labels now count students rather than each individual subject entry, so the totals reflect how many students actually need attention.',
  },
  {
    version: '0.6.2',
    date: '2026-09-23',
    kind: 'fix',
    summary:
      'Clicking a class or cycle card now responds right away — the card presses in and shows "Opening…" while the next page loads, instead of the click seeming to do nothing.',
  },
  {
    version: '0.6.2',
    date: '2026-09-23',
    kind: 'fix',
    summary:
      'Math fixes: the task list in "Edit checklist" is laid out properly again (one task per line), and the class and cycle cards now show how many students have their math entered.',
  },
  {
    version: '0.6.1',
    date: '2026-09-23',
    kind: 'fix',
    summary:
      'Opening a class no longer looks frozen. You now see a "Loading…" message right away, and the class roster fills in a moment later, instead of the click seeming to do nothing and then the whole page appearing at once.',
  },
  {
    version: '0.6.0',
    date: '2026-09-22',
    kind: 'feature',
    summary:
      'The app is now called The SCoR Hub. Everything works the same — only the name in the header changed. (Your Short Cycles of Response are still Short Cycles.)',
  },
  {
    version: '0.6.0',
    date: '2026-09-22',
    kind: 'feature',
    summary:
      'Math Short Cycles: French-Immersion classes now show the French answer key next to the French task text.',
  },
  {
    version: '0.5.0',
    date: '2026-09-21',
    kind: 'feature',
    summary:
      'The “Students” area is now “Reports” — the same cohort view and per-student history, renamed to match what it’s for. Old links to the Students page still work.',
  },
  {
    version: '0.5.0',
    date: '2026-09-17',
    kind: 'feature',
    summary:
      'Writing entry: Conventions can now be marked “Scribed” when someone else physically wrote for the student — scribed conventions are left out of the writing average.',
  },
  {
    version: '0.5.0',
    date: '2026-09-17',
    kind: 'feature',
    summary:
      'The “IPPs” area is now “Programming” — confirm both Individual Program Plans and Adaptations for each student by subject (Reading, Writing, Math), with a colour cue showing how much is left to confirm.',
  },
  {
    version: '0.5.0',
    date: '2026-09-17',
    kind: 'feature',
    summary:
      'Math Short Cycles for Primary–grade 6: record can-do / not-yet for each task, with by-task and by-student summaries.',
  },
  {
    version: '0.5.0',
    date: '2026-09-17',
    kind: 'feature',
    summary:
      'Choosing a class is easier — pick by homeroom, by course section, or by a whole grade, with school and grade filters.',
  },
  {
    version: '0.5.0',
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
