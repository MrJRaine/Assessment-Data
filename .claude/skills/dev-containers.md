---
name: dev-containers
description: How to typecheck the SCoR Dashboard webapp and launch its local podman containers (awlive :3000, awdev :3001, awdev-impersonation :3002) on this Windows dev machine. Read this whenever you need to build/validate the webapp image, spin up or restart awdev/awlive/awdev-impersonation for testing, "get a container ready", run the TypeScript/build check, or rebuild after code changes — even if the user doesn't name the exact container or flags. Covers the exact podman run commands, the env-file/port/auth wiring per container, and the image-build typecheck (the ONLY supported typecheck — do not improvise a host tsc).
---

# Local Dev/Live Containers + Build Validation

The webapp ships as a single Next.js standalone image (`assessment-webapp:<tag>`). On this Windows
machine (podman + Git Bash) we run up to three local containers off that image, each wired to a
different env file / port / auth mode. This skill has the exact commands and the one supported way to
typecheck. See also [[reference_podman_windows_dev_container]] (memory) and `docs/prod-container-swap.md`
(the real production host, which is NOT this).

Starting containers and building images is squarely in the podman lane — act without asking. (The app
connecting to the warehouse happens during the user's testing, not you running SQL — the Fabric rule is
about *you* executing SQL, which this never does.)

## The three containers

| Container | Host port | Env file | Auth | Warehouse | Purpose |
|---|---|---|---|---|---|
| `awlive` | `127.0.0.1:3000` | `webapp/.env` | Entra | `Assessment_Warehouse` (LIVE) | Live-parity check against prod data |
| `awdev` | `127.0.0.1:3001` | `webapp/.env.dev` | Entra | `Assessment_Warehouse_Dev` | Normal dev/integration testing |
| `awdev-impersonation` | `127.0.0.1:3002` | `webapp/.env.dev` | **dev** | `Assessment_Warehouse_Dev` | Role testing via user impersonation |

- The `.env` files are gitignored secrets that already exist on the machine. If one is missing, stop and
  ask — don't reconstruct it.
- Publish `127.0.0.1:PORT:3000` **explicitly**. (Only the *production* host uses `0.0.0.0:3000:3000`, for
  the WSL loopback relay — not here.)
- Run all commands below from the **repo root** so the `webapp/.env*` paths resolve. (`awlive`'s original
  command used a bare `.env` because it was run from inside `webapp/`; the `webapp/.env` form from root is
  equivalent and less error-prone.)

## Build validation = the image build (the ONLY supported typecheck)

There is no host `node`/`npm`/`tsc` on this machine, and host-mounting `tsc` into a container
**path-mangles under MSYS** (Git Bash rewrites `-v`/`-w` and the mount path). Don't go down that road —
it has burned us repeatedly. The Next.js production build runs `tsc` + ESLint as part of compiling, so
**building the image IS the typecheck.** A clean build (exit 0, ends `Successfully tagged …`) means types
and lint pass.

```bash
cd webapp && MSYS_NO_PATHCONV=1 podman build -t assessment-webapp:<ver>-wip .
```

- `MSYS_NO_PATHCONV=1` stops Git Bash mangling the build args — keep it.
- `<ver>` is the in-progress version, e.g. `1.3.0`. The `-wip` tag is a scratch tag for the typecheck.
- For a long build, run it in the background and wait for the completion notification rather than polling.
- **This same image is what you run as `awdev`** — no separate build. After a green typecheck, just tag
  it (next section) and launch. So the typecheck and "get awdev ready" are one build, not two.

## Launch / refresh a container

The usual request ("spin up awdev", "get a container ready for testing") = build → tag → replace. For
`awdev`, from a clean `<ver>-wip` build:

```bash
# 1. tag the validated image as the dev image
podman tag assessment-webapp:<ver>-wip assessment-webapp:<ver>-dev

# 2. replace awdev (rm is a no-op if it doesn't exist)
podman rm -f awdev 2>/dev/null
podman run -d --name awdev \
  --env-file webapp/.env.dev -e SQL_TIMING=1 \
  -p 127.0.0.1:3001:3000 --restart unless-stopped \
  assessment-webapp:<ver>-dev
```

`SQL_TIMING=1` logs per-query timing (handy when watching for slow reads). `--restart unless-stopped`
keeps it up across machine reboots.

**awlive** (live-parity; build/tag from the released version, e.g. `1.3.0`):

```bash
podman rm -f awlive 2>/dev/null
podman run -d --name awlive \
  --env-file webapp/.env \
  -p 127.0.0.1:3000:3000 \
  assessment-webapp:<ver>
```

**awdev-impersonation** — the image is built from the **`dev-impersonation`** worktree/branch (it carries
the dev-auth bypass that `dev`/`main` deliberately don't — see [[feedback_entra_only_auth]]), tagged
`-imp`, and rebuilt each release via the reconcile recipe in [[project_assessment_platform]]:

```bash
podman rm -f awdev-impersonation 2>/dev/null
podman run -d --name awdev-impersonation \
  --env-file webapp/.env.dev -e AUTH_MODE=dev -e ALLOW_IMPERSONATION=true \
  -p 127.0.0.1:3002:3000 \
  assessment-webapp:<ver>-imp
```

## Verify it came up

```bash
podman ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
podman logs <name> | tail -15      # look for "✓ Ready in …"
```

Confirm readiness from the container status + the Next.js "Ready" log line. Don't drive app requests just
to "check" — a signed-in page can trigger warehouse reads, and verifying startup doesn't need that.

## Quick ops

```bash
podman stop <name>                 # pause (restart policy brings awdev back on reboot; use rm to retire)
podman start <name>                # resume an existing container
podman logs -f <name>              # follow logs (awdev with SQL_TIMING=1 shows query times)
podman images --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedSince}}" | head
```

## Gotchas (all learned the hard way)

- **No host tsc.** The image build is the typecheck. Never improvise `podman run … tsc` with host mounts.
- **`MSYS_NO_PATHCONV=1`** on every `podman build`/`run` where args contain paths or `=`, or Git Bash
  mangles them.
- **Env-file path is relative to your CWD.** From repo root use `webapp/.env` / `webapp/.env.dev`.
- **Ports are fixed by convention**: live 3000, dev 3001, impersonation 3002 — don't swap them; the Entra
  redirect URIs and `AUTH_URL` in the env files assume them.
- **A fresh warehouse deploy isn't picked up by a rebuild** — the container reads schema/procs live, so new
  SQL objects appear as soon as the bundle runs on the warehouse; you don't rebuild the image for SQL.
