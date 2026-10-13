/*******************************************************************************
 * Script: diag_ches_sc1_section_reversion_2026-10-13.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: CONFIRM the Short-Cycle-1 sparse-roster cause. Enrollment fully overlaps SC1
 *          (diag_ches_sc1_enrollment_dates: OverlapSC1 = full), yet SectionRosterMembership
 *          shows ~1 for SC1 while SC2-6 are full. usp_RebuildRosterMembership resolves a
 *          CLOSED window's sections AS OF the window EndDate (SC1 -> 2026-10-05) and joins
 *          enrollment to THAT section version's SectionKey. If DimSection re-versioned after
 *          Oct 5, the current FactEnrollment (re-pointed to the CURRENT SectionKey on ingest)
 *          no longer matches the Oct-5 version -> SC1 under-populates. This checks exactly that.
 *
 * Reads:  DimSection, FactEnrollment (current rows). Section metadata + COUNTS only — NO PII.
 * Region: Canada East (PIIDPA compliant)
 *
 * Sample sections = the ELA6 (141049) + ILA3 (141130) cards, plus 140873 (all had SC1=1 in the
 * membership diag but full current enrollment). Adjust the IN list to taste.
 *
 * Confirms the theory if, per section: the version in force on 2026-10-05 is NOT IsCurrent (a
 * re-version happened since), and ActiveEnrollmentsOnThatKey is ~1 while the class is 18-22 —
 * i.e. the live enrollment points at a DIFFERENT (current) SectionKey than the one SC1 resolves.
 ******************************************************************************/

SET NOCOUNT ON;

-- ============ (1) DimSection version history for the sample sections ============
-- A section with >1 row here re-versioned; note where a version boundary falls after 2026-10-05.
SELECT
    sec.SectionID,
    sec.SectionNumber,
    sec.CourseName,
    sec.SectionKey,
    sec.EffectiveStartDate,
    sec.EffectiveEndDate,
    sec.IsCurrent
FROM DimSection sec
WHERE sec.SectionID IN ('141049', '141130', '140873')
ORDER BY sec.SectionID, sec.EffectiveStartDate;
GO

-- ============ (2) The version SC1 resolves (in force on Oct 5) vs the live enrollment it holds ============
-- SC1's rebuild picks the version whose range contains 2026-10-05, then joins enrollment on its
-- SectionKey. If that version is stale (IsCurrent = 0) and holds ~1 active enrollment while the
-- class is full, that's the SC1 under-population — the enrollment moved to the current SectionKey.
SELECT
    secAtSC1.SectionID,
    secAtSC1.SectionNumber,
    secAtSC1.CourseName,
    secAtSC1.SectionKey                          AS SectionKey_on_Oct5,
    secAtSC1.IsCurrent                           AS Oct5VersionIsCurrent,
    COUNT(e.StudentKey)                          AS ActiveEnrollmentsOnOct5Key
FROM DimSection secAtSC1
LEFT JOIN FactEnrollment e
       ON e.SectionKey = secAtSC1.SectionKey AND e.ActiveFlag = 1
WHERE secAtSC1.SectionID IN ('141049', '141130', '140873')
  AND '2026-10-05' BETWEEN secAtSC1.EffectiveStartDate AND COALESCE(secAtSC1.EffectiveEndDate, '9999-12-31')
GROUP BY secAtSC1.SectionID, secAtSC1.SectionNumber, secAtSC1.CourseName, secAtSC1.SectionKey, secAtSC1.IsCurrent
ORDER BY secAtSC1.SectionID;
GO
