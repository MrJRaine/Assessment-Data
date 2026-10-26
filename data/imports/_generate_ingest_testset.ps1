# =============================================================================
# Generate the FULL synthetic ingest test set (split-grade + immersion + maintenance-trigger).
# =============================================================================
# Purpose: exercise the ingest pipeline AND the maintenance trigger end-to-end on
#          DEV with a realistic, structured population — straight vs split grades,
#          three program streams, correct course-language routing, and a teacher
#          layout that matches how the region actually staffs each tier.
#
# Output: replaces the 5 files in data/imports/{topic}/ (one file per folder — the
#         loaders union everything matching the wildcard, so exactly one file per
#         folder). Also emits sql/scripts/seed_DimCourseAssessment_dev_testset.sql
#         so course-scoped entry resolves the new synthetic course codes.
#
# FORMAT (confirmed against sql/deploy/deploy_all_dev.sql — the DEV-deployed loaders):
#   - Direct table extracts (Students/Staff/Sections/Enrollments):
#       TAB-delimited, CR-only (0x0D) line endings, UTF-8 no BOM, no quote qualifier,
#       filename AssessmentData{Topic}Export.text
#   - sqlReport (Co-Teachers):
#       comma-delimited, CRLF, UTF-8 no BOM, double-quote qualifier on comma values,
#       filename AssessmentDataCoTeacherExport.csv
#   -Format selects which shape to emit:
#     Legacy  (default) = the above dev format (TAB / .text / CR, AssessmentData* names).
#     Cutover           = live sqlReport format (comma / .csv / CRLF, Students*/Staff*/
#                         Sections*/Enrollments*/Co-Teachers* names) — matches the deployed
#                         LIVE loaders and the dev CSV loaders from deploy_dev_cutover_loaders.sql.
#   Synthetic field values are kept free of commas/quotes so comma-join needs no escaping;
#   each topic folder is cleared before writing so exactly one file per topic remains.
#
# POPULATION (per grade per stream = 30 students: 20 straight + 10 split):
#   English         : grades P,1,4,5,7,8,10,11              (240)
#   Early Immersion : grades P,1,4,5,7,8,10,11              (240)
#   Late Immersion  : 7/8 split only                        ( 20)  -> total 500
#   Splits: P/1, 4/5 (elementary), 7/8, 10/11.
#
# SUBJECTS / LANGUAGE ROUTING:
#   Math      : P-6 ONLY -> elementary grades P,1,4,5 get a Math section; 7-11 get none.
#               Immersion math is French-taught but assessed single-track (Kind=Math).
#   Literacy  : English stream -> ELA (English) all grades.
#               Early Immersion -> FLA (French) all grades, PLUS ELA (English) at 7,8,10,11.
#               Late Immersion  -> FLA (French) + ELA (English), grades 7,8.
#
# TEACHERS:
#   Elementary (P,1,4,5): one teacher per class-configuration, teaching ALL subjects
#                         (math + literacy) to that class.
#   Junior High (7,8)   : one ELA teacher + one FLA teacher for the whole tier.
#   Senior High (10,11) : one ELA teacher + one FLA teacher for the whole tier.
#   Plus one regional itinerant (multi-school grain) co-teaching one section per tier.
#   Plus one school administrator per school (Administrator RLS) and one regional
#   analyst dummy (RegionalAnalyst, multi-school) for RLS/login testing.
#
# Re-run anytime: powershell -File data/imports/_generate_ingest_testset.ps1
# NOTE: this REPLACES the small 21-row edge-case set from _generate_test_dummies.ps1
#       (only one file per folder can be ingested at a time). That generator is kept
#       in git to restore the edge-case coverage when needed.
# =============================================================================

param(
    [ValidateSet('Legacy','Cutover')]
    [string]$Format = 'Legacy'   # Legacy = dev TAB/.text (default); Cutover = live CSV/.csv Students* shape
)

$ErrorActionPreference = "Stop"

$basePath  = "c:\Git-Repos\Assessment-Data\data\imports"
$sqlPath   = "c:\Git-Repos\Assessment-Data\sql\scripts\seed_DimCourseAssessment_dev_testset.sql"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# --- format knobs (driven by -Format) ---
if ($Format -eq 'Cutover') {
    $DELIM = ','                                    # live sqlReport CSV
    $EXT   = 'csv'
    $fnStudents = 'StudentsExport.csv';   $fnStaff = 'StaffExport.csv'
    $fnSections = 'SectionsExport.csv';   $fnEnroll = 'EnrollmentsExport.csv'
    $fnCoTeach  = 'Co-TeachersExport.csv'           # must start with 'Co-Teachers' for the live wildcard
} else {
    $DELIM = "`t"                                   # legacy TAB
    $EXT   = 'text'
    $fnStudents = 'AssessmentDataStudentsExport.text';   $fnStaff = 'AssessmentDataStaffExport.text'
    $fnSections = 'AssessmentDataSectionExport.text';    $fnEnroll = 'AssessmentDataEnrollmentsExport.text'
    $fnCoTeach  = 'AssessmentDataCoTeacherExport.csv'
}

