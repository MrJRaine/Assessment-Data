# Executive Brief — Hosting Requirements: Assessment Web App

**To:** Coordinator, Technology Services
**From:** jeffrey.raine@tcrce.ca
**Date:** 2026-06-18

A containerized web application to be hosted on a TCRCE server and published to the internet
at **`https://data.tcrce.ca`**. The following are the technical requirements to stand it up.

---

## 1. Resource footprint

For deployment onto an **existing** server, these are the resources the app needs
*available* — not a fresh allocation (the OS, its updates, and logging are already in place).

| Resource | Needed available |
|---|---|
| CPU | ~1 vCPU (light; brief bursts per request) |
| RAM | ~1–2 GB free (Node process ~0.3–1 GB) |
| Free disk | ~3–5 GB (app image ~0.5 GB + one rollback image + rotated logs) |

- **Stateless** — no local database or persistent storage; logs only.
- Host must be able to run **Linux OCI containers** (native on Linux; Windows Server requires Linux-container support).
- Server must reside **in Canada** (on-prem TCRCE satisfies this).
- **Co-hosting:** if the server already serves other sites on 443, the reverse proxy routes `data.tcrce.ca` by host name (virtual host / SNI) — no dedicated IP or port needed.

## 2. Software / runtime

- **Container runtime:** **Podman** (recommended) — the open-source container engine from
  Red Hat. **Docker** is technically compatible (same OCI image), but Podman is recommended
  for its security posture: it runs **rootless and daemonless by default**, so there is no
  long-lived privileged daemon or socket to compromise, and a container breakout is contained
  to an unprivileged user rather than root on the host. Docker can be configured similarly but
  is not rootless by default.
- **Reverse proxy:** nginx, Caddy, or Apache (or IIS) — TLS termination + forward to the app. Open-source.
- **Process management:** systemd unit / Podman quadlet / restart policy so the container
  auto-starts on boot and restarts on failure.
- App is delivered as an OCI container image (built from source; transferred via registry
  pull or `podman load` of a saved image).

## 3. DNS / TLS

- **DNS record:** `data.tcrce.ca` → the public ingress address (firewall NAT or proxy).
- **TLS certificate** for `data.tcrce.ca` from a public CA (ACME/Let's Encrypt or the
  TCRCE certificate process). HTTPS is required (auth callbacks + secure cookies).

## 4. Networking / firewall

**Inbound**
| Source | Port | Destination |
|---|---|---|
| Internet | 443 (HTTPS) | Reverse proxy → app on `127.0.0.1:3000` |

- The container port (**3000**) is **not** exposed publicly — only the reverse proxy reaches it.
- The proxy must forward `X-Forwarded-Proto: https` and the `Host` header.

**Outbound (HTTPS/TLS from the server)**
| Destination | Port | Purpose |
|---|---|---|
| `login.microsoftonline.com`, `login.windows.net` | 443 | Entra ID sign-in |
| `graph.microsoft.com` | 443 | Microsoft Graph |
| `<workspace>.datawarehouse.fabric.microsoft.com` | 1433 (TCP, TLS) | Fabric Warehouse SQL endpoint |

## 5. Runtime configuration / secrets

Provided to the container at runtime — never baked into the image or committed to source:

- `ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID`, `ENTRA_CLIENT_SECRET`
- `AUTH_SECRET` (session encryption key)
- `FABRIC_SQL_SERVER`, `FABRIC_SQL_DATABASE`
- `AUTH_MODE=entra`, `DATA_REGION=canadaeast`

**Secret handling:** the two sensitive values — `ENTRA_CLIENT_SECRET` and `AUTH_SECRET` —
are never baked into the image or committed to source. Recommended approach is **Podman
secrets**: held in Podman's secret store and **mounted into only the container that needs
them at runtime**, delivered as an in-memory (tmpfs) file under `/run/secrets/` — not written
to the container's disk and not exposed in `podman inspect`. For **encryption at rest**, use
Podman's GPG-backed `pass` driver or an external secrets manager (Canadian region if cloud);
the default secret driver protects by filesystem permissions rather than encryption. A
root-owned `0600` env file is the minimum acceptable fallback. Non-secret values
(`FABRIC_SQL_SERVER`, `AUTH_MODE`, `DATA_REGION`, etc.) can be plain environment variables.

**Entra dependency:** the production redirect URI
`https://data.tcrce.ca/api/auth/callback/microsoft-entra-id` must be registered on the app's
Entra registration (separate request in progress).

## 6. Operations

- **Health check:** `GET /api/health` returns `200` JSON — use for uptime/load-balancer probes.
- **Logging:** container stdout/stderr to the host journal or log aggregation.
- **Updates:** redeploy = load new image + restart container (brief restart, no data migration).
- **Backup:** none required for the app (stateless); back up only the config/secret file.

---

## Action items for Technology Services

1. Provision a Linux server/VM per Section 1.
2. Install a container runtime + reverse proxy (Section 2).
3. Create DNS record `data.tcrce.ca` (Section 3).
4. Issue a TLS certificate for `data.tcrce.ca` (Section 3).
5. Configure firewall: inbound 443; outbound 443 + 1433 to the endpoints in Section 4.
6. Provide a secret store / protected env mechanism (Section 5).
