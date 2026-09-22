/*******************************************************************************
 * Script: diag_reading_instance_counts.sql   (READ-ONLY — config + aggregate counts)
 * Purpose: Diagnose why the /enter Reading card only counts English students and
 *          not the immersion (French) reading instance. The card sums
 *          ApplicableStudentCount across a cycle's reading instances; if the sum
 *          is English-only, the French reading instance is contributing 0. This
 *          shows WHERE it's lost, without pinning a cause first.
 *
 * How to read the three result sets:
 *   A) INSTANCES (config, no PII): every active Reading/Writing instance per
 *      cycle. If there is NO 'Reading' row with AssessmentLanguage='French' for
 *      the cycle in question -> the instance doesn't exist (cause 1); fix the
 *      cycle config, not code.
 *   B) COUNTS (aggregate): tvf_UserAssessmentWindows for @UPN, reading+writing.
 *      Compare the French READING row's ApplicableStudentCount to the French
 *      WRITING row's. The TVF filters reading and writing IDENTICALLY, so:
 *        - French writing > 0 but French reading = 0 -> reading-specific data
 *          (French reading instance missing / wrong grade band / inactive).
 *        - Both French rows = 0 -> the shared cause: this caller has no FLA
 *          students in scope (causes 2/3/4).
 *   C) TEACHER COURSE COVERAGE (teacher branch only): the literacy languages the
 *      caller can actually enter, via their sections -> DimCourseAssessment. If
 *      'French' is absent here, the caller teaches no FLA section, so the French
 *      reading instance legitimately counts 0 for them (cause 4), or the FLA
 *      course isn't mapped (cause 3).
 *
 * SET @UPN to the account that shows the bug. Default is a known dev FLA teacher
 * from the current synthetic set; change it to whoever you were signed in as.
 * Run on DEV. Region: Canada East (PIIDPA compliant).
 ******************************************************************************/

DECLARE @UPN VARCHAR(255) = 'classroom.teacher1@tcrce.ca';   -- <- change to the account showing the bug

-- ===== A) INSTANCES per cycle (config only, no PII) =====
SELECT
    h.DisplayName                AS Cycle,
    w.AssessmentType,
    w.AssessmentLanguage,        -- 'English' | 'French' | NULL(Both)
    w.ProgramScope,
    w.MinGrade, w.MaxGrade,
    w.ScaleSystem,
    w.ActiveFlag,
    w.AssessmentWindowID
FROM DimAssessmentWindow w
INNER JOIN DimShortCycle h ON h.CycleGroupID = w.CycleGroupID
WHERE w.AssessmentType IN ('Reading', 'Writing')
ORDER BY h.DisplayName, w.AssessmentType, w.AssessmentLanguage, w.MinGrade;

-- ===== B) COUNTS from the TVF for @UPN (aggregate) =====
SELECT
    CycleName,
    AssessmentType,
    AssessmentLanguage,
    ProgramScope,
    MinGrade, MaxGrade,
    WindowStatus,
    ApplicableStudentCount,
    EnteredStudentCount,
    AssessmentWindowID
FROM dbo.tvf_UserAssessmentWindows(@UPN)
WHERE AssessmentType IN ('Reading', 'Writing')
ORDER BY CycleName, AssessmentType, AssessmentLanguage, MinGrade;

-- ===== C) TEACHER COURSE-LANGUAGE COVERAGE for @UPN (teacher branch only) =====
-- The literacy languages this caller can enter, via their current sections. If
-- 'French'/'Literacy' is missing, they teach no FLA section (or FLA isn't mapped).
SELECT DISTINCT
    sec.CourseCode,
    ca.Language,
    ca.Kind
FROM DimStaff st
INNER JOIN FactSectionTeachers fst
        ON LOWER(fst.TeacherEmail) = LOWER(@UPN)
       AND CAST(GETDATE() AS DATE) BETWEEN fst.EffectiveStartDate AND COALESCE(fst.EffectiveEndDate, '9999-12-31')
INNER JOIN DimSection sec
        ON sec.SectionID = fst.SectionID
       AND CAST(GETDATE() AS DATE) BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
LEFT JOIN DimCourseAssessment ca
        ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
WHERE LOWER(st.Email) = LOWER(@UPN) AND st.IsCurrent = 1
ORDER BY ca.Kind, ca.Language, sec.CourseCode;
