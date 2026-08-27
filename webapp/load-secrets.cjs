// Container secret preloader (the "*_FILE" convention for file-mounted secrets).
//
// Loaded via `node --require ./load-secrets.cjs server.js` so it runs in-process BEFORE the
// Next standalone server boots. For each secret NAME, if NAME_FILE is set its file contents
// (trailing newline trimmed) become process.env[NAME]. App code — including the edge-runtime
// middleware — then reads process.env exactly as usual and never imports node:fs, so nothing
// edge-incompatible enters the bundle.
//
// Use with podman/docker file-mounted secrets, e.g.:
//   podman run --secret aw_auth_secret \                       # mounts at /run/secrets/aw_auth_secret
//     -e AUTH_SECRET_FILE=/run/secrets/aw_auth_secret ...
//
// A file-mounted value overrides any plain NAME already in the environment. If NAME_FILE is set
// but the file can't be read, we FAIL CLOSED (exit 1) rather than boot without a credential.
const fs = require('node:fs')

const SECRET_VARS = ['AUTH_SECRET', 'AUTH_ENTRA_CLIENT_SECRET', 'ENTRA_CLIENT_SECRET']

const loaded = []
for (const name of SECRET_VARS) {
  const file = process.env[`${name}_FILE`]
  if (!file) continue
  let value
  try {
    value = fs.readFileSync(file, 'utf8')
  } catch (err) {
    console.error(`[load-secrets] ${name}_FILE is set to '${file}' but could not be read: ${err.message}`)
    process.exit(1)
  }
  process.env[name] = value.replace(/[\r\n]+$/, '')
  loaded.push(name)
}

if (loaded.length) console.log(`[load-secrets] loaded from file: ${loaded.join(', ')}`)