# --- fixed values ---
# Elementary = Hillcrest Academy (0079, actually elementary); Junior = Shelburne Regional High (0716, 7-8
# here by choice though it's a full 7-12 in reality); Senior = Yarmouth Consolidated Memorial High (1178).
# Flipped from the original (which had elem at the high school and JH at the elementary school).
$ELEM = '0079'; $JR = '0716'; $SR = '1178'
# Additional schools (2 of each tier): Clark's Harbour Elementary (elem), Barrington Municipal High (full
# 7-12 secondary — gives a 2nd school at every secondary band so Reading/Writing TCRCE go multi-school too).
$ELEM2 = '0511'; $SEC2 = '0167'
$TERM = '3500'                 # Year-Long (DimTerm seed) — term id is cosmetic for roster resolution
                               # (the roster TVFs match enrolment DATE overlap vs the cycle window, not term).
# Enrolment dates = the CURRENT school year, computed at generate time, so a fresh ingest always lands
# ACTIVE enrolments and NEVER needs rollforward_enrollment_dev.sql. (Sept-onward => this year; else prior.)
$syStart = if ((Get-Date).Month -ge 9) { (Get-Date).Year } else { (Get-Date).Year - 1 }
$DENR = "09/02/$syStart"; $DLEFT = "06/30/$($syStart + 1)"

foreach ($topic in @("students","staff","sections","section-teachers","enrollments")) {
    $folder = Join-Path $basePath $topic
    if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
    # Clear any prior export files so only the current-format file is present (the
    # loaders union everything matching their wildcard — stale files would duplicate).
    Get-ChildItem -Path $folder -File | Where-Object { $_.Extension -in '.text','.csv' } | Remove-Item -Force
}

function Write-FileWithCR   { param($Path,$Lines) [System.IO.File]::WriteAllText($Path, ($Lines -join "`r"),   $utf8NoBom) }
function Write-FileWithCRLF { param($Path,$Lines) [System.IO.File]::WriteAllText($Path, ($Lines -join "`r`n"), $utf8NoBom) }

# grade token -> PS Grade_Level ('0' for Primary; numeric otherwise)
function Get-GradeLevel($g) { if ($g -eq 'P') { '0' } else { $g } }

# (tier, stream) -> NS_Program code (all in DimProgram seed; ScopeBucket derives from it)
function Get-Program($tier,$stream) {
    switch ("$tier-$stream") {
        'ELEM-EN' { 'E005' } 'ELEM-EI' { 'E015' }
        'JR-EN'   { 'J005' } 'JR-EI'   { 'J015' } 'JR-LI' { 'J020' }
        'SR-EN'   { 'S005' } 'SR-EI'   { 'S015' }
    }
}

$birthYear = @{ 'P'=2020; '1'=2019; '4'=2016; '5'=2015; '7'=2013; '8'=2012; '10'=2010; '11'=2009 }

# 50 x 50 = 2500 unique (first,last) pairs — more than the whole dev population, so every student gets a
# UNIQUE name (no more 17 "Ash, Avery"s). Pairing below cycles first every student, last every 50.
$firsts = @('Avery','Blake','Casey','Devon','Emery','Finley','Gray','Harper','Indy','Jules','Kai','Lane','Marlow','Nico','Oakley','Parker','Quinn','Reese','Sage','Tatum','Uri','Vale','Wren','Xen','Yael','Zion','Ari','Bell','Cove','Dale','Eden','Flynn','Gael','Hollis','Ira','Jory','Keir','Lior','Milan','Noor','Odin','Perry','Rory','Sasha','Teo','Wynn','Xavi','Yuki','Zane','Remy')
$lasts  = @('Ash','Birch','Cedar','Dune','Elm','Frost','Glen','Hollow','Isle','Juniper','Kestrel','Larch','Moss','North','Onyx','Pike','Quill','Reed','Slate','Thorn','Rowan','Wolfe','Yarrow','Brook','Crane','Dell','Fern','Gale','Heath','Iris','Marsh','Nash','Orchard','Peak','Ridge','Shoal','Tide','Vane','Willow','Ember','Finch','Grove','Hart','Lark','Meade','Sparrow','Bramble','Clover','Dover','Quince')

