# =============================================================================
# Generate cross-referenced synthetic test dummies for Step 8 merge proc dev.
# =============================================================================
# Output: 5 files in data/imports/{topic}/, replacing the previous dummies.
# Format matches PS production export quirks discovered 2026-04-29:
#   - Direct table extracts (Students/Staff/Sections/Enrollments):
#       TAB-delimited, CR-only line endings, UTF-8 no BOM, no quote qualifier.
#   - sqlReport (Co-Teachers):
#       comma-delimited, CRLF line endings, UTF-8 no BOM, double-quote qualifier
#       on values containing commas.
#
# Cross-reference integrity:
#   - All Enrollment.StudentNumber  -> Student.Student_Number
#   - All Enrollment.SectionID      -> Section.ID
#   - All Section.[5]Email_Addr     -> Staff.Email_Addr
#   - All CoTeacher.SectionID       -> Section.ID
#   - All CoTeacher.Email           -> Staff.Email_Addr
#   - All SchoolIDs                 -> DimSchool seed (real TCRCE 4-digit codes)
#   - All NS_Programs               -> DimProgram seed
#   - All TermIDs                   -> DimTerm seed (2025-2026 = 3500/3501/3502)
#   - All Group codes               -> DimRole seed
#
# Edge cases covered (deliberately):
#   - Grades:        0 (Primary), -1 (Pre-Primary), 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
#   - Genders:       M, F, X
#   - EnrollStatus:  0 (Active) and -1 (Pre-Enrolled) — production PS Students
#                    export is filtered to Enroll_Status IN (0, -1) upstream, so
#                    values 2 (Inactive) and 3 (Graduated) never appear in real
#                    exports. Pre-enrolled cases include both a future StartDate
#                    (Beta — not yet visible to teacher) and a past StartDate
#                    (Omicron — visible to teacher via vw_TeacherStudents date
#                    gate, before PS has flipped the status). Filter broadened
#                    2026-05-01 from Enroll_Status = 0 only.
#   - SelfIDAfrican: "Yes" and empty (no "No" — matches PS reality)
#   - SelfIDIndigenous: "1", "2", empty
#   - CurrentIPP / CurrentAdap: "Y", "N"
#   - Programs:     FI (E015/J015/J020/S015/S115) + non-FI (P005/E005/J005/E025/S005) for filter test
#   - MiddleName: populated and empty
#   - Homeroom: populated and empty (Grade 12 graduate, Pre-Primary)
#   - Multi-school staff: APSEA itinerant person × 4 schools (4 rows, same email)
#   - Itinerant staff: HomeSchoolID empty
#   - District-tier sentinel: HomeSchoolID = '0', SchoolID = '0' (DoE staff)
#   - Every active RoleCode bucket:
#       Teacher (47, 48, 32), SpecialistTeacher (12), Administrator (33),
#       RegionalAnalyst (10), ProvincialAnalyst (9), SupportStaff (49)
#     (Group 32 = APSEA Itinerant reclassified from SpecialistTeacher to
#      Teacher on 2026-05-01.)
#   - Term mix: Year-Long (3500), S1 (3501), S2 (3502)
#   - Enrollment DateLeft: term-end auto-fill (most), early-exit (Xi),
#     and one truly-empty DateLeft (Pi at S2 — testing the NULL code path)
#   - Co-teacher arrangements: Counsellor co-teaching, APSEA itinerant supporting
#
# Re-run anytime: pwsh -File data/imports/_generate_test_dummies.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

$basePath  = "c:\Git-Repos\Assessment-Data\data\imports"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Ensure topic subfolders exist (so this script works on a fresh clone)
foreach ($topic in @("students","staff","sections","section-teachers","enrollments")) {
    $folder = Join-Path $basePath $topic
    if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
}

