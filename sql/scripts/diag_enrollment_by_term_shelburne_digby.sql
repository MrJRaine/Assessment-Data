/*───────────────────────────────────────────────────────────────────────────────────────────
  diag_enrollment_by_term_shelburne_digby.sql
  Purpose: Explain why the O2 report shows no Semester 2 rows — is S2 enrollment "not pulled yet"
           or "not active yet"? Breaks sections vs. active enrollments out by semester for DRHS/SRHS.
  Type: READ-ONLY (three SELECTs). Run against LIVE Assessment_Warehouse.
  Region: Canada East.

  Expected pattern (confirms "not pulled yet, not the ActiveFlag"):
   - Query 1: S1 / S2 / Year-Long SECTIONS all exist (Sections export pulls the whole year).
   - Query 2: active ENROLLMENTS exist for S1 (+ Year-Long) but ~ZERO for S2 — because the CC export
     only sends currently-active enrollments and S2 hasn't started (DateEnrolled in the future).
   - Query 3: any S2 enrollment rows that DO exist would be ActiveFlag=1 (term-end is in the future),
     proving the flag isn't what's hiding S2.
───────────────────────────────────────────────────────────────────────────────────────────*/

-- 1) Current SECTIONS by semester (these exist for the whole year).
SELECT sch.SchoolName, dt.TermName, COUNT(*) AS Sections
FROM DimSection sec
INNER JOIN DimSchool sch ON sch.SchoolID = sec.SchoolID
LEFT  JOIN DimTerm  dt  ON dt.TermID   = sec.TermID
WHERE sec.IsCurrent = 1 AND sec.SchoolID IN ('0709', '0716')
GROUP BY sch.SchoolName, dt.TermCode, dt.TermName
ORDER BY sch.SchoolName, dt.TermCode;

-- 2) Active ENROLLMENTS by semester (expect S1/Year-Long populated, S2 ~empty).
SELECT sch.SchoolName, dt.TermName,
       COUNT(*)                                              AS EnrollmentRows,
       SUM(CASE WHEN e.ActiveFlag = 1 THEN 1 ELSE 0 END)     AS ActiveRows,
       MIN(e.StartDate)                                      AS EarliestStart,
       MAX(e.StartDate)                                      AS LatestStart
FROM FactEnrollment e
INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
INNER JOIN DimSchool  sch ON sch.SchoolID   = sec.SchoolID
LEFT  JOIN DimTerm    dt  ON dt.TermID       = sec.TermID
WHERE sec.SchoolID IN ('0709', '0716')
GROUP BY sch.SchoolName, dt.TermCode, dt.TermName
ORDER BY sch.SchoolName, dt.TermCode;

-- 3) Do ANY Semester 2 enrollment rows exist, and what's their ActiveFlag? (TermCode 2 = Semester 2.)
--    If this returns nothing, S2 enrollment simply isn't pulled yet.
SELECT sch.SchoolName, sec.CourseName, sec.SectionNumber,
       e.StartDate, e.EndDate, e.ActiveFlag
FROM FactEnrollment e
INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
INNER JOIN DimSchool  sch ON sch.SchoolID   = sec.SchoolID
INNER JOIN DimTerm    dt  ON dt.TermID       = sec.TermID AND dt.TermCode = 2
WHERE sec.SchoolID IN ('0709', '0716')
ORDER BY sch.SchoolName, sec.CourseName, sec.SectionNumber;
