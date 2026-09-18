# Ingest runbook — maintenance window + PowerSchool load

**Audience:** whoever runs the weekly PowerSchool ingest (sysadmin / ingest admin).

**The rule: never run an ingest while teachers are entering data.** Put the app into maintenance
first, let the window elapse, then run the cycle.

---

## Why the window is not optional

The save path re-resolves the caller's roster as a scope gate before writing — each student must
still be on the teacher's roster for that cycle. An ingest is precisely what moves students between
sections.

So if a teacher has a roster open when the ingest lands:

- they mark their class, hit **Save**, and get *"Not in your roster for this window/group — not
  saved."*
- the entry is lost, and the message reads as though **they** did something wrong
- worse, it can be partial — some rows save, some don't, with no obvious cause

Maintenance mode exists for exactly this. Its staged sequence — banner → lock → **auto-save** → down
overlay — flushes in-flight work *before* the data shifts underneath it.

---

## The procedure

1. **Upload the export files** on `/ingest`. Uploading is safe at any time; it only lands files in
   OneLake and touches nothing teachers can see.
2. **Press “Schedule maintenance”.** The app sets a window **15 minutes** out and starts warning
   every open tab. Teachers see a banner, then a lock, then their work auto-saves.
3. **Wait for the window.** Don't shorten it by clicking through — the 15 minutes is what guarantees
   background tabs (which poll every 8 minutes) get the message and auto-save.
4. **Press “Run ingest cycle”** once the app is down.
5. **The app comes back automatically** when the cycle finishes cleanly — including runs that skipped
   some rows. Nothing more to do.

### The admin pages stay usable during maintenance

The down overlay covers the app but NOT `/ingest` or `/admin/maintenance` — otherwise this procedure
would be impossible: the window lands, the overlay covers the Run button, and the only control left
is "Clear maintenance now", which throws away the wait. Any error from the run would also be hidden
behind it.

The banner still shows on those pages, so you can see the window is live.

If you close the tab and come back mid-maintenance, the overlay offers **Go to Ingest** and **Go to
Maintenance** links — shown only to users who hold the matching capability, the same way the Clear
button is.

### What happens if the ingest fails

If `usp_TriggerIngestCycle` throws, **maintenance stays on deliberately.** The app does not come back
up over a half-applied ingest — that is the same reasoning behind the window no longer auto-expiring.

Check the warehouse, fix the cause, re-run, and clear maintenance yourself on `/admin/maintenance`
once you are satisfied.

---

## Permissions

| Action | Capability |
|---|---|
| Upload files, run the ingest cycle | `StaffAppAccess.CanRunIngest` |
| Set / clear a maintenance window | `StaffAppAccess.IsSysAdmin` |

These are **different capabilities**. An ingest admin who is not also a sysadmin can still run the
cycle, but the "Schedule maintenance" button will report that it needs sysadmin rights, and the app
will not be able to clear the window afterwards either — it says so in the result message.

Either give the ingest operator `IsSysAdmin`, or have a sysadmin set the window (below).

---

## Doing it faster, or by hand

The 15 minutes is a deliberate default, not a limit. To use a different notice period — or when the
`/ingest` button is unavailable — set the window directly.

**Schedule maintenance N minutes out:**

```sql
-- @MaintenanceAt is UTC. Replace 15 with the notice you want, and the email with your own.
DECLARE @Minutes INT = 15;
EXEC dbo.usp_SetMaintenanceWindow
     @MaintenanceAt = DATEADD(MINUTE, @Minutes, GETDATE()),   -- GETDATE() is UTC in Fabric
     @Message       = 'Student data is being updated. Your work is saved automatically before the app pauses.',
     @CallerUPN     = 'jeffrey.raine@tcrce.ca';
```

**Bring the app back up:**

```sql
EXEC dbo.usp_ClearMaintenanceWindow @CallerUPN = 'jeffrey.raine@tcrce.ca';
```

**Check the current state:**

```sql
SELECT MaintenanceAt, Message FROM dbo.AppMaintenance WHERE Id = 1;
```

`MaintenanceAt` is UTC; the app compares in Atlantic time. `NULL` means no window is set.

Going below ~10 minutes is possible but risky: background tabs poll every 8 minutes, so a shorter
notice can pass before a hidden tab ever learns about it and auto-saves. The `/admin/maintenance`
page asks for confirmation below 10 minutes for this reason.

---

## What else the ingest resets

`runIngestCycle` clears two server-side caches on completion, because the ingest is what invalidates
them:

- **identity cache** — `DimStaff.AccessLevel` and the `StaffAppAccess` capabilities (1h TTL)
- **groups cache** — `tvf_TeacherGroups` results (30s TTL)

This is what keeps those TTLs honest: a cached role or roster can only be stale until the data behind
it actually changes, and this is that moment. If you ever run the ingest **outside** the app (direct
`EXEC usp_TriggerIngestCycle`), those caches are not cleared — restart the container, or accept up to
an hour of stale capabilities.

---

## Not automated (yet)

The wait between scheduling and running is **manual on purpose**. An unattended timer would have to
survive a closed browser tab and a container restart, and its failure mode is the app stuck in
maintenance with nobody watching. See the pre-launch queue for the discussion.
