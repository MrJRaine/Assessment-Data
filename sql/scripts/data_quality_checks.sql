/*******************************************************************************
 * Script: data_quality_checks.sql
 * Purpose: Comprehensive data quality validation suite for Assessment_Warehouse.
 *          Single result set: any non-zero output indicates a violation.
 *          Empty result set = all checks pass.
 *
 * Categories covered:
 *   - Orphan       Fact/bridge rows referencing missing dim rows by surrogate key
 *   - IsCurrent    More than one IsCurrent=1 row per business key on Type 2 dims
 *   - Date         Malformed effective windows (NULL/non-NULL mismatches; reversed
 *                  start/end dates; overlapping windows for same business key)
 *   - Reference    Business-key values not present in their reference dim
 *   - Consistency  Logical-state contradictions (e.g. inactive staff with current
 *                  assignments)
 *
 * When to run:
 *   - After every full ingest cycle to confirm merge procs landed cleanly
 *   - After any direct data manipulation in the warehouse
 *   - Before pilot UAT and before September rollout (gate criterion)
 *   - Periodically as a heartbeat once the platform is live
 *
 * Output schema (single UNION ALL result set):
 *   CheckCategory  Orphan / IsCurrent / Date / Reference / Consistency
 *   CheckName      Short description of the rule violated
 *   TableName      Table containing the offending row
 *   KeyColumn      Column name used to identify the offending row
 *   KeyValue       Value of that column for the offending row
 *   Detail         What was wrong (key value that didn't resolve, etc.)
 *
 * Performance note: this script uses LEFT JOIN + IS NULL anti-joins and
 * self-joins on Type 2 dims for overlap detection. At MVP scale (~6k students,
 * ~200 staff, ~hundreds of sections) this completes in seconds. At production
 * scale across multiple school years, expect sub-minute runtimes — still cheap
 * to run on demand.
 *
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

WITH AllChecks AS (

    -- ========================================================================
    -- ORPHAN CHECKS — fact/bridge rows referencing missing dim rows
    -- ========================================================================

    -- 01. FactEnrollment.StudentKey → DimStudent.StudentKey
    SELECT
        CAST('Orphan' AS VARCHAR(20))                                                  AS CheckCategory,
        CAST('FactEnrollment.StudentKey not found in DimStudent' AS VARCHAR(150))      AS CheckName,
        CAST('FactEnrollment' AS VARCHAR(50))                                          AS TableName,
        CAST('EnrollmentID' AS VARCHAR(50))                                            AS KeyColumn,
        CAST(f.EnrollmentID AS VARCHAR(50))                                            AS KeyValue,
        CONCAT('StudentKey=', CAST(f.StudentKey AS VARCHAR(20)), ' has no DimStudent row') AS Detail
    FROM FactEnrollment f
    LEFT JOIN DimStudent s ON s.StudentKey = f.StudentKey
    WHERE s.StudentKey IS NULL

    UNION ALL

    -- 02. FactEnrollment.SectionKey → DimSection.SectionKey
    SELECT
        'Orphan',
        'FactEnrollment.SectionKey not found in DimSection',
        'FactEnrollment',
        'EnrollmentID',
        CAST(f.EnrollmentID AS VARCHAR(50)),
        CONCAT('SectionKey=', CAST(f.SectionKey AS VARCHAR(20)), ' has no DimSection row')
    FROM FactEnrollment f
    LEFT JOIN DimSection sec ON sec.SectionKey = f.SectionKey
    WHERE sec.SectionKey IS NULL

    UNION ALL

    -- 03. FactStaffAssignment.StaffKey → DimStaff.StaffKey
    SELECT
        'Orphan',
        'FactStaffAssignment.StaffKey not found in DimStaff',
        'FactStaffAssignment',
        'StaffAssignmentID',
        CAST(f.StaffAssignmentID AS VARCHAR(50)),
        CONCAT('StaffKey=', CAST(f.StaffKey AS VARCHAR(20)), ' has no DimStaff row')
    FROM FactStaffAssignment f
    LEFT JOIN DimStaff d ON d.StaffKey = f.StaffKey
    WHERE d.StaffKey IS NULL

    UNION ALL

    -- 04. StaffSchoolAccess.StaffKey → DimStaff.StaffKey
    SELECT
        'Orphan',
        'StaffSchoolAccess.StaffKey not found in DimStaff',
        'StaffSchoolAccess',
        'StaffSchoolAccessID',
        CAST(ssa.StaffSchoolAccessID AS VARCHAR(50)),
        CONCAT('StaffKey=', CAST(ssa.StaffKey AS VARCHAR(20)), ' has no DimStaff row')
    FROM StaffSchoolAccess ssa
    LEFT JOIN DimStaff d ON d.StaffKey = ssa.StaffKey
    WHERE d.StaffKey IS NULL

    UNION ALL

    -- 05. FactAssessmentReading.StudentKey → DimStudent.StudentKey
    SELECT
        'Orphan',
        'FactAssessmentReading.StudentKey not found in DimStudent',
        'FactAssessmentReading',
        'ReadingAssessmentID',
        CAST(f.ReadingAssessmentID AS VARCHAR(50)),
        CONCAT('StudentKey=', CAST(f.StudentKey AS VARCHAR(20)), ' has no DimStudent row')
    FROM FactAssessmentReading f
    LEFT JOIN DimStudent s ON s.StudentKey = f.StudentKey
    WHERE s.StudentKey IS NULL

    UNION ALL

    -- 06. FactAssessmentReading.AssessmentWindowID → DimAssessmentWindow
    SELECT
        'Orphan',
        'FactAssessmentReading.AssessmentWindowID not found in DimAssessmentWindow',
        'FactAssessmentReading',
        'ReadingAssessmentID',
        CAST(f.ReadingAssessmentID AS VARCHAR(50)),
        CONCAT('AssessmentWindowID=', CAST(f.AssessmentWindowID AS VARCHAR(20)), ' missing')
    FROM FactAssessmentReading f
    LEFT JOIN DimAssessmentWindow w ON w.AssessmentWindowID = f.AssessmentWindowID
    WHERE f.AssessmentWindowID IS NOT NULL
      AND w.AssessmentWindowID IS NULL

    UNION ALL

    -- 07. FactAssessmentReading.ReadingScaleID → DimReadingScale
    SELECT
        'Orphan',
        'FactAssessmentReading.ReadingScaleID not found in DimReadingScale',
        'FactAssessmentReading',
        'ReadingAssessmentID',
        CAST(f.ReadingAssessmentID AS VARCHAR(50)),
        CONCAT('ReadingScaleID=', CAST(f.ReadingScaleID AS VARCHAR(20)), ' missing')
    FROM FactAssessmentReading f
    LEFT JOIN DimReadingScale r ON r.ReadingScaleID = f.ReadingScaleID
    WHERE f.ReadingScaleID IS NOT NULL
      AND r.ReadingScaleID IS NULL

    UNION ALL

    -- 08. FactAssessmentReading.EnteredByStaffKey → DimStaff.StaffKey (when populated)
    SELECT
        'Orphan',
        'FactAssessmentReading.EnteredByStaffKey not found in DimStaff',
        'FactAssessmentReading',
        'ReadingAssessmentID',
        CAST(f.ReadingAssessmentID AS VARCHAR(50)),
        CONCAT('EnteredByStaffKey=', CAST(f.EnteredByStaffKey AS VARCHAR(20)), ' has no DimStaff row')
    FROM FactAssessmentReading f
    LEFT JOIN DimStaff d ON d.StaffKey = f.EnteredByStaffKey
    WHERE f.EnteredByStaffKey IS NOT NULL
      AND d.StaffKey IS NULL

    UNION ALL

    -- 09. DimStudent.SchoolID → DimSchool.SchoolID
    SELECT
        'Orphan',
        'DimStudent.SchoolID not found in DimSchool',
        'DimStudent',
        'StudentKey',
        CAST(s.StudentKey AS VARCHAR(50)),
        CONCAT('SchoolID=', s.SchoolID, ' not in DimSchool')
    FROM DimStudent s
    LEFT JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
    WHERE s.SchoolID IS NOT NULL
      AND sch.SchoolID IS NULL

    UNION ALL

    -- 10. DimSection.SchoolID → DimSchool.SchoolID
    SELECT
        'Orphan',
        'DimSection.SchoolID not found in DimSchool',
        'DimSection',
        'SectionKey',
        CAST(sec.SectionKey AS VARCHAR(50)),
        CONCAT('SchoolID=', sec.SchoolID, ' not in DimSchool')
    FROM DimSection sec
    LEFT JOIN DimSchool sch ON sch.SchoolID = sec.SchoolID
    WHERE sec.SchoolID IS NOT NULL
      AND sch.SchoolID IS NULL

    UNION ALL

    -- 11. DimStaff.HomeSchoolID → DimSchool.SchoolID (when populated)
    SELECT
        'Orphan',
        'DimStaff.HomeSchoolID not found in DimSchool',
        'DimStaff',
        'StaffKey',
        CAST(d.StaffKey AS VARCHAR(50)),
        CONCAT('HomeSchoolID=', d.HomeSchoolID, ' not in DimSchool')
    FROM DimStaff d
    LEFT JOIN DimSchool sch ON sch.SchoolID = d.HomeSchoolID
    WHERE d.HomeSchoolID IS NOT NULL
      AND sch.SchoolID IS NULL

    UNION ALL

    -- 12. DimSection.TermID → DimTerm.TermID
    SELECT
        'Orphan',
        'DimSection.TermID not found in DimTerm',
        'DimSection',
        'SectionKey',
        CAST(sec.SectionKey AS VARCHAR(50)),
        CONCAT('TermID=', CAST(sec.TermID AS VARCHAR(20)), ' not in DimTerm')
    FROM DimSection sec
    LEFT JOIN DimTerm t ON t.TermID = sec.TermID
    WHERE t.TermID IS NULL

    UNION ALL

    -- 13. FactStaffAssignment.SchoolID → DimSchool.SchoolID
    --      Special case: '0000' is the district-level aggregate-row marker —
    --      it's intentional and does NOT exist in DimSchool. Exclude from the
    --      orphan check.
    SELECT
        'Orphan',
        'FactStaffAssignment.SchoolID not found in DimSchool',
        'FactStaffAssignment',
        'StaffAssignmentID',
        CAST(f.StaffAssignmentID AS VARCHAR(50)),
        CONCAT('SchoolID=', f.SchoolID, ' not in DimSchool')
    FROM FactStaffAssignment f
    LEFT JOIN DimSchool sch ON sch.SchoolID = f.SchoolID
    WHERE f.SchoolID <> '0000'
      AND sch.SchoolID IS NULL

    UNION ALL

    -- 14. StaffSchoolAccess.SchoolID → DimSchool.SchoolID
    --      Same '0000' aggregate-row marker exception as #13.
    SELECT
        'Orphan',
        'StaffSchoolAccess.SchoolID not found in DimSchool',
        'StaffSchoolAccess',
        'StaffSchoolAccessID',
        CAST(ssa.StaffSchoolAccessID AS VARCHAR(50)),
        CONCAT('SchoolID=', ssa.SchoolID, ' not in DimSchool')
    FROM StaffSchoolAccess ssa
    LEFT JOIN DimSchool sch ON sch.SchoolID = ssa.SchoolID
    WHERE ssa.SchoolID <> '0000'
      AND sch.SchoolID IS NULL

    UNION ALL

    -- 15. FactSectionTeachers.SectionID → some DimSection row (any version)
    --      Bridge keys on business keys, not surrogates — so the check is
    --      "does this SectionID exist anywhere in DimSection's history?"
    SELECT
        'Orphan',
        'FactSectionTeachers.SectionID not found in any DimSection version',
        'FactSectionTeachers',
        'SectionTeacherID',
        CAST(fst.SectionTeacherID AS VARCHAR(50)),
        CONCAT('SectionID=', fst.SectionID, ' not in DimSection')
    FROM FactSectionTeachers fst
    WHERE NOT EXISTS (
        SELECT 1 FROM DimSection sec WHERE sec.SectionID = fst.SectionID
    )

    UNION ALL

    -- 16. FactSectionTeachers.TeacherEmail → some DimStaff row (any version)
    SELECT
        'Orphan',
        'FactSectionTeachers.TeacherEmail not found in any DimStaff version',
        'FactSectionTeachers',
        'SectionTeacherID',
        CAST(fst.SectionTeacherID AS VARCHAR(50)),
        CONCAT('TeacherEmail=', fst.TeacherEmail, ' not in DimStaff')
    FROM FactSectionTeachers fst
    WHERE NOT EXISTS (
        SELECT 1 FROM DimStaff d WHERE LOWER(d.Email) = LOWER(fst.TeacherEmail)
    )

    UNION ALL

    -- ========================================================================
    -- ISCURRENT CHECKS — more than one IsCurrent=1 row per business key
    -- ========================================================================

    -- 17. DimStudent: multiple current rows per StudentNumber
    SELECT
        'IsCurrent',
        'DimStudent: multiple IsCurrent=1 rows for same StudentNumber',
        'DimStudent',
        'StudentNumber',
        CAST(StudentNumber AS VARCHAR(50)),
        CONCAT(CAST(COUNT(*) AS VARCHAR(10)), ' current rows (expected 1)')
    FROM DimStudent
    WHERE IsCurrent = 1
    GROUP BY StudentNumber
    HAVING COUNT(*) > 1

    UNION ALL

    -- 18. DimStaff: multiple current rows per Email
    SELECT
        'IsCurrent',
        'DimStaff: multiple IsCurrent=1 rows for same Email',
        'DimStaff',
        'Email',
        Email,
        CONCAT(CAST(COUNT(*) AS VARCHAR(10)), ' current rows (expected 1)')
    FROM DimStaff
    WHERE IsCurrent = 1
    GROUP BY Email
    HAVING COUNT(*) > 1

    UNION ALL

    -- 19. DimSection: multiple current rows per SectionID
    SELECT
        'IsCurrent',
        'DimSection: multiple IsCurrent=1 rows for same SectionID',
        'DimSection',
        'SectionID',
        SectionID,
        CONCAT(CAST(COUNT(*) AS VARCHAR(10)), ' current rows (expected 1)')
    FROM DimSection
    WHERE IsCurrent = 1
    GROUP BY SectionID
    HAVING COUNT(*) > 1

    UNION ALL

    -- 20. FactStaffAssignment: multiple current rows per (StaffKey, SchoolID, RoleCode)
    SELECT
        'IsCurrent',
        'FactStaffAssignment: multiple IsCurrent=1 rows per (StaffKey, SchoolID, RoleCode)',
        'FactStaffAssignment',
        'Triple',
        CONCAT(CAST(StaffKey AS VARCHAR(20)), '|', SchoolID, '|', RoleCode),
        CONCAT(CAST(COUNT(*) AS VARCHAR(10)), ' current rows (expected 1)')
    FROM FactStaffAssignment
    WHERE IsCurrent = 1
    GROUP BY StaffKey, SchoolID, RoleCode
    HAVING COUNT(*) > 1

    UNION ALL

    -- 21. FactSectionTeachers: multiple current rows per (SectionID, TeacherEmail, TeacherRole)
    SELECT
        'IsCurrent',
        'FactSectionTeachers: multiple IsCurrent=1 rows per (SectionID, TeacherEmail, TeacherRole)',
        'FactSectionTeachers',
        'Triple',
        CONCAT(SectionID, '|', TeacherEmail, '|', TeacherRole),
        CONCAT(CAST(COUNT(*) AS VARCHAR(10)), ' current rows (expected 1)')
    FROM FactSectionTeachers
    WHERE IsCurrent = 1
    GROUP BY SectionID, TeacherEmail, TeacherRole
    HAVING COUNT(*) > 1

    UNION ALL

    -- ========================================================================
    -- DATE CHECKS — effective-window integrity on Type 2 dims and bridges
    --   Rule A: IsCurrent=1 ⇒ EffectiveEndDate IS NULL
    --   Rule B: IsCurrent=0 ⇒ EffectiveEndDate IS NOT NULL
    --   Rule C: EffectiveEndDate >= EffectiveStartDate (when both populated)
    --   Rule D: no overlapping windows for same business key
    -- ========================================================================

    -- 22. DimStudent — IsCurrent=1 with non-NULL EffectiveEndDate (Rule A)
    SELECT
        'Date',
        'DimStudent: IsCurrent=1 row has non-NULL EffectiveEndDate (rule A)',
        'DimStudent',
        'StudentKey',
        CAST(StudentKey AS VARCHAR(50)),
        CONCAT('EffectiveEndDate=', CAST(EffectiveEndDate AS VARCHAR(20)))
    FROM DimStudent
    WHERE IsCurrent = 1 AND EffectiveEndDate IS NOT NULL

    UNION ALL

    -- 23. DimStudent — IsCurrent=0 with NULL EffectiveEndDate (Rule B)
    SELECT
        'Date',
        'DimStudent: IsCurrent=0 row has NULL EffectiveEndDate (rule B)',
        'DimStudent',
        'StudentKey',
        CAST(StudentKey AS VARCHAR(50)),
        'IsCurrent=0 but EffectiveEndDate is NULL'
    FROM DimStudent
    WHERE IsCurrent = 0 AND EffectiveEndDate IS NULL

    UNION ALL

    -- 24. DimStudent — reversed effective window (Rule C)
    SELECT
        'Date',
        'DimStudent: EffectiveEndDate < EffectiveStartDate (rule C)',
        'DimStudent',
        'StudentKey',
        CAST(StudentKey AS VARCHAR(50)),
        CONCAT('Start=', CAST(EffectiveStartDate AS VARCHAR(20)),
               ' End=', CAST(EffectiveEndDate AS VARCHAR(20)))
    FROM DimStudent
    WHERE EffectiveEndDate IS NOT NULL
      AND EffectiveEndDate < EffectiveStartDate

    UNION ALL

    -- 25. DimStudent — overlapping windows for same StudentNumber (Rule D)
    --      Treats NULL EffectiveEndDate as 9999-12-31 (open-ended). Self-join
    --      with StudentKey ordering avoids reporting each pair twice.
    SELECT
        'Date',
        'DimStudent: overlapping effective windows for same StudentNumber (rule D)',
        'DimStudent',
        'StudentNumber',
        CAST(a.StudentNumber AS VARCHAR(50)),
        CONCAT('StudentKeys ', CAST(a.StudentKey AS VARCHAR(20)), ' & ', CAST(b.StudentKey AS VARCHAR(20)),
               ' overlap on [', CAST(a.EffectiveStartDate AS VARCHAR(20)),
               ', ', COALESCE(CAST(a.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'),
               '] vs [', CAST(b.EffectiveStartDate AS VARCHAR(20)),
               ', ', COALESCE(CAST(b.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'), ']')
    FROM DimStudent a
    INNER JOIN DimStudent b
            ON a.StudentNumber = b.StudentNumber
           AND a.StudentKey < b.StudentKey
    WHERE a.EffectiveStartDate <= COALESCE(b.EffectiveEndDate, '9999-12-31')
      AND COALESCE(a.EffectiveEndDate, '9999-12-31') >= b.EffectiveStartDate

    UNION ALL

    -- 26. DimStaff — IsCurrent=1 with non-NULL EffectiveEndDate (Rule A)
    SELECT
        'Date',
        'DimStaff: IsCurrent=1 row has non-NULL EffectiveEndDate (rule A)',
        'DimStaff',
        'StaffKey',
        CAST(StaffKey AS VARCHAR(50)),
        CONCAT('EffectiveEndDate=', CAST(EffectiveEndDate AS VARCHAR(20)))
    FROM DimStaff
    WHERE IsCurrent = 1 AND EffectiveEndDate IS NOT NULL

    UNION ALL

    -- 27. DimStaff — IsCurrent=0 with NULL EffectiveEndDate (Rule B)
    SELECT
        'Date',
        'DimStaff: IsCurrent=0 row has NULL EffectiveEndDate (rule B)',
        'DimStaff',
        'StaffKey',
        CAST(StaffKey AS VARCHAR(50)),
        'IsCurrent=0 but EffectiveEndDate is NULL'
    FROM DimStaff
    WHERE IsCurrent = 0 AND EffectiveEndDate IS NULL

    UNION ALL

    -- 28. DimStaff — reversed effective window (Rule C)
    SELECT
        'Date',
        'DimStaff: EffectiveEndDate < EffectiveStartDate (rule C)',
        'DimStaff',
        'StaffKey',
        CAST(StaffKey AS VARCHAR(50)),
        CONCAT('Start=', CAST(EffectiveStartDate AS VARCHAR(20)),
               ' End=', CAST(EffectiveEndDate AS VARCHAR(20)))
    FROM DimStaff
    WHERE EffectiveEndDate IS NOT NULL
      AND EffectiveEndDate < EffectiveStartDate

    UNION ALL

    -- 29. DimStaff — overlapping windows for same Email (Rule D)
    SELECT
        'Date',
        'DimStaff: overlapping effective windows for same Email (rule D)',
        'DimStaff',
        'Email',
        a.Email,
        CONCAT('StaffKeys ', CAST(a.StaffKey AS VARCHAR(20)), ' & ', CAST(b.StaffKey AS VARCHAR(20)),
               ' overlap on [', CAST(a.EffectiveStartDate AS VARCHAR(20)),
               ', ', COALESCE(CAST(a.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'),
               '] vs [', CAST(b.EffectiveStartDate AS VARCHAR(20)),
               ', ', COALESCE(CAST(b.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'), ']')
    FROM DimStaff a
    INNER JOIN DimStaff b
            ON a.Email = b.Email
           AND a.StaffKey < b.StaffKey
    WHERE a.EffectiveStartDate <= COALESCE(b.EffectiveEndDate, '9999-12-31')
      AND COALESCE(a.EffectiveEndDate, '9999-12-31') >= b.EffectiveStartDate

    UNION ALL

    -- 30. DimSection — IsCurrent=1 with non-NULL EffectiveEndDate (Rule A)
    SELECT
        'Date',
        'DimSection: IsCurrent=1 row has non-NULL EffectiveEndDate (rule A)',
        'DimSection',
        'SectionKey',
        CAST(SectionKey AS VARCHAR(50)),
        CONCAT('EffectiveEndDate=', CAST(EffectiveEndDate AS VARCHAR(20)))
    FROM DimSection
    WHERE IsCurrent = 1 AND EffectiveEndDate IS NOT NULL

    UNION ALL

    -- 31. DimSection — IsCurrent=0 with NULL EffectiveEndDate (Rule B)
    SELECT
        'Date',
        'DimSection: IsCurrent=0 row has NULL EffectiveEndDate (rule B)',
        'DimSection',
        'SectionKey',
        CAST(SectionKey AS VARCHAR(50)),
        'IsCurrent=0 but EffectiveEndDate is NULL'
    FROM DimSection
    WHERE IsCurrent = 0 AND EffectiveEndDate IS NULL

    UNION ALL

    -- 32. DimSection — reversed effective window (Rule C)
    SELECT
        'Date',
        'DimSection: EffectiveEndDate < EffectiveStartDate (rule C)',
        'DimSection',
        'SectionKey',
        CAST(SectionKey AS VARCHAR(50)),
        CONCAT('Start=', CAST(EffectiveStartDate AS VARCHAR(20)),
               ' End=', CAST(EffectiveEndDate AS VARCHAR(20)))
    FROM DimSection
    WHERE EffectiveEndDate IS NOT NULL
      AND EffectiveEndDate < EffectiveStartDate

    UNION ALL

    -- 33. DimSection — overlapping windows for same SectionID (Rule D)
    SELECT
        'Date',
        'DimSection: overlapping effective windows for same SectionID (rule D)',
        'DimSection',
        'SectionID',
        a.SectionID,
        CONCAT('SectionKeys ', CAST(a.SectionKey AS VARCHAR(20)), ' & ', CAST(b.SectionKey AS VARCHAR(20)),
               ' overlap on [', CAST(a.EffectiveStartDate AS VARCHAR(20)),
               ', ', COALESCE(CAST(a.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'),
               '] vs [', CAST(b.EffectiveStartDate AS VARCHAR(20)),
               ', ', COALESCE(CAST(b.EffectiveEndDate AS VARCHAR(20)), '9999-12-31'), ']')
    FROM DimSection a
    INNER JOIN DimSection b
            ON a.SectionID = b.SectionID
           AND a.SectionKey < b.SectionKey
    WHERE a.EffectiveStartDate <= COALESCE(b.EffectiveEndDate, '9999-12-31')
      AND COALESCE(a.EffectiveEndDate, '9999-12-31') >= b.EffectiveStartDate

    UNION ALL

    -- 34. FactStaffAssignment — IsCurrent=1 with non-NULL EffectiveEndDate
    SELECT
        'Date',
        'FactStaffAssignment: IsCurrent=1 row has non-NULL EffectiveEndDate (rule A)',
        'FactStaffAssignment',
        'StaffAssignmentID',
        CAST(StaffAssignmentID AS VARCHAR(50)),
        CONCAT('EffectiveEndDate=', CAST(EffectiveEndDate AS VARCHAR(20)))
    FROM FactStaffAssignment
    WHERE IsCurrent = 1 AND EffectiveEndDate IS NOT NULL

    UNION ALL

    -- 35. FactStaffAssignment — IsCurrent=0 with NULL EffectiveEndDate
    SELECT
        'Date',
        'FactStaffAssignment: IsCurrent=0 row has NULL EffectiveEndDate (rule B)',
        'FactStaffAssignment',
        'StaffAssignmentID',
        CAST(StaffAssignmentID AS VARCHAR(50)),
        'IsCurrent=0 but EffectiveEndDate is NULL'
    FROM FactStaffAssignment
    WHERE IsCurrent = 0 AND EffectiveEndDate IS NULL

    UNION ALL

    -- 36. FactStaffAssignment — reversed effective window
    SELECT
        'Date',
        'FactStaffAssignment: EffectiveEndDate < EffectiveStartDate (rule C)',
        'FactStaffAssignment',
        'StaffAssignmentID',
        CAST(StaffAssignmentID AS VARCHAR(50)),
        CONCAT('Start=', CAST(EffectiveStartDate AS VARCHAR(20)),
               ' End=', CAST(EffectiveEndDate AS VARCHAR(20)))
    FROM FactStaffAssignment
    WHERE EffectiveEndDate IS NOT NULL
      AND EffectiveEndDate < EffectiveStartDate

    UNION ALL

    -- 37. FactSectionTeachers — IsCurrent=1 with non-NULL EffectiveEndDate
    SELECT
        'Date',
        'FactSectionTeachers: IsCurrent=1 row has non-NULL EffectiveEndDate (rule A)',
        'FactSectionTeachers',
        'SectionTeacherID',
        CAST(SectionTeacherID AS VARCHAR(50)),
        CONCAT('EffectiveEndDate=', CAST(EffectiveEndDate AS VARCHAR(20)))
    FROM FactSectionTeachers
    WHERE IsCurrent = 1 AND EffectiveEndDate IS NOT NULL

    UNION ALL

    -- 38. FactSectionTeachers — IsCurrent=0 with NULL EffectiveEndDate
    SELECT
        'Date',
        'FactSectionTeachers: IsCurrent=0 row has NULL EffectiveEndDate (rule B)',
        'FactSectionTeachers',
        'SectionTeacherID',
        CAST(SectionTeacherID AS VARCHAR(50)),
        'IsCurrent=0 but EffectiveEndDate is NULL'
    FROM FactSectionTeachers
    WHERE IsCurrent = 0 AND EffectiveEndDate IS NULL

    UNION ALL

    -- 39. FactSectionTeachers — reversed effective window
    SELECT
        'Date',
        'FactSectionTeachers: EffectiveEndDate < EffectiveStartDate (rule C)',
        'FactSectionTeachers',
        'SectionTeacherID',
        CAST(SectionTeacherID AS VARCHAR(50)),
        CONCAT('Start=', CAST(EffectiveStartDate AS VARCHAR(20)),
               ' End=', CAST(EffectiveEndDate AS VARCHAR(20)))
    FROM FactSectionTeachers
    WHERE EffectiveEndDate IS NOT NULL
      AND EffectiveEndDate < EffectiveStartDate

    UNION ALL

    -- 40. FactEnrollment — reversed enrollment dates (StartDate / EndDate are
    --      domain dates, not SCD effective dates; rule C only)
    SELECT
        'Date',
        'FactEnrollment: EndDate < StartDate',
        'FactEnrollment',
        'EnrollmentID',
        CAST(EnrollmentID AS VARCHAR(50)),
        CONCAT('Start=', CAST(StartDate AS VARCHAR(20)),
               ' End=', CAST(EndDate AS VARCHAR(20)))
    FROM FactEnrollment
    WHERE EndDate IS NOT NULL
      AND EndDate < StartDate

    UNION ALL

    -- ========================================================================
    -- REFERENCE CHECKS — business-key values not in their reference dim
    -- ========================================================================

    -- 41. DimStudent.ProgramCode → DimProgram.ProgramCode
    SELECT
        'Reference',
        'DimStudent.ProgramCode not found in DimProgram',
        'DimStudent',
        'StudentKey',
        CAST(s.StudentKey AS VARCHAR(50)),
        CONCAT('ProgramCode=', s.ProgramCode, ' not in DimProgram')
    FROM DimStudent s
    LEFT JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    WHERE s.ProgramCode IS NOT NULL
      AND p.ProgramCode IS NULL

    UNION ALL

    -- 42. DimStudent.Gender → DimGender.GenderCode
    SELECT
        'Reference',
        'DimStudent.Gender not found in DimGender',
        'DimStudent',
        'StudentKey',
        CAST(s.StudentKey AS VARCHAR(50)),
        CONCAT('Gender=', s.Gender, ' not in DimGender')
    FROM DimStudent s
    LEFT JOIN DimGender g ON g.GenderCode = s.Gender
    WHERE s.Gender IS NOT NULL
      AND g.GenderCode IS NULL

    UNION ALL

    -- 43. FactStaffAssignment.RoleCode → DimRole.RoleCode
    --      DimRole keys on RoleNumber, not RoleCode, so check is "is this
    --      RoleCode one of the values present in DimRole?"
    SELECT
        'Reference',
        'FactStaffAssignment.RoleCode not present in DimRole',
        'FactStaffAssignment',
        'StaffAssignmentID',
        CAST(f.StaffAssignmentID AS VARCHAR(50)),
        CONCAT('RoleCode=', f.RoleCode, ' not in DimRole.RoleCode')
    FROM FactStaffAssignment f
    WHERE NOT EXISTS (
        SELECT 1 FROM DimRole r WHERE r.RoleCode = f.RoleCode
    )

    UNION ALL

    -- 44. DimStudent.EnrollStatus must be 0 or -1 (production import filter)
    --      Schema technically allows any INT, but the import filter restricts.
    --      Anything else means rogue data.
    SELECT
        'Reference',
        'DimStudent.EnrollStatus outside expected (0, -1)',
        'DimStudent',
        'StudentKey',
        CAST(StudentKey AS VARCHAR(50)),
        CONCAT('EnrollStatus=', CAST(EnrollStatus AS VARCHAR(10)),
               ' (expected 0 = Active or -1 = Pre-Enrolled)')
    FROM DimStudent
    WHERE EnrollStatus NOT IN (0, -1)

    UNION ALL

    -- ========================================================================
    -- CONSISTENCY CHECKS — logical-state contradictions
    -- ========================================================================

    -- 45. DimStaff currently active (IsCurrent=1, ActiveFlag=0) should have
    --      NO current FactStaffAssignment rows. The merge proc closes them
    --      when staff go inactive (Step 5b in usp_MergeStaff). Any current
    --      row left under an inactive person means the close didn't happen.
    SELECT
        'Consistency',
        'Inactive DimStaff (ActiveFlag=0) has current FactStaffAssignment row',
        'FactStaffAssignment',
        'StaffAssignmentID',
        CAST(f.StaffAssignmentID AS VARCHAR(50)),
        CONCAT('StaffKey=', CAST(d.StaffKey AS VARCHAR(20)),
               ' (', d.Email, ') ActiveFlag=0 but bridge IsCurrent=1')
    FROM FactStaffAssignment f
    INNER JOIN DimStaff d ON d.StaffKey = f.StaffKey
    WHERE f.IsCurrent = 1
      AND d.IsCurrent = 1
      AND d.ActiveFlag = 0

    UNION ALL

    -- 46. DimStaff inactive deactivation marker should have AccessLevel = NULL
    --      (merge proc Step 4c sets AccessLevel to NULL when inserting the
    --      deactivation row).
    SELECT
        'Consistency',
        'DimStaff inactive row has non-NULL AccessLevel',
        'DimStaff',
        'StaffKey',
        CAST(StaffKey AS VARCHAR(50)),
        CONCAT('Email=', Email, ' ActiveFlag=0 AccessLevel=', AccessLevel)
    FROM DimStaff
    WHERE IsCurrent = 1
      AND ActiveFlag = 0
      AND AccessLevel IS NOT NULL

    UNION ALL

    -- 47. StaffSchoolAccess should never include staff with NULL or excluded
    --      AccessLevel (Teacher / ProvincialAnalyst / SupportStaff / NULL).
    --      The materialization proc filters AccessLevel IS NOT NULL, but if
    --      that ever changes upstream, this catches it.
    SELECT
        'Consistency',
        'StaffSchoolAccess contains staff whose current DimStaff AccessLevel is NULL',
        'StaffSchoolAccess',
        'StaffSchoolAccessID',
        CAST(ssa.StaffSchoolAccessID AS VARCHAR(50)),
        CONCAT('StaffKey=', CAST(ssa.StaffKey AS VARCHAR(20)),
               ' (', ssa.Email, ') is in StaffSchoolAccess but DimStaff.AccessLevel is NULL')
    FROM StaffSchoolAccess ssa
    INNER JOIN DimStaff d
            ON d.StaffKey = ssa.StaffKey
    WHERE d.IsCurrent = 1
      AND d.AccessLevel IS NULL

    UNION ALL

    -- 48. FactSectionTeachers.TeacherEmail should always be lowercase (ingest
    --      lowercases at translation time; any mixed-case row indicates a bug
    --      OR a manual insert that bypassed the merge proc).
    SELECT
        'Consistency',
        'FactSectionTeachers.TeacherEmail is not lowercase',
        'FactSectionTeachers',
        'SectionTeacherID',
        CAST(SectionTeacherID AS VARCHAR(50)),
        CONCAT('TeacherEmail=', TeacherEmail, ' (expected lowercase)')
    FROM FactSectionTeachers
    WHERE TeacherEmail <> LOWER(TeacherEmail)

    UNION ALL

    -- 49. DimStaff.Email same lowercase rule.
    SELECT
        'Consistency',
        'DimStaff.Email is not lowercase',
        'DimStaff',
        'StaffKey',
        CAST(StaffKey AS VARCHAR(50)),
        CONCAT('Email=', Email, ' (expected lowercase)')
    FROM DimStaff
    WHERE Email <> LOWER(Email)

)
SELECT *
FROM AllChecks
ORDER BY CheckCategory, CheckName, KeyValue;