# -----------------------------------------------------------------------------
# CLASS DEFINITIONS  (Sections carry an explicit teacher email; elementary uses
# the class teacher on both sections, Jr/Sr split ELA vs FLA by tier teacher.)
# -----------------------------------------------------------------------------
function Sec($subj,$code,$teacher) { @{ Subj=$subj; Code=$code; Teacher=$teacher } }

# Class builders for the ADDED schools — unique codes/labels/teacher emails via $tag/$tpfx so they don't
# collide with the base schools. Elementary: one teacher per class on both sections. Secondary: ONE ELA +
# ONE FLA teacher for the whole school, so the ELA teacher spans JH (7/8) AND SH (10/11) English — the
# cross-band-teacher test case.
function New-ElemClasses($school,$tag,$tpfx) {
    $out = @()
    foreach ($sm in @(@{St='EN';Lit='ELA'},@{St='EI';Lit='FLA'})) {
        foreach ($d in @(@{L='STR-P';C='P';G=[ordered]@{'P'=20}},@{L='STR-1';C='1';G=[ordered]@{'1'=20}},@{L='STR-4';C='4';G=[ordered]@{'4'=20}},@{L='STR-5';C='5';G=[ordered]@{'5'=20}},@{L='SPL-P1';C='P1';G=[ordered]@{'P'=10;'1'=10}},@{L='SPL-45';C='45';G=[ordered]@{'4'=10;'5'=10}})) {
            $t = "$tpfx.$($sm.St.ToLower()).$($d.C.ToLower())@tcrce.ca"
            $out += @{ Label="$($d.L)-$($sm.St)-$tag"; Tier='ELEM'; School=$school; Stream=$sm.St; Grades=$d.G; Sections=@((Sec 'MAT' "MAT-$($d.C)-$($sm.St)-$tag" $t),(Sec $sm.Lit "$($sm.Lit)-$($d.C)-$($sm.St)-$tag" $t)) }
        }
    }
    return $out
}
function New-SecClasses($school,$tag,$tpfx) {
    $ela = "$tpfx.ela@tcrce.ca"; $fla = "$tpfx.fla@tcrce.ca"
    $out = @()
    $bands = @(@{L='STR-7';C='7';T='JR';G=[ordered]@{'7'=20}},@{L='STR-8';C='8';T='JR';G=[ordered]@{'8'=20}},@{L='SPL-78';C='78';T='JR';G=[ordered]@{'7'=10;'8'=10}},@{L='STR-10';C='10';T='SR';G=[ordered]@{'10'=20}},@{L='STR-11';C='11';T='SR';G=[ordered]@{'11'=20}},@{L='SPL-1011';C='1011';T='SR';G=[ordered]@{'10'=10;'11'=10}})
    foreach ($d in $bands) { $out += @{ Label="$($d.L)-EN-$tag"; Tier=$d.T; School=$school; Stream='EN'; Grades=$d.G; Sections=@((Sec 'ELA' "ELA-$($d.C)-EN-$tag" $ela)) } }
    foreach ($d in $bands) { $out += @{ Label="$($d.L)-EI-$tag"; Tier=$d.T; School=$school; Stream='EI'; Grades=$d.G; Sections=@((Sec 'FLA' "FLA-$($d.C)-EI-$tag" $fla),(Sec 'ELA' "ELA-$($d.C)-EI-$tag" $ela)) } }
    $out += @{ Label="SPL-78-LI-$tag"; Tier='JR'; School=$school; Stream='LI'; Grades=[ordered]@{'7'=10;'8'=10}; Sections=@((Sec 'FLA' "FLA-78-LI-$tag" $fla),(Sec 'ELA' "ELA-78-LI-$tag" $ela)) }
    return $out
}

