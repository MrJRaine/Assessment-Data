"""
Locust load test for the SCoR Dashboard load-test build.

Drives the app's real SSR/Fabric read paths through the Entra BYPASS build (loadtest branch), to
measure the VM's serving capacity and the connection-pool ceiling. Every request carries the two
bypass headers; each virtual user is pinned to a synthetic identity and seeds its real, RLS-scoped
paths once from /api/loadtest/seed, then browses like a teacher or an oversight user (admin/analyst).

RUN (headless, distributed is the same file):
    export LOADTEST_KEY='<the key the app was started with>'
    export LOADTEST_USERS='teach1@tcrce.ca:teacher,...,admin1@tcrce.ca:admin,analyst1@tcrce.ca:analyst'
    # single process:
    locust -f locustfile.py --host http://<staging-ip>:3001 --headless -u 50 -r 5 -t 10m
    # distributed (k3s): one --master, N --worker --master-host=<master> ; same file, same env.

Notes:
 - Identities are assigned ROUND-ROBIN from LOADTEST_USERS, so the spawned population mirrors that
   list's teacher/oversight mix (repeat the file's mix, e.g. 16 teachers + 2 admins + 2 analysts).
 - roster-grid tasks self-skip for users with no sections (analysts), who then shift to report reads.
 - Dynamic URLs are grouped by a stable `name=` so stats don't fragment per ID.
 - Poll /api/debug/pool yourself during the run (curl loop) to watch borrowed/pending vs max.
"""
import os
import re
import threading
import itertools

from locust import HttpUser, task, between, events

# ── config from env ───────────────────────────────────────────────────────────────────────────
LOADTEST_KEY = os.environ.get("LOADTEST_KEY", "")
# "upn[:role]" comma/space separated; role ∈ teacher|admin|analyst (default teacher).
_RAW_USERS = os.environ.get("LOADTEST_USERS", "")


def _parse_users(raw):
    out = []
    for tok in re.split(r"[,\s]+", raw.strip()):
        if not tok:
            continue
        upn, _, role = tok.partition(":")
        out.append((upn.strip(), (role.strip().lower() or "teacher")))
    return out


USERS = _parse_users(_RAW_USERS)
_user_cycle = itertools.cycle(USERS) if USERS else None
_cycle_lock = threading.Lock()

# Seed cache shared across virtual users on this worker (keyed by upn), so N VUs sharing an identity
# only hit /api/loadtest/seed once for it.
_SEED_CACHE = {}
_SEED_LOCK = threading.Lock()

_HREF_RE = re.compile(r'href="(/[^"?#]+)"')


@events.test_start.add_listener
def _check_config(environment, **_):
    if not LOADTEST_KEY:
        raise RuntimeError("LOADTEST_KEY env var is required (the X-Loadtest-Key the app expects).")
    if not USERS:
        raise RuntimeError("LOADTEST_USERS env var is required (comma-separated upn[:role]).")
    print(f"[loadtest] {len(USERS)} identities loaded "
          f"({sum(1 for _, r in USERS if r == 'teacher')} teacher / "
          f"{sum(1 for _, r in USERS if r != 'teacher')} oversight).")


class AppUser(HttpUser):
    wait_time = between(1, 6)  # think time between actions

    def on_start(self):
        # Pin an identity (round-robin so the population mirrors LOADTEST_USERS' mix).
        with _cycle_lock:
            self.upn, self.role = next(_user_cycle)
        self.client.headers.update({
            "X-Loadtest-Key": LOADTEST_KEY,
            "X-Loadtest-User": self.upn,
        })
        self._seed()

    # ── seed: fetch this identity's real paths once (cached per upn) ────────────────────────────
    def _seed(self):
        cached = _SEED_CACHE.get(self.upn)
        if cached is None:
            with _SEED_LOCK:
                cached = _SEED_CACHE.get(self.upn)
                if cached is None:
                    cached = self._fetch_seed()
                    _SEED_CACHE[self.upn] = cached
        (self.enter_paths, self.roster_paths, self.student_paths, self.reports) = cached

    def _fetch_seed(self):
        with self.client.get("/api/loadtest/seed", name="GET /api/loadtest/seed", catch_response=True) as r:
            if r.status_code != 200:
                r.failure(f"seed {r.status_code}: {r.text[:120]}")
                return ([], [], [], {"cohort": "/reports"})
            data = r.json()
            enter = data.get("enter", []) or []
            enter_paths = [w["path"] for w in enter]
            roster_paths = [g["path"] for w in enter for g in (w.get("groups") or [])]
            reports = data.get("reports", {}) or {}
            student_paths = reports.get("students", []) or []
            return (enter_paths, roster_paths, student_paths, reports)

    # small helper: GET a page, mark 5xx/401 as failures with a snippet
    def _get(self, url, name):
        with self.client.get(url, name=name, catch_response=True) as r:
            if r.status_code >= 500:
                r.failure(f"{r.status_code} server error")
            elif r.status_code == 401:
                r.failure("401 — X-Loadtest-Key rejected (check LOADTEST_KEY)")
            elif r.status_code >= 400:
                r.failure(f"{r.status_code}")
            return r

    def _pick(self, seq):
        import random
        return random.choice(seq) if seq else None

    # ── tasks ──────────────────────────────────────────────────────────────────────────────────

    @task(1)
    def landing(self):
        self._get("/", name="GET / (landing)")

    @task(2)
    def windows(self):
        self._get("/enter", name="GET /enter (windows)")

    @task(4)
    def roster_grid(self):
        # The heavy entry read. Analysts/admins with no sections have no roster paths → fall back to reports.
        path = self._pick(self.roster_paths)
        if path:
            self._get(path, name="GET /enter/cycle/{cg}/{subject}/{group} (roster)")
        else:
            self.reports_cohort()

    @task(3)
    def reports_cohort(self):
        # Reading cohort, and sometimes the writing toggle.
        if self._pick([True, False]):
            self._get(self.reports.get("cohort", "/reports"), name="GET /reports (cohort)")
        else:
            self._get(self.reports.get("writing", "/reports?subject=writing"), name="GET /reports?subject=writing")

    @task(3)
    def student_drill(self):
        path = self._pick(self.student_paths)
        if path:
            self._get(path, name="GET /reports/{studentKey}")
        else:
            self.reports_cohort()

    @task(2)
    def reports_math_rwm(self):
        # The newest, heaviest cohort reads. Math/RWM pickers, then drill into one matrix/student by
        # scraping a link from the picker page (realistic browse; no guessed IDs).
        if self._pick([True, False]):
            r = self._get(self.reports.get("math", "/reports/math"), name="GET /reports/math (picker)")
            self._drill_from(r, "/reports/math/", name="GET /reports/math/{group} (matrix)")
        else:
            r = self._get(self.reports.get("rwm", "/reports/rwm"), name="GET /reports/rwm (cohort)")
            self._drill_from(r, "/reports/rwm/", name="GET /reports/rwm/{studentKey}")

    def _drill_from(self, resp, prefix, name):
        try:
            hrefs = [h for h in _HREF_RE.findall(resp.text) if h.startswith(prefix) and h != prefix]
        except Exception:
            hrefs = []
        target = self._pick(hrefs)
        if target:
            self._get(target, name=name)
