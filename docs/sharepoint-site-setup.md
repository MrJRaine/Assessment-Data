# SharePoint Site Setup — Assessment Entry Lists

Companion to [sharepoint-entry-pivot.md](sharepoint-entry-pivot.md). Resolves open
decision 3. Everything here is doable today, before IT delivers the Entra registration.

## Site choice — recommendation: one dedicated team site

**Create a dedicated SharePoint team site** (suggested name: `Assessment Entry`,
URL slug `/sites/AssessmentEntry`) rather than reusing an existing Teams site:

- **NOT a Teams private-channel site** (like the planned ingest channel) — private-channel
  membership is capped and managed per-channel; 200 teachers don't belong there.
- **NOT a personal/OneDrive location** — no service-account story, wrong governance.
- A dedicated site gives clean permission boundaries, its own audit/versioning settings,
  and a single URL for the Entra `Sites.Selected` grant (least-privilege: the bridge app
  will be able to touch THIS site and nothing else in the tenant).
- Canadian residency is automatic (TCRCE tenancy).
- If tenant policy blocks self-service site creation, bundle the site request with the
  Entra registration request — same IT ticket, one round-trip.

Pilot scale: one site, all four lists. The per-school partitioning question (spec open
decision 1) gets decided before September; nothing about this site forecloses it.

## Lists to create (exact names, columns, types)

Create all columns BEFORE loading any data, and the indexes BEFORE the lists grow —
retrofitting indexes onto a >5000-item list is painful. (* = create an index.)

### 1. `RosterEntry` — bridge-maintained working surface (teachers read)
| Column | Type | Notes |
|---|---|---|
| Title | (default) | Bridge writes "LastName, FirstName" |
| AssessmentWindowID* | Text | |
| WindowName | Text | |
| SchoolYear | Text | |
| WindowStatus | Choice: Upcoming, Open, ClosesToday, Closed | |
| ScaleSystem | Text | |
| TeacherEmail* | Text | lowercased |
| GroupKey* | Text | `HR:...` / `SEC:...` |
| GroupLabel | Text | bridge-composed display label |
| SchoolID* | Text | |
| StudentKey | Text | 19-digit, stays text |
| StudentNumber | Number | |
| FirstName / LastName | Text | |
| Grade | Text | |
| ProgramFamily | Text | |
| ExistingReadingAssessmentID | Text | |
| ExistingReadingScaleID | Text | |
| ExistingScaleValue | Text | |
| ExistingAssessmentDate | Date | |
| ExistingDelta | Number | |
| ExpectedMinLevel / ExpectedMaxLevel | Text | |
| ExpectedMinOrder / ExpectedMaxOrder | Number | |
| ReadingIPPStatus | Choice: Yes, No (allow blank) | SP Yes/No can't be blank — use Choice |
| ReadingIPPNeedsConfirmation | Yes/No | |

### 2. `Submissions` — append-only queue (teachers write, bridge drains)
| Column | Type | Notes |
|---|---|---|
| Title | (default) | app writes "StudentNumber WindowID" for humans |
| StudentNumber | Number | |
| AssessmentWindowID* | Text | |
| Action | Choice: Upsert, Delete, IPPConfirm | |
| LevelCode | Text | |
| ReadingScaleID | Text | |
| IsIPP | Choice: Yes, No (allow blank) | IPPConfirm rows only |
| AssessmentDate | Date | |
| SubmittedBy* | Text | User().Email |
| SubmittedAt | Date and Time | |
| SyncStatus* | Choice: Pending, Synced, Error — default **Pending** | |
| SyncError | Multiple lines of text | proc THROW message verbatim |
| SyncedAt | Date and Time | |

Enable **versioning** on this list (audit trail for every submission and status change).

### 3. `ScaleLevels` — reference (bridge-seeded from DimReadingScale)
| Column | Type |
|---|---|
| Title | LevelCode |
| ReadingScaleID | Text |
| LevelOrder | Number |
| ScaleSystem* | Text |
| ActiveFlag | Yes/No |

### 4. `SyncCounts` — truncation tripwire
| Column | Type | Notes |
|---|---|---|
| ScopeKey* | Text | `<TeacherEmail>\|<WindowID>` or `<SchoolID>\|<WindowID>` |
| ExpectedRows | Number | |
| LastOutboundRun | Date and Time | |

## Permissions (pilot-grade; Step 26 security groups take over at rollout)

- **Site:** private. Owners = you (+ IT if they want standing access). No members yet.
  Disable "members can share"; external sharing off (tenant default likely already).
- **Pilot teachers + pilot admins:** site **Visitors** (Read) — covers RosterEntry,
  ScaleLevels, SyncCounts.
- **`Submissions` list:** break permission inheritance; grant the pilot
  teachers/admins **Contribute** on this list only. Then in the list's advanced
  settings set item-level permissions: **Read items: only their own · Create and
  Edit: only their own.** That natively stops teachers reading each other's
  submissions with zero per-item management.
  - **Build-time verification (flagged):** confirm the bridge app (Graph,
    `Sites.Selected` write) sees ALL items despite the read-own setting — expected
    behavior for an app-only identity, but verify before trusting the drain.
- **PIIDPA note:** `RosterEntry` is readable by every pilot participant — accepted for
  the pilot's 1-3 schools; the per-school partitioning decision (spec open decision 1)
  is where this gets tightened for rollout.
- Remember the canvas app itself is shared separately (Power Apps share) — site
  permissions and app sharing are two different gates; pilot users need both.

## When done

Send me the site URL — it goes into [it-request-entra-bridge.md](it-request-entra-bridge.md)
(the `Sites.Selected` write grant) and into the bridge notebook's config.
