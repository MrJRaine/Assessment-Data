// Proves the load-test startup guard blocks production. Run: `node scripts/loadtest_guard_check.mjs`
// (no test framework in this repo). MIRRORS assertLoadtestSafe() in webapp/src/lib/loadtest.ts —
// keep the two in sync. Exits non-zero on any failed assertion.
import assert from 'node:assert/strict'

const LIVE_HOST = 'data.tcrce.ca'

// Mirror of assertLoadtestSafe: returns the list of problems (empty = safe to start).
function problems(env) {
  if (env.LOADTEST_AUTH_BYPASS !== 'true') return []
  const p = []
  if ((env.AUTH_URL ?? '').toLowerCase().includes(LIVE_HOST)) p.push('live host')
  if (!/_dev$/i.test(env.FABRIC_SQL_DATABASE ?? '')) p.push('non-dev warehouse')
  if ((env.AUTH_MODE ?? '').toLowerCase() !== 'dev' || env.ALLOW_DEV_AUTH !== 'true') p.push('dev-auth not opted in')
  if (!env.LOADTEST_KEY) p.push('no key')
  return p
}
const safe = (env) => problems(env).length === 0

const SAFE = {
  LOADTEST_AUTH_BYPASS: 'true',
  AUTH_URL: 'http://10.0.0.5:3003',
  FABRIC_SQL_DATABASE: 'Assessment_Warehouse_Dev',
  AUTH_MODE: 'dev',
  ALLOW_DEV_AUTH: 'true',
  LOADTEST_KEY: 'secret',
}

// Bypass off ⇒ always safe (guard is inert).
assert.equal(safe({ LOADTEST_AUTH_BYPASS: 'false' }), true, 'bypass off should be safe')
// The known-good load-test config passes.
assert.equal(safe(SAFE), true, 'dev warehouse + staging host + key should be safe')
// Each production tell must BLOCK boot.
assert.equal(safe({ ...SAFE, AUTH_URL: 'https://data.tcrce.ca' }), false, 'live host must block')
assert.equal(safe({ ...SAFE, FABRIC_SQL_DATABASE: 'Assessment_Warehouse' }), false, 'live warehouse must block')
assert.equal(safe({ ...SAFE, ALLOW_DEV_AUTH: undefined }), false, 'missing ALLOW_DEV_AUTH must block')
assert.equal(safe({ ...SAFE, AUTH_MODE: 'entra' }), false, 'entra mode must block')
assert.equal(safe({ ...SAFE, LOADTEST_KEY: undefined }), false, 'missing key must block')

console.log('OK — load-test startup guard blocks production configs and permits dev-only ones.')