$classes = @(
    # ---- Elementary English (school 0716): 1 teacher/class, Math + ELA ----
    @{ Label='STR-P-EN';  Tier='ELEM'; School=$ELEM; Stream='EN'; Grades=[ordered]@{'P'=20};        Sections=@((Sec 'MAT' 'MAT-P-EN' 'teach.elem.en.p@tcrce.ca'),  (Sec 'ELA' 'ELA-P-EN' 'teach.elem.en.p@tcrce.ca')) }
    @{ Label='STR-1-EN';  Tier='ELEM'; School=$ELEM; Stream='EN'; Grades=[ordered]@{'1'=20};        Sections=@((Sec 'MAT' 'MAT-1-EN' 'teach.elem.en.1@tcrce.ca'),  (Sec 'ELA' 'ELA-1-EN' 'teach.elem.en.1@tcrce.ca')) }
    @{ Label='STR-4-EN';  Tier='ELEM'; School=$ELEM; Stream='EN'; Grades=[ordered]@{'4'=20};        Sections=@((Sec 'MAT' 'MAT-4-EN' 'teach.elem.en.4@tcrce.ca'),  (Sec 'ELA' 'ELA-4-EN' 'teach.elem.en.4@tcrce.ca')) }
    @{ Label='STR-5-EN';  Tier='ELEM'; School=$ELEM; Stream='EN'; Grades=[ordered]@{'5'=20};        Sections=@((Sec 'MAT' 'MAT-5-EN' 'teach.elem.en.5@tcrce.ca'),  (Sec 'ELA' 'ELA-5-EN' 'teach.elem.en.5@tcrce.ca')) }
    @{ Label='SPL-P1-EN'; Tier='ELEM'; School=$ELEM; Stream='EN'; Grades=[ordered]@{'P'=10;'1'=10}; Sections=@((Sec 'MAT' 'MAT-P1-EN' 'teach.elem.en.p1@tcrce.ca'),(Sec 'ELA' 'ELA-P1-EN' 'teach.elem.en.p1@tcrce.ca')) }
    @{ Label='SPL-45-EN'; Tier='ELEM'; School=$ELEM; Stream='EN'; Grades=[ordered]@{'4'=10;'5'=10}; Sections=@((Sec 'MAT' 'MAT-45-EN' 'teach.elem.en.45@tcrce.ca'),(Sec 'ELA' 'ELA-45-EN' 'teach.elem.en.45@tcrce.ca')) }

    # ---- Elementary Early Immersion (0716): Math (French) + FLA ----
    @{ Label='STR-P-EI';  Tier='ELEM'; School=$ELEM; Stream='EI'; Grades=[ordered]@{'P'=20};        Sections=@((Sec 'MAT' 'MAT-P-EI' 'teach.elem.ei.p@tcrce.ca'),  (Sec 'FLA' 'FLA-P-EI' 'teach.elem.ei.p@tcrce.ca')) }
    @{ Label='STR-1-EI';  Tier='ELEM'; School=$ELEM; Stream='EI'; Grades=[ordered]@{'1'=20};        Sections=@((Sec 'MAT' 'MAT-1-EI' 'teach.elem.ei.1@tcrce.ca'),  (Sec 'FLA' 'FLA-1-EI' 'teach.elem.ei.1@tcrce.ca')) }
    @{ Label='STR-4-EI';  Tier='ELEM'; School=$ELEM; Stream='EI'; Grades=[ordered]@{'4'=20};        Sections=@((Sec 'MAT' 'MAT-4-EI' 'teach.elem.ei.4@tcrce.ca'),  (Sec 'FLA' 'FLA-4-EI' 'teach.elem.ei.4@tcrce.ca')) }
    @{ Label='STR-5-EI';  Tier='ELEM'; School=$ELEM; Stream='EI'; Grades=[ordered]@{'5'=20};        Sections=@((Sec 'MAT' 'MAT-5-EI' 'teach.elem.ei.5@tcrce.ca'),  (Sec 'FLA' 'FLA-5-EI' 'teach.elem.ei.5@tcrce.ca')) }
    @{ Label='SPL-P1-EI'; Tier='ELEM'; School=$ELEM; Stream='EI'; Grades=[ordered]@{'P'=10;'1'=10}; Sections=@((Sec 'MAT' 'MAT-P1-EI' 'teach.elem.ei.p1@tcrce.ca'),(Sec 'FLA' 'FLA-P1-EI' 'teach.elem.ei.p1@tcrce.ca')) }
    @{ Label='SPL-45-EI'; Tier='ELEM'; School=$ELEM; Stream='EI'; Grades=[ordered]@{'4'=10;'5'=10}; Sections=@((Sec 'MAT' 'MAT-45-EI' 'teach.elem.ei.45@tcrce.ca'),(Sec 'FLA' 'FLA-45-EI' 'teach.elem.ei.45@tcrce.ca')) }

    # ---- Junior High English (school 0079): ELA only, no math ----
    @{ Label='STR-7-EN';  Tier='JR'; School=$JR; Stream='EN'; Grades=[ordered]@{'7'=20};        Sections=@((Sec 'ELA' 'ELA-7-EN'  'teach.jr.ela@tcrce.ca')) }
    @{ Label='STR-8-EN';  Tier='JR'; School=$JR; Stream='EN'; Grades=[ordered]@{'8'=20};        Sections=@((Sec 'ELA' 'ELA-8-EN'  'teach.jr.ela@tcrce.ca')) }
    @{ Label='SPL-78-EN'; Tier='JR'; School=$JR; Stream='EN'; Grades=[ordered]@{'7'=10;'8'=10}; Sections=@((Sec 'ELA' 'ELA-78-EN' 'teach.jr.ela@tcrce.ca')) }

    # ---- Junior High Early Immersion (0079): FLA + ELA (English writing) ----
    @{ Label='STR-7-EI';  Tier='JR'; School=$JR; Stream='EI'; Grades=[ordered]@{'7'=20};        Sections=@((Sec 'FLA' 'FLA-7-EI'  'teach.jr.fla@tcrce.ca'),(Sec 'ELA' 'ELA-7-EI'  'teach.jr.ela@tcrce.ca')) }
    @{ Label='STR-8-EI';  Tier='JR'; School=$JR; Stream='EI'; Grades=[ordered]@{'8'=20};        Sections=@((Sec 'FLA' 'FLA-8-EI'  'teach.jr.fla@tcrce.ca'),(Sec 'ELA' 'ELA-8-EI'  'teach.jr.ela@tcrce.ca')) }
    @{ Label='SPL-78-EI'; Tier='JR'; School=$JR; Stream='EI'; Grades=[ordered]@{'7'=10;'8'=10}; Sections=@((Sec 'FLA' 'FLA-78-EI' 'teach.jr.fla@tcrce.ca'),(Sec 'ELA' 'ELA-78-EI' 'teach.jr.ela@tcrce.ca')) }

    # ---- Junior High Late Immersion (0079): 7/8 split only, FLA + ELA ----
    @{ Label='SPL-78-LI'; Tier='JR'; School=$JR; Stream='LI'; Grades=[ordered]@{'7'=10;'8'=10}; Sections=@((Sec 'FLA' 'FLA-78-LI' 'teach.jr.fla@tcrce.ca'),(Sec 'ELA' 'ELA-78-LI' 'teach.jr.ela@tcrce.ca')) }

    # ---- Senior High English (school 1178): ELA only, no math ----
    @{ Label='STR-10-EN';   Tier='SR'; School=$SR; Stream='EN'; Grades=[ordered]@{'10'=20};          Sections=@((Sec 'ELA' 'ELA-10-EN'   'teach.sr.ela@tcrce.ca')) }
    @{ Label='STR-11-EN';   Tier='SR'; School=$SR; Stream='EN'; Grades=[ordered]@{'11'=20};          Sections=@((Sec 'ELA' 'ELA-11-EN'   'teach.sr.ela@tcrce.ca')) }
    @{ Label='SPL-1011-EN'; Tier='SR'; School=$SR; Stream='EN'; Grades=[ordered]@{'10'=10;'11'=10};  Sections=@((Sec 'ELA' 'ELA-1011-EN' 'teach.sr.ela@tcrce.ca')) }

    # ---- Senior High Early Immersion (1178): FLA + ELA (English writing) ----
    @{ Label='STR-10-EI';   Tier='SR'; School=$SR; Stream='EI'; Grades=[ordered]@{'10'=20};          Sections=@((Sec 'FLA' 'FLA-10-EI'   'teach.sr.fla@tcrce.ca'),(Sec 'ELA' 'ELA-10-EI'   'teach.sr.ela@tcrce.ca')) }
    @{ Label='STR-11-EI';   Tier='SR'; School=$SR; Stream='EI'; Grades=[ordered]@{'11'=20};          Sections=@((Sec 'FLA' 'FLA-11-EI'   'teach.sr.fla@tcrce.ca'),(Sec 'ELA' 'ELA-11-EI'   'teach.sr.ela@tcrce.ca')) }
    @{ Label='SPL-1011-EI'; Tier='SR'; School=$SR; Stream='EI'; Grades=[ordered]@{'10'=10;'11'=10};  Sections=@((Sec 'FLA' 'FLA-1011-EI' 'teach.sr.fla@tcrce.ca'),(Sec 'ELA' 'ELA-1011-EI' 'teach.sr.ela@tcrce.ca')) }
)
# Add the two extra schools (2 of each tier): CHES elementary + BMHS full 7-12 secondary.
$classes = $classes + (New-ElemClasses $ELEM2 'CHES' 'teach.ches') + (New-SecClasses $SEC2 'BMHS' 'teach.bmhs')