function Write-FileWithCR {
    param([string]$Path, [string[]]$Lines)
    $content = $Lines -join "`r"
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

function Write-FileWithCRLF {
    param([string]$Path, [string[]]$Lines)
    $content = $Lines -join "`r`n"
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

# -----------------------------------------------------------------------------
# 1. STUDENTS  (20 rows — 18 Active + 2 Pre-Enrolled, matching production
#               filter Enroll_Status IN (0, -1))
# -----------------------------------------------------------------------------
$studentHeader = "Student_Number`tID`tFirst_Name`tMiddle_Name`tLast_Name`tSchoolID`tGrade_Level`tNS_Program`tHome_Room`tGender`tDOB`tNS_AssigndIdentity_African`tNS_aboriginal`tCurrentIPP`tCurrentAdap`tEnroll_Status"

$studentRows = @(
    "9100000001`t90001`tAlpha`tOne`tTest`t0716`t0`tE015`tP-Sample`tM`t09/01/2020`t`t`tN`tN`t0",
    "9100000003`t90003`tGamma`tThree`tDemo`t0167`t1`tE015`t1A`tX`t06/15/2019`tYes`t`tY`tN`t0",
    "9100000004`t90004`tDelta`tFour`tTest`t0167`t5`tE015`t5A`tM`t09/15/2014`t`t1`tN`tY`t0",
    "9100000005`t90005`tEpsilon`tFive`tSample`t0079`t7`tJ015`t7B`tF`t04/22/2012`tYes`t2`tY`tY`t0",
    "9100000006`t90006`tZeta`tSix`tDemo`t0079`t9`tJ020`t9C`tM`t11/30/2010`t`t`tN`tN`t0",
    "9100000007`t90007`tEta`tSeven`tTest`t1178`t10`tS015`t10A`tF`t02/14/2009`t`t1`tY`tY`t0",
    "9100000008`t90008`tTheta`tEight`tSample`t1178`t11`tS115`t11B`tM`t08/19/2008`tYes`t`tN`tY`t0",
    "9100000009`t90009`tIota`tNine`tDemo`t0981`t12`tS015`t12A`tF`t03/05/2007`t`t2`tN`tN`t0",
    "9100000010`t90010`tKappa`tTen`tTest`t0981`t12`tS005`t12B`tX`t05/22/2007`t`t`tN`tN`t0",
    "9100000011`t90011`tLambda`t`tSample`t0716`t3`tE015`t3C`tM`t11/03/2017`tYes`t1`tY`tN`t0",
    "9100000012`t90012`tMu`t`tDemo`t0716`t6`tE005`t6A`tF`t07/08/2014`t`t`tN`tN`t0",
    "9100000013`t90013`tNu`tEleven`tTest`t0167`t8`tJ005`t8B`tM`t12/01/2011`t`t`tN`tY`t0",
    "9100000014`t90014`tXi`tTwelve`tSample`t0079`t4`tE015`t4A`tF`t06/30/2015`tYes`t1`tY`tN`t0",
    "9100000016`t90016`tPi`tFourteen`tTest`t1178`t9`tJ015`t9A`tF`t09/22/2010`t`t2`tY`tY`t0",
    "9100000017`t90017`tRho`tFifteen`tSample`t0981`t7`tE025`t7C`tM`t10/05/2012`t`t`tN`tN`t0",
    "9100000018`t90018`tSigma`tSixteen`tDemo`t0716`t2`tE015`t2B`tX`t04/12/2018`tYes`t1`tN`tN`t0",
    "9100000019`t90019`tTau`t`tTest`t0167`t4`tJ015`t4D`tF`t11/19/2015`t`t`tY`tN`t0",
    "9100000020`t90020`tUpsilon`tSeventeen`tSample`t1178`t11`tS005`t11A`tM`t06/14/2008`t`t1`tN`tY`t0",
    # Pre-Enrolled (-1) — Beta has FUTURE StartDate, not yet visible on teacher roster
    "9100000002`t90002`tBeta`t`tDemo`t0716`t0`tE015`tP-Sample`tF`t08/22/2020`t`t`tN`tN`t-1",
    # Pre-Enrolled (-1) — Omicron has PAST StartDate, VISIBLE on teacher roster via date gate
    "9100000015`t90015`tOmicron`tFifteen`tTest`t0167`t1`tE015`t1A`tM`t05/30/2019`tYes`t2`tN`tN`t-1"
)

Write-FileWithCR -Path "$basePath\students\AssessmentDataStudentsExport.text" `
                 -Lines (@($studentHeader) + $studentRows)

# -----------------------------------------------------------------------------
# 2. STAFF  (14 rows = 10 unique people; APSEA itinerant has 4 rows)
# -----------------------------------------------------------------------------
$staffHeader = "Email_Addr`tFirst_Name`tLast_Name`tTitle`tHomeSchoolID`tSchoolID`tCanChangeSchool`tGroup`tID"

$staffRows = @(
    # Single-school classroom teachers (one per school, RoleCode = Teacher)
    "classroom.teacher1@tcrce.ca`tAurora`tMaple`tTeacher`t0716`t0716`t`t47`t80001",
    "classroom.teacher2@tcrce.ca`tBryce`tBirch`tTeacher`t0167`t0167`t`t48`t80002",
    "classroom.teacher3@tcrce.ca`tCedar`tPine`tTeacher`t0079`t0079`t`t47`t80003",
    "classroom.teacher4@tcrce.ca`tDaphne`tOak`tTeacher`t1178`t1178`t`t47`t80004",
    "classroom.teacher5@tcrce.ca`tElder`tSpruce`tTeacher`t0981`t0981`t`t47`t80005",
    # School Principal (RoleCode = Administrator)
    "principal.test@tcrce.ca`tForest`tWalnut`tPrincipal`t0167`t0167`t`t33`t80010",
    # Counsellor (RoleCode = SpecialistTeacher)
    "counsellor.test@tcrce.ca`tGlade`tHazel`tCounsellor`t0716`t0716`t`t12`t80020",
    # APSEA Itinerant — same person, 4 school assignments (multi-row grain test)
    # HomeSchoolID empty (itinerant), CanChangeSchool same on every row
    "apsea.itinerant@tcrce.ca`tHeather`tRose`tAPSEA Itinerant`t`t0716`t0079;0167;0716;1178`t32`t80030",
    "apsea.itinerant@tcrce.ca`tHeather`tRose`tAPSEA Itinerant`t`t0079`t0079;0167;0716;1178`t32`t80031",
    "apsea.itinerant@tcrce.ca`tHeather`tRose`tAPSEA Itinerant`t`t0167`t0079;0167;0716;1178`t32`t80032",
    "apsea.itinerant@tcrce.ca`tHeather`tRose`tAPSEA Itinerant`t`t1178`t0079;0167;0716;1178`t32`t80033",
    # Custodian (RoleCode = SupportStaff — should NOT appear in vw_StaffSchoolAccess)
    "support.test@tcrce.ca`tIris`tSunset`tCustodian`t0716`t0716`t`t49`t80040",
    # Board-level director (RoleCode = RegionalAnalyst, multi-school via CanChangeSchool)
    "board.admin@tcrce.ca`tJasper`tStone`tBoard Director`t0167`t0167`t0079;0167;0716;0981;1178`t10`t80050",
    # DoE rep (RoleCode = ProvincialAnalyst — district-tier sentinel '0' on HomeSchoolID and SchoolID)
    "province.test@novascotia.ca`tKlee`tMountain`tDoE Rep`t0`t0`t0;0079;0167;0716;0981;1178`t9`t80060"
)

Write-FileWithCR -Path "$basePath\staff\AssessmentDataStaffExport.text" `
                 -Lines (@($staffHeader) + $staffRows)

# -----------------------------------------------------------------------------
# 3. SECTIONS  (10 rows)
# -----------------------------------------------------------------------------
$sectionHeader = "ID`tSchoolID`tTermID`tCourse_Number`tSection_Number`t[2]course_name`tNo_of_students`tMaxEnrollment`t[5]Email_Addr"

$sectionRows = @(
    "9000001`t0716`t3500`tMTH-K-FI`t01`tMathématiques Maternelle`t18`t22`tclassroom.teacher1@tcrce.ca",
    "9000002`t0716`t3500`tLET-K-FI`t01`tLettres Maternelle`t18`t22`tclassroom.teacher1@tcrce.ca",
    "9000003`t0167`t3500`tMTH-1-FI`t01`tMathématiques 1ère`t20`t24`tclassroom.teacher2@tcrce.ca",
    "9000004`t0167`t3500`tFRA-1-FI`t01`tFrançais 1ère`t20`t24`tclassroom.teacher2@tcrce.ca",
    "9000005`t0079`t3500`tSCI-7-FI`t01`tSciences 7e`t22`t30`tclassroom.teacher3@tcrce.ca",
    "9000006`t0079`t3501`tHIS-9-FI`t01`tHistoire 9e (S1)`t28`t32`tclassroom.teacher3@tcrce.ca",
    "9000007`t1178`t3501`tMTH-10-FI`t01`tMathématiques 10 (S1)`t25`t32`tclassroom.teacher4@tcrce.ca",
    "9000008`t1178`t3502`tPHY-11-FI`t01`tPhysique 11 (S2)`t18`t32`tclassroom.teacher4@tcrce.ca",
    "9000009`t0981`t3500`tLIT-12-FI`t01`tLittérature 12`t15`t32`tclassroom.teacher5@tcrce.ca",
    "9000010`t0716`t3500`tHRM-EL-FI`t01`tHomeroom FI`t20`t30`tclassroom.teacher1@tcrce.ca"
)

Write-FileWithCR -Path "$basePath\sections\AssessmentDataSectionExport.text" `
                 -Lines (@($sectionHeader) + $sectionRows)

# -----------------------------------------------------------------------------
# 4. CO-TEACHERS  (sqlReport — comma-delimited, CRLF, double-quoted as needed)
# -----------------------------------------------------------------------------
$coTeacherHeader = "School,TermID,Course,Section,Teacher,Email,Role,SectionID"

$coTeacherRows = @(
    'Test School 0167,3500,MTH-1-FI,01,"Hazel, Glade",counsellor.test@tcrce.ca,Co-teacher,9000003',
    'Test School 0079,3500,SCI-7-FI,01,"Rose, Heather",apsea.itinerant@tcrce.ca,Support,9000005',
    'Test School 1178,3501,MTH-10-FI,01,"Rose, Heather",apsea.itinerant@tcrce.ca,Support,9000007',
    'Test School 0716,3500,LET-K-FI,01,"Hazel, Glade",counsellor.test@tcrce.ca,Co-teacher,9000002'
)

Write-FileWithCRLF -Path "$basePath\section-teachers\AssessmentDataCoTeacherExport.csv" `
                   -Lines (@($coTeacherHeader) + $coTeacherRows)

# -----------------------------------------------------------------------------
# 5. ENROLLMENTS  (40 rows: 34 standard + 2 edge cases + 4 pre-enrolled)
# -----------------------------------------------------------------------------
# Date conventions per term:
#   Year-Long (3500): DateEnrolled=09/02/2025, DateLeft=06/30/2026 (year end)
#   Semester 1 (3501): DateEnrolled=09/02/2025, DateLeft=01/30/2026 (S1 end)
#   Semester 2 (3502): DateEnrolled=02/02/2026, DateLeft=06/30/2026 (S2/year end)
#
# Edge cases:
#   - Xi (#9100000014) at section 9000005: DateLeft=11/15/2025 (early exit, < term end).
#     Xi is Active overall — students can drop one course without becoming inactive.
#   - Pi (#9100000016) at section 9000008 (S2): DateLeft empty (testing NULL code path)
#   - Beta (#9100000002, EnrollStatus=-1) at sections 9000001/9000002 (year-long):
#     DateEnrolled=05/15/2026 (FUTURE — should NOT appear on teacher roster yet)
#   - Omicron (#9100000015, EnrollStatus=-1) at sections 9000003/9000004 (year-long):
#     DateEnrolled=04/15/2026 (PAST — SHOULD appear on teacher roster via date gate)

$enrollmentHeader = "[1]Student_Number`tSectionID`tDateEnrolled`tDateLeft`tID"

$enrollmentRows = @(
    # School 0716 — Alpha, Beta, Lambda, Mu, Sigma in {9000001 Math K, 9000002 Lett K, 9000010 HRM} (Year-Long)
    "9100000001`t9000001`t09/02/2025`t06/30/2026`t70000001",
    "9100000001`t9000002`t09/02/2025`t06/30/2026`t70000002",
    "9100000001`t9000010`t09/02/2025`t06/30/2026`t70000003",
    "9100000011`t9000001`t09/02/2025`t06/30/2026`t70000005",
    "9100000011`t9000002`t09/02/2025`t06/30/2026`t70000006",
    "9100000011`t9000010`t09/02/2025`t06/30/2026`t70000007",
    "9100000012`t9000001`t09/02/2025`t06/30/2026`t70000008",
    "9100000012`t9000002`t09/02/2025`t06/30/2026`t70000009",
    "9100000012`t9000010`t09/02/2025`t06/30/2026`t70000010",
    "9100000018`t9000001`t09/02/2025`t06/30/2026`t70000011",
    "9100000018`t9000002`t09/02/2025`t06/30/2026`t70000012",
    "9100000018`t9000010`t09/02/2025`t06/30/2026`t70000013",
    # School 0167 — Gamma, Delta, Nu, Tau in {9000003 MTH-1, 9000004 FRA-1} (Year-Long)
    "9100000003`t9000003`t09/02/2025`t06/30/2026`t70000014",
    "9100000003`t9000004`t09/02/2025`t06/30/2026`t70000015",
    "9100000004`t9000003`t09/02/2025`t06/30/2026`t70000016",
    "9100000004`t9000004`t09/02/2025`t06/30/2026`t70000017",
    "9100000013`t9000003`t09/02/2025`t06/30/2026`t70000018",
    "9100000013`t9000004`t09/02/2025`t06/30/2026`t70000019",
    "9100000019`t9000003`t09/02/2025`t06/30/2026`t70000020",
    "9100000019`t9000004`t09/02/2025`t06/30/2026`t70000021",
    # School 0079 — Epsilon, Zeta in {9000005 SCI-7 Year-Long, 9000006 HIS-9 S1}; Xi early exit at 9000005
    "9100000005`t9000005`t09/02/2025`t06/30/2026`t70000022",
    "9100000005`t9000006`t09/02/2025`t01/30/2026`t70000023",   # S1 ends 01/30/2026
    "9100000006`t9000005`t09/02/2025`t06/30/2026`t70000024",
    "9100000006`t9000006`t09/02/2025`t01/30/2026`t70000025",
    "9100000014`t9000005`t09/02/2025`t11/15/2025`t70000026",   # Xi — EARLY EXIT from this course (< term end); student remains Active
    # School 1178 — Eta, Theta, Pi, Upsilon in {9000007 MTH-10 S1, 9000008 PHY-11 S2}
    "9100000007`t9000007`t09/02/2025`t01/30/2026`t70000027",
    "9100000007`t9000008`t02/02/2026`t06/30/2026`t70000028",
    "9100000008`t9000007`t09/02/2025`t01/30/2026`t70000029",
    "9100000008`t9000008`t02/02/2026`t06/30/2026`t70000030",
    "9100000016`t9000007`t09/02/2025`t01/30/2026`t70000031",
    "9100000016`t9000008`t02/02/2026`t`t70000032",             # Pi — DateLeft EMPTY (testing NULL path)
    "9100000020`t9000007`t09/02/2025`t01/30/2026`t70000033",
    "9100000020`t9000008`t02/02/2026`t06/30/2026`t70000034",
    # School 0981 — Iota, Kappa, Rho in {9000009 LIT-12 Year-Long}
    "9100000009`t9000009`t09/02/2025`t06/30/2026`t70000035",
    "9100000010`t9000009`t09/02/2025`t06/30/2026`t70000036",
    "9100000017`t9000009`t09/02/2025`t06/30/2026`t70000037",
    # Pre-Enrolled — Beta (future StartDate) at school 0716, sections 9000001/9000002
    "9100000002`t9000001`t05/15/2026`t06/30/2026`t70000038",   # Beta — FUTURE start (not yet visible)
    "9100000002`t9000002`t05/15/2026`t06/30/2026`t70000039",
    # Pre-Enrolled — Omicron (past StartDate) at school 0167, sections 9000003/9000004
    "9100000015`t9000003`t04/15/2026`t06/30/2026`t70000040",   # Omicron — PAST start (visible via date gate)
    "9100000015`t9000004`t04/15/2026`t06/30/2026`t70000041"
)

Write-FileWithCR -Path "$basePath\enrollments\AssessmentDataEnrollmentsExport.text" `
                 -Lines (@($enrollmentHeader) + $enrollmentRows)

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
"Generated synthetic test dummies:"
foreach ($p in @(
    "students\AssessmentDataStudentsExport.text",
    "staff\AssessmentDataStaffExport.text",
    "sections\AssessmentDataSectionExport.text",
    "section-teachers\AssessmentDataCoTeacherExport.csv",
    "enrollments\AssessmentDataEnrollmentsExport.text"
)) {
    $full = "$basePath\$p"
    $bytes = [System.IO.File]::ReadAllBytes($full)
    $crlf = 0; $cr = 0; $lf = 0
    for ($i = 0; $i -lt $bytes.Length - 1; $i++) {
        if ($bytes[$i] -eq 0x0D -and $bytes[$i+1] -eq 0x0A) { $crlf++; $i++ }
        elseif ($bytes[$i] -eq 0x0D) { $cr++ }
        elseif ($bytes[$i] -eq 0x0A) { $lf++ }
    }
    "  {0,-55}  {1,7} bytes   CRLF={2}  CR={3}  LF={4}" -f $p, $bytes.Length, $crlf, $cr, $lf
}
