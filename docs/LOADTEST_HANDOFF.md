# Load-test build: handover

This brief is for the agent working in the app repository. It explains what is being built, why, how it will be tested, and what information needs to come back.

## Goal

Load test the student assessment app (production: data.tcrce.ca) without touching production, without real sign-ins, and without sending any traffic to Microsoft. To do that we need a **load-test build** of the app, created from the **impersonation branch**, pointed at the **dev warehouse**, with **Entra ID sign-in bypassed** behind strict safeguards. It runs on the staging server and is driven by Locust from a separate test cluster.

## How the test will run (context)

- **Load generator:** A 4-node Raspberry Pi 400 k3s cluster runs Locust (a Python load-testing tool). One Locust master and several workers run as Kubernetes pods in a namespace called `loadtest`.
- **Network path (current):** The Pis reach other networks over Wi-Fi. Wi-Fi blocks device-to-device traffic, so reachability to the staging server is still being confirmed.
- **Network path (planned):** A dedicated VLAN on the enterprise switching gear for the cluster, ideally using subnet `10.0.0.0/24` with gateway `10.0.0.1`. Firewall rules on that VLAN will allow HTTPS to the staging server and HTTPS out to the internet only.
- **DNS:** Locust will address the staging server by its proper hostname, but the IP will be pinned inside the pods (Kubernetes `hostAliases`). No load-test DNS lookups will reach the provincial DNS servers, and TLS certificates and Auth.js host checks keep working.
- **Traffic shape:** Many simulated teachers and admins, each following a realistic session of page loads and API calls with pauses in between. Initial runs will be gentle (tens to low hundreds of requests per second) and ramped gradually.

## What to build

Create a branch `loadtest` from the impersonation branch. The app uses **Auth.js**, so the bypass most likely belongs in the Auth.js configuration or middleware.

1. **Dev warehouse only:** Read the warehouse connection from environment variables. No hard-coded credentials, and no production connection details anywhere in the branch.
2. **Bypass behind an explicit flag:** `LOADTEST_AUTH_BYPASS=true` enables it. Every bypassed request must carry a header `X-Loadtest-Key` matching a secret supplied by an environment variable (for example `LOADTEST_KEY`). Requests without a valid key get `401`.
3. **Realistic identities via impersonation:** Use the existing impersonation mechanism to map bypassed requests to a small set of test teacher and admin identities, selected by a header such as `X-Loadtest-User`. The load test should exercise real permission checks, not an all-powerful superuser.
4. **Zero Microsoft traffic when the flag is on:** No Entra sign-in redirects, token validation, JWKS fetches, or Microsoft Graph calls (profile, photo, groups). Stub anything the app would otherwise call.
5. **Fail closed:** The app must refuse to start if `LOADTEST_AUTH_BYPASS=true` and the environment is production, or the configured host is data.tcrce.ca. Log a prominent warning at startup whenever the bypass is active.
6. **Optional network lock:** Support an allow-list of source networks for bypassed requests (for example `LOADTEST_ALLOWED_CIDRS=10.0.0.0/24`), so the bypass only works from the test cluster's VLAN. Mind any reverse proxy in front of the app when reading the client address.
7. **Isolated and reviewable:** Keep the bypass in its own module or middleware. Add a test proving the startup guard blocks production.
8. **Never merged:** State in the README that `loadtest` must never be merged into main. If there is CI, add a check that fails if the bypass module appears on main.

Before writing code, show where authentication and Microsoft Graph calls currently happen and the plan for each requirement.

## What to hand back

The Locust test script will be written outside this repository. It needs:

- **Staging address:** The hostname and IP the load-test build will run on, and the port if not 443.
- **Bypass details:** The exact header names, and the list of test identities (teacher and admin) with what each can see. Do not include the key value; it will be stored as a Kubernetes Secret.
- **Teacher session:** The pages and API routes a teacher hits in a normal session, in order, with method, path, typical request body, and roughly how often each happens. Note which calls the browser makes automatically on page load.
- **Admin session:** The same for an admin.
- **Writes:** Which routes write to the dev warehouse (submitting assessments, saving scores), and whether writes are acceptable during load tests. Note any cleanup needed afterwards.
- **Static assets:** Whether built assets under the app's static path are served by the app container or by a proxy or CDN, so the test can decide whether to include them.
- **Health check:** An endpoint that returns quickly when the app is up, for a pre-test sanity check.
- **Deployment steps:** How the build is started on staging, including the environment variables it needs (names only).

## Constraints

- **No production:** Nothing in this work touches data.tcrce.ca or the production warehouse.
- **No Microsoft calls:** With the bypass on, the app makes no requests to Entra ID or Microsoft Graph.
- **No secrets in the repository:** Keys and connection strings come from environment variables only.
- **Student data:** If the dev warehouse holds a copy of real student records, flag it. Synthetic data is preferred for load testing.

## Acceptance checks

- **Bypass works:** A request with a valid `X-Loadtest-Key` and `X-Loadtest-User` receives the same page a signed-in test teacher would.
- **Bypass is locked:** A request without the key, or with a wrong key, gets `401`.
- **Production guard:** Starting with the bypass flag in a production configuration fails immediately with a clear error.
- **No outbound Microsoft traffic:** Under load, the server makes no connections to Microsoft endpoints (check logs or outbound connections).
- **Staging reachable from the cluster:** An HTTPS request from inside the cluster to the staging hostname returns a normal response.