# course_name (human label) from subject + code
function Course-Name($subj,$code) {
    $kind = switch ($subj) { 'MAT' { 'Math' } 'ELA' { 'English Language Arts' } 'FLA' { 'Francais (immersion)' } }
    "$kind $code"
}

# -----------------------------------------------------------------------------
# Pass 1: assign SectionIDs + build the Sections export
# -----------------------------------------------------------------------------
$sectionId = 9200000
$sectionRows = @()
$codeToSection = @{}    # code -> SectionID (for co-teacher rows)
$courseMap = [ordered]@{}   # code -> subj (for the DimCourseAssessment seed)

foreach ($c in $classes) {
    $count = 0; foreach ($v in $c.Grades.Values) { $count += $v }
    foreach ($s in $c.Sections) {
        $sectionId++
        $s['ID'] = $sectionId
        $codeToSection[$s.Code] = $sectionId
        if (-not $courseMap.Contains($s.Code)) { $courseMap[$s.Code] = $s.Subj }
        $max = $count + 6
        $sectionRows += @($s.ID, $c.School, $TERM, $s.Code, '01', (Course-Name $s.Subj $s.Code), $count, $max, $s.Teacher) -join $DELIM
    }
}

# -----------------------------------------------------------------------------
# Pass 2: students + enrollments
# -----------------------------------------------------------------------------
$studentNum  = 9200000000
$studentDcid = 920000
$enrollId    = 72000000
$i = 0
$studentRows = @()
$enrollRows  = @()

