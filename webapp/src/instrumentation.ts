// Next.js instrumentation — runs once at server startup. Used here for the LOAD-TEST bypass guard:
// fail closed (throw ⇒ container won't boot) if LOADTEST_AUTH_BYPASS=true in an unsafe config, and log
// a prominent banner when the bypass is active. Runs in the Node runtime, where process.env is fully
// reliable (unlike the Edge middleware bundle). This file, like lib/loadtest.ts, must never reach main.
export async function register() {
  if (process.env.NEXT_RUNTIME !== 'nodejs') return
  const { assertLoadtestSafe, loadtestBypassEnabled, loadtestBanner } = await import('@/lib/loadtest')
  assertLoadtestSafe() // throws on an unsafe bypass config
  if (loadtestBypassEnabled()) console.warn(loadtestBanner())
}
