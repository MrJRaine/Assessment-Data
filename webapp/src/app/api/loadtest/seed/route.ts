// LOAD-TEST ONLY: returns real, RLS-scoped paths for the X-Loadtest-User so the Locust script can hit
// dynamic routes (cycles/groups/students) without scraping IDs from SSR HTML. Key-gated; 404 unless
// the bypass is on. Reuses the app's own data functions, so every path respects that user's scope.
// Meant to be called ONCE per virtual user at start. This file must never reach main.
import { getTeacherWindows, getTeacherGroups, getStudentCohort } from '@/lib/data'
import {
  loadtestBypassEnabled,
  keyMatches,
  resolveLoadtestUser,
  LOADTEST_KEY_HEADER,
  LOADTEST_USER_HEADER,
} from '@/lib/loadtest'

export const dynamic = 'force-dynamic'

export async function GET(req: Request) {
  if (!loadtestBypassEnabled()) return new Response('Not found', { status: 404 })
  if (!keyMatches(req.headers.get(LOADTEST_KEY_HEADER))) {
    return new Response('Unauthorized (load-test key required)', { status: 401 })
  }
  const upn = resolveLoadtestUser(req.headers.get(LOADTEST_USER_HEADER)) ?? process.env.DEV_FAKE_UPN
  if (!upn) return new Response('No user (set X-Loadtest-User or DEV_FAKE_UPN)', { status: 400 })

  const windows = await getTeacherWindows(upn)

  // Distinct (cycleGroupId, subject) → the /enter step-2 pages; a few groups each → the roster pages.
  const enter: Array<{ cycleGroupId: string; subject: string; path: string; groups: Array<{ groupKey: string; path: string }> }> = []
  const seen = new Set<string>()
  for (const w of windows) {
    if (!w.cycleGroupId) continue
    const dedupe = `${w.cycleGroupId}|${w.assessmentType}`
    if (seen.has(dedupe)) continue
    seen.add(dedupe)
    if (enter.length >= 5) break // cap the seed's own cost
    const base = `/enter/cycle/${encodeURIComponent(w.cycleGroupId)}/${encodeURIComponent(w.assessmentType)}`
    let groups: Array<{ groupKey: string; path: string }> = []
    try {
      groups = (await getTeacherGroups(upn, w.cycleGroupId, w.assessmentType))
        .slice(0, 10)
        .map((g) => ({ groupKey: g.key, path: `${base}/${encodeURIComponent(g.key)}` }))
    } catch {
      /* a cycle with no groups for this user — leave empty */
    }
    enter.push({ cycleGroupId: w.cycleGroupId, subject: w.assessmentType, path: base, groups })
  }

  // A sample of the user's in-scope students → the /reports drill-down.
  let studentPaths: string[] = []
  try {
    studentPaths = (await getStudentCohort(upn)).slice(0, 25).map((s) => `/reports/${s.studentKey}`)
  } catch {
    /* leave empty */
  }

  return Response.json({
    user: upn,
    windowCount: windows.length,
    enter,
    reports: {
      cohort: '/reports',
      writing: '/reports?subject=writing',
      math: '/reports/math',
      rwm: '/reports/rwm',
      students: studentPaths,
    },
  })
}