foreach ($c in $classes) {
    $prog = Get-Program $c.Tier $c.Stream
    foreach ($g in $c.Grades.Keys) {
        $n = $c.Grades[$g]
        for ($k = 0; $k -lt $n; $k++) {
            $studentNum++; $studentDcid++
            $first  = $firsts[$i % $firsts.Count]
            $last   = $lasts[[math]::Floor($i / $firsts.Count) % $lasts.Count]  # unique pair: first cycles each student, last every 50
            $middle = if ($i % 4 -eq 0) { $firsts[($i * 3) % $firsts.Count] } else { '' }
            $gl     = Get-GradeLevel $g
            $by     = $birthYear[$g]
            $dob    = '{0:D2}/{1:D2}/{2}' -f (($i % 12) + 1), (($i % 28) + 1), $by
            $gender = @('M','F','X')[$i % 3]
            $afr    = if ($i % 12 -eq 5) { 'Yes' } else { '' }
            $abo    = if ($i % 9 -eq 2) { '1' } elseif ($i % 15 -eq 7) { '2' } else { '' }
            $ipp    = if ($i % 10 -eq 0) { 'Y' } else { 'N' }
            $adap   = if ($i % 8 -eq 3) { 'Y' } else { 'N' }

            $studentRows += @($studentNum, $studentDcid, $first, $middle, $last, $c.School, $gl, $prog, $c.Label, $gender, $dob, $afr, $abo, $ipp, $adap, '0') -join $DELIM

            foreach ($s in $c.Sections) {
                $enrollId++
                $enrollRows += @($studentNum, $s.ID, $DENR, $DLEFT, $enrollId) -join $DELIM
            }
            $i++
        }
    }
}

