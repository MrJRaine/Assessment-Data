# Load-test baseline — single user — 2026-10-02

Reference point for later comparison. **Source of truth:** the exported Locust HTML report
`loadtest/Locust_2026-10-02-14h25_locustfile.py_http___127.0.0.1_3001.html` (numbers below are
extracted from its embedded JSON — exact, not hand-parsed).

## Run config
- **Host:** http://127.0.0.1:3001 (awlt, `assessment-webapp:0.7.1-loadtest`, dev warehouse `Assessment_Warehouse_Dev`)
- **Generator:** Locust on the box (WSL), **single user**
- **Volume:** 20 total requests · aggregate RPS ~0.3 · **Failures 0%**
- **Identities:** bare-UPN allow-list (20 personas); `LOADTEST_ALLOWED_CIDRS` blank

## Per-endpoint (from the HTML report)

| Endpoint | Req | Fails | Median (ms) | 95%ile | 99%ile | Avg (ms) | Min | Max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| GET / (landing) | 2 | 0 | 242.4 | 240 | 240 | 243.4 | 242 | 244 |
| GET /api/loadtest/seed | 1 | 0 | 16492.8 | 16000 | 16000 | **16492.8** | 16493 | 16493 |
| GET /enter (windows) | 5 | 0 | 240 | 3600 | 3600 | 890.5 | 183 | 3596 |
| GET /enter/cycle/{cg}/{subject}/{group} (roster) | 5 | 0 | 1200 | — | — | 2437.3 | 1044 | 4896 |
| GET /reports (cohort) | 1 | 0 | 1395.6 | 1400 | 1400 | 1395.6 | 1396 | 1396 |
| GET /reports/math (picker) | 3 | 0 | 850 | 910 | 910 | 868.2 | 846 | 908 |
| GET /reports/{studentKey} | 3 | 0 | 1799.3 | 1800 | 1800 | 1761.0 | 1724 | 1799 |
| **Aggregated** | **20** | **0** | 1100 | 16000 | 16000 | **2145.1** | 183 | 16493 |

## Observations
- **0% failures** — clean (CIDR + bare-UPN fixes in place).
- **`/api/loadtest/seed` ≈ 16.5 s** is the outlier (1 sample; runs several Fabric queries serially per
  identity — `getTeacherWindows` + a `getTeacherGroups` loop + `getStudentCohort`). It's a once-per-VU
  startup call, not a page a user waits on, but it dominates aggregate latency — weight it separately.
- Real page floors at 1 user: landing ~0.24 s, math picker ~0.87 s, windows ~0.89 s (one 3.6 s outlier),
  cohort ~1.40 s, student ~1.76 s, **roster ~2.44 s** (heaviest real page; 1.0–4.9 s spread).

## Caveat — thin sample
This run was only **20 requests** (1–5 per endpoint), so medians/percentiles are noisy. For a sturdier
single-user floor, re-run longer (e.g. `-u 1 -t 5m` or a few hundred requests) and replace this file.
The **averages** here are reliable as a rough floor; treat per-endpoint percentiles as indicative only.

Keep the HTML report alongside this file as the authoritative artifact for the run.
