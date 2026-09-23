/*───────────────────────────────────────────────────────────────────────────────────────────────
  diag_roster_timing.sql   —   READ-ONLY diagnostic (no writes; safe on dev or live)

  PURPOSE
    Localize where the ~3.47s roster "long call" actually goes: the SQL query itself, or the app's
    connection/token/pool overhead (which SQL timing can't see). This measures the SERVER-side
    elapsed of tvf_TeacherRoster (and tvf_TeacherGroups) for a real, busy teacher — cold and warm.

  HOW TO READ THE RESULT (compare the WARM roster figure to the app's observed ~3.47s):
    • Warm roster ≈ a few seconds  → the cost is the QUERY. The membership-materialization idea
      (a TeacherRosterMembership table rebuilt each ingest, roster TVF reads it + joins facts live)
      would help. See the 2026-09-23 discussion.
    • Warm roster is small (say < 500 ms) but the APP still sees ~3.47s → the cost is NOT the query;
      it's connection setup / token acquisition / cold pool. Pre-warm / min-connections is the fix,
      and materialization would NOT help. (This is the item tied to the tvf_TeacherGroups perf.)
    • Cold ≫ Warm → plan compilation dominates the first hit (the TVF can't prune the @UPN role
      branches at plan time — see its header note), i.e. a parameter/compile cost, not I/O.
    • baseline_select1 shows the server-side floor (~0 ms); anything the APP measures ABOVE the warm
      figure here is round-trip + connection overhead, not database work.

  WHAT IT DOES: picks the current Reading cycle, finds the caller-agnostic teacher with the LARGEST
  taught group in it, then times the roster + groups TVFs for that teacher. Everything is resolved
  from the data — no placeholders to fill in.

  NOTE: the timing wraps the TVF in COUNT_BIG(*) so no student rows are returned (PII-safe on live).
  The joins/filters — the dominant cost — still execute; only some output-only scalar computes may be
  pruned. For a fully faithful dev figure, change the inner `SELECT *` to return rows (dev only).
───────────────────────────────────────────────────────────────────────────────────────────────*/
SET NOCOUNT ON;

DECLARE @CycleGroupID VARCHAR(36),
        @UPN          VARCHAR(255),
        @WID          VARCHAR(20),
        @GroupKeys    VARCHAR(4000),
        @Students     INT;

/* 1 ── the current Reading cycle (active + covering today; else the latest active Reading cycle) */
SELECT TOP 1 @CycleGroupID = w.CycleGroupID
FROM DimAssessmentWindow w
CROSS JOIN (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) at
WHERE w.ActiveFlag = 1
  AND w.AssessmentType = 'Reading'
  AND at.Today BETWEEN w.StartDate AND w.EndDate
ORDER BY w.StartDate DESC;

IF @CycleGroupID IS NULL
    SELECT TOP 1 @CycleGroupID = CycleGroupID
    FROM DimAssessmentWindow
    WHERE ActiveFlag = 1 AND AssessmentType = 'Reading'
    ORDER BY EndDate DESC;

IF @CycleGroupID IS NULL
BEGIN
    ;THROW 51000, 'No active Reading cycle in DimAssessmentWindow — cannot pick a roster to time.', 1;
END

/* 2 ── the teacher with the biggest TAUGHT group in that cycle (drives tvf_TeacherGroups per teacher
        who actually has a section, then keeps their largest own-class card). @GroupKeys = its
        GroupKey ('SEC:<id>'); @WID = the first window instance behind the card. */
SELECT TOP 1
    @UPN       = t.Email,
    @GroupKeys = g.GroupKey,
    @WID       = CASE WHEN CHARINDEX(',', g.WindowIDs) > 0
                      THEN LEFT(g.WindowIDs, CHARINDEX(',', g.WindowIDs) - 1)
                      ELSE g.WindowIDs END,
    @Students  = g.ApplicableStudentCount