# -----------------------------------------------------------------------------
# Staff (16 teachers, Group 47 = Teacher) + 1 regional itinerant (Group 32, multi-school)
# -----------------------------------------------------------------------------
$staffId = 82000
$staffRows = @()
$elemTeachers = @(
    @('teach.elem.en.p@tcrce.ca','Pat','Willow',$ELEM),  @('teach.elem.en.1@tcrce.ca','Robin','Sorrel',$ELEM),
    @('teach.elem.en.4@tcrce.ca','Sam','Tamarack',$ELEM),@('teach.elem.en.5@tcrce.ca','Jamie','Aspen',$ELEM),
    @('teach.elem.en.p1@tcrce.ca','Alex','Cedar',$ELEM), @('teach.elem.en.45@tcrce.ca','Morgan','Hazel',$ELEM),
    @('teach.elem.ei.p@tcrce.ca','Remy','Bouleau',$ELEM),@('teach.elem.ei.1@tcrce.ca','Noa','Erable',$ELEM),
    @('teach.elem.ei.4@tcrce.ca','Charlie','Sapin',$ELEM),@('teach.elem.ei.5@tcrce.ca','Frankie','Chene',$ELEM),
    @('teach.elem.ei.p1@tcrce.ca','Sacha','Ormeau',$ELEM),@('teach.elem.ei.45@tcrce.ca','Louis','Tilleul',$ELEM)
)
$tierTeachers = @(
    @('teach.jr.ela@tcrce.ca','Dana','Ashford',$JR), @('teach.jr.fla@tcrce.ca','Yves','Lemieux',$JR),
    @('teach.sr.ela@tcrce.ca','Terry','Blackwood',$SR),@('teach.sr.fla@tcrce.ca','Chantal','Dubois',$SR)
)
foreach ($t in ($elemTeachers + $tierTeachers)) {
    $staffId++
    $staffRows += @($t[0], $t[1], $t[2], 'Teacher', $t[3], $t[3], '', '47', $staffId) -join $DELIM
}
# Teachers for the ADDED schools (CHES/BMHS), Group 47 — derived from their section teacher emails so
# every referenced teacher exists (names generated; the BMHS ELA teacher is the cross-band 7-12 case).
$addedTeachers = [ordered]@{}
foreach ($c in $classes) { if ($c.School -eq $ELEM2 -or $c.School -eq $SEC2) { foreach ($s in $c.Sections) { if (-not $addedTeachers.Contains($s.Teacher)) { $addedTeachers[$s.Teacher] = $c.School } } } }
$ti = 0
foreach ($em in $addedTeachers.Keys) {
    $staffId++
    $staffRows += @($em, $firsts[(30 + $ti) % $firsts.Count], $lasts[(33 + $ti) % $lasts.Count], 'Teacher', $addedTeachers[$em], $addedTeachers[$em], '', '47', $staffId) -join $DELIM
    $ti++
}
# Regional itinerant — same person, one row per school (multi-row grain test)
$itinEmail = 'itinerant.region@tcrce.ca'
$canChange = "$ELEM;$JR;$SR"
foreach ($sch in @($ELEM,$JR,$SR)) {
    $staffId++
    $staffRows += @($itinEmail, 'Sky', 'Rivard', 'APSEA Itinerant', '', $sch, $canChange, '32', $staffId) -join $DELIM
}

# School administrators — one per school (Group 33 = Principal/VP -> Administrator; school-level RLS)
$adminNames = @(@('Reed','Marchand'), @('Quinn','Delacroix'), @('Sol','Beaumont'), @('Wren','Hartley'), @('Lior','Beaudry'))
$adminSchools = @($ELEM, $JR, $SR, $ELEM2, $SEC2)
for ($a = 0; $a -lt $adminSchools.Count; $a++) {
    $staffId++
    $sch = $adminSchools[$a]
    $staffRows += @("principal.$sch@tcrce.ca", $adminNames[$a][0], $adminNames[$a][1], 'Principal', $sch, $sch, '', '33', $staffId) -join $DELIM
}
# Regional analyst dummy (Group 41 -> RegionalAnalyst; multi-school over ALL 5 test schools)
$allSchools = "$ELEM;$JR;$SR;$ELEM2;$SEC2"
$staffId++
$staffRows += @('analyst.region@tcrce.ca', 'Rue', 'Ellery', 'Board Director', $ELEM, $ELEM, $allSchools, '41', $staffId) -join $DELIM
# Project lead's own account, as a region-wide RegionalAnalyst, so they can sign in and test on dev as themselves.
$staffId++
$staffRows += @('jeffrey.raine@tcrce.ca', 'Jeffrey', 'Raine', 'Board Director', $ELEM, $ELEM, $allSchools, '41', $staffId) -join $DELIM

# -----------------------------------------------------------------------------
# Co-Teachers (sqlReport: comma-delimited, CRLF, quote the "Last, First" name)
# Itinerant supports one section per tier.
# -----------------------------------------------------------------------------
$coTargets = @(
    @{ School="Test School $ELEM"; Course='MAT-P1-EN';   SectionID=$codeToSection['MAT-P1-EN'] },
    @{ School="Test School $JR";   Course='FLA-78-LI';   SectionID=$codeToSection['FLA-78-LI'] },
    @{ School="Test School $SR";   Course='FLA-1011-EI'; SectionID=$codeToSection['FLA-1011-EI'] }
)
$coTeacherRows = @()
foreach ($ct in $coTargets) {
    $coTeacherRows += ('{0},{1},{2},01,"{3}",{4},Support,{5}' -f $ct.School, $TERM, $ct.Course, 'Rivard, Sky', $itinEmail, $ct.SectionID)
}

# -----------------------------------------------------------------------------
# Write the 5 export files
# -----------------------------------------------------------------------------
$studentHeader   = @('Student_Number','ID','First_Name','Middle_Name','Last_Name','SchoolID','Grade_Level','NS_Program','Home_Room','Gender','DOB','NS_AssigndIdentity_African','NS_aboriginal','CurrentIPP','CurrentAdap','Enroll_Status') -join $DELIM
$staffHeader     = @('Email_Addr','First_Name','Last_Name','Title','HomeSchoolID','SchoolID','CanChangeSchool','Group','ID') -join $DELIM
$sectionHeader   = @('ID','SchoolID','TermID','Course_Number','Section_Number','[2]course_name','No_of_students','MaxEnrollment','[5]Email_Addr') -join $DELIM
$enrollHeader    = @('[1]Student_Number','SectionID','DateEnrolled','DateLeft','ID') -join $DELIM
$coTeacherHeader = 'School,TermID,Course,Section,Teacher,Email,Role,SectionID'

# Direct extracts: CR-only in Legacy, CRLF in Cutover. Co-Teachers always CRLF.
$writeDirect = if ($Format -eq 'Cutover') { 'Write-FileWithCRLF' } else { 'Write-FileWithCR' }
& $writeDirect -Path "$basePath\students\$fnStudents"        -Lines (@($studentHeader) + $studentRows)
& $writeDirect -Path "$basePath\staff\$fnStaff"             -Lines (@($staffHeader)   + $staffRows)
& $writeDirect -Path "$basePath\sections\$fnSections"       -Lines (@($sectionHeader) + $sectionRows)
& $writeDirect -Path "$basePath\enrollments\$fnEnroll"      -Lines (@($enrollHeader)  + $enrollRows)
Write-FileWithCRLF -Path "$basePath\section-teachers\$fnCoTeach" -Lines (@($coTeacherHeader) + $coTeacherRows)

# -----------------------------------------------------------------------------
# Companion: DimCourseAssessment dev seed for the new synthetic course codes
# -----------------------------------------------------------------------------
$seedLines = @()
$seedLines += '/*******************************************************************************'
$seedLines += ' * Script: seed_DimCourseAssessment_dev_testset.sql   (DEV ONLY)'
$seedLines += ' * Purpose: Course-scoped entry mapping for the synthetic ingest TEST SET'
$seedLines += ' *          (generated by data/imports/_generate_ingest_testset.ps1). Every'
$seedLines += ' *          MAT-* -> Math (Language NULL); ELA-* -> English Literacy;'
$seedLines += ' *          FLA-* -> French Literacy. Idempotent: clears then re-seeds.'
$seedLines += ' *          Run on DEV after ingesting the test set so entry resolves courses.'
$seedLines += ' * Region: Canada East (PIIDPA compliant)'
$seedLines += ' ******************************************************************************/'
$seedLines += ''
$seedLines += 'DELETE FROM DimCourseAssessment;'
$seedLines += ''
$seedLines += 'INSERT INTO DimCourseAssessment (CourseCode, Language, Kind, ActiveFlag, Notes, LastUpdated) VALUES'
$vals = @()
foreach ($code in $courseMap.Keys) {
    switch ($courseMap[$code]) {
        'MAT' { $lang = 'NULL';      $kind = 'Math';     $note = 'testset (Math)' }
        'ELA' { $lang = "'English'"; $kind = 'Literacy'; $note = 'testset (ELA)'  }
        'FLA' { $lang = "'French'";  $kind = 'Literacy'; $note = 'testset (FLA)'  }
    }
    $vals += ("    ('{0}', {1}, '{2}', 1, '{3}', GETDATE())" -f $code, $lang, $kind, $note)
}
$seedLines += ($vals -join ",`r`n") + ';'
$seedLines += ''
$seedLines += 'SELECT Language, Kind, COUNT(*) AS Courses FROM DimCourseAssessment GROUP BY Language, Kind ORDER BY Kind, Language;'
[System.IO.File]::WriteAllText($sqlPath, ($seedLines -join "`r`n"), $utf8NoBom)

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
"Generated ingest test set [Format=$Format]:"
"  students     : {0} rows" -f $studentRows.Count
"  staff        : {0} rows ({1} base + {2} added-school teachers + itinerant x3 + {3} principals + 2 analysts incl. project lead)" -f $staffRows.Count, ($elemTeachers.Count + $tierTeachers.Count), $addedTeachers.Count, $adminSchools.Count
"  schools      : {0} ({1} elementary + {2} secondary)" -f 5, 2, 3
"  sections     : {0} rows" -f $sectionRows.Count
"  enrollments  : {0} rows" -f $enrollRows.Count
"  co-teachers  : {0} rows" -f $coTeacherRows.Count
"  course codes : {0} -> $sqlPath" -f $courseMap.Count