FROM (SELECT DISTINCT LOWER(fst.TeacherEmail) AS Email FROM FactSectionTeachers fst WHERE fst.TeacherEmail IS NOT NULL) t
CROSS APPLY dbo.tvf_TeacherGroups(t.Email, @CycleGroupID, 'Reading') g
WHERE g.Scope = 'Taught'
ORDER BY g.ApplicableStudentCount DESC;

IF @UPN IS NULL
BEGIN
    ;THROW 51001, 'No taught Reading group found for any teacher in the current cycle — check the seed.', 1;
END

/* Show exactly what got measured (so an empty/odd result is diagnosable). */
SELECT @CycleGroupID AS CycleGroupID, @UPN AS TeacherUPN, @WID AS AssessmentWindowID,
       @GroupKeys AS GroupKeys, @Students AS ApplicableStudents;

/* 3 ── timings (wall-clock; server-side only, excludes the app's connection overhead by design) */
DECLARE @t0 DATETIME2(7), @t1 DATETIME2(7), @n BIGINT;
DECLARE @Timings TABLE (Seq INT IDENTITY(1,1), Step VARCHAR(40), Elapsed_ms INT, Rows BIGINT);

-- server-side floor: a trivial statement round-trip
SET @t0 = SYSUTCDATETIME();  SELECT @n = 1;  SET @t1 = SYSUTCDATETIME();
INSERT @Timings (Step, Elapsed_ms, Rows) VALUES ('baseline_select1', DATEDIFF(MILLISECOND, @t0, @t1), @n);

-- roster: cold (first compile + exec)
SET @t0 = SYSUTCDATETIME();
SELECT @n = COUNT_BIG(*) FROM (SELECT * FROM dbo.tvf_TeacherRoster(@UPN, @WID, @GroupKeys)) x;
SET @t1 = SYSUTCDATETIME();
INSERT @Timings (Step, Elapsed_ms, Rows) VALUES ('roster_cold', DATEDIFF(MILLISECOND, @t0, @t1), @n);

-- roster: warm x2 (plan cached; the number the app effectively pays on a repeat open)
SET @t0 = SYSUTCDATETIME();
SELECT @n = COUNT_BIG(*) FROM (SELECT * FROM dbo.tvf_TeacherRoster(@UPN, @WID, @GroupKeys)) x;
SET @t1 = SYSUTCDATETIME();
INSERT @Timings (Step, Elapsed_ms, Rows) VALUES ('roster_warm1', DATEDIFF(MILLISECOND, @t0, @t1), @n);

SET @t0 = SYSUTCDATETIME();
SELECT @n = COUNT_BIG(*) FROM (SELECT * FROM dbo.tvf_TeacherRoster(@UPN, @WID, @GroupKeys)) x;
SET @t1 = SYSUTCDATETIME();
INSERT @Timings (Step, Elapsed_ms, Rows) VALUES ('roster_warm2', DATEDIFF(MILLISECOND, @t0, @t1), @n);

-- groups picker: cold + warm (the perf item tied to pre-warm / min-connections)
SET @t0 = SYSUTCDATETIME();
SELECT @n = COUNT_BIG(*) FROM (SELECT * FROM dbo.tvf_TeacherGroups(@UPN, @CycleGroupID, 'Reading')) x;
SET @t1 = SYSUTCDATETIME();
INSERT @Timings (Step, Elapsed_ms, Rows) VALUES ('groups_cold', DATEDIFF(MILLISECOND, @t0, @t1), @n);

SET @t0 = SYSUTCDATETIME();
SELECT @n = COUNT_BIG(*) FROM (SELECT * FROM dbo.tvf_TeacherGroups(@UPN, @CycleGroupID, 'Reading')) x;
SET @t1 = SYSUTCDATETIME();
INSERT @Timings (Step, Elapsed_ms, Rows) VALUES ('groups_warm1', DATEDIFF(MILLISECOND, @t0, @t1), @n);

SELECT Step, Elapsed_ms, Rows FROM @Timings ORDER BY Seq;
