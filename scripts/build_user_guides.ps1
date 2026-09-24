# TODO (0.7.0 grace-lock): document the GRACE WINDOW where appropriate — in the reading/writing/math
#   "enter data" guides (03/04/05) and the "choose a cycle" guide: after a cycle closes it stays editable
#   for a grace period (default 7 days / 168h, per-cycle configurable), shows under "Past cycles — late
#   entry (N left)", then LOCKS to read-only ("View only"); designated Literacy/Math override staff can
#   flip a locked group back on via "Override lock for this group". Add once 0.7.0 ships.
#
# Builds the v0.6.0 teacher how-to one-pagers (.docx) via Word COM, from a single
# consistent template. Regenerates docs/user-guides/v0.6.0/*.docx from the content below.
# Run:  powershell -ExecutionPolicy Bypass -File scripts\build_user_guides.ps1
# NOTE: this .ps1 is UTF-8 + BOM so the Δ ✓ ✗ → • · — characters render.

$ErrorActionPreference = 'Stop'
$OutDir = 'C:\Git-Repos\Assessment-Data\docs\user-guides\v0.6.0'
$ImgDir = Join-Path $OutDir '_source-images'

$EM='—'; $DOT='·'; $D='Δ'; $CHK='✓'; $CRS='✗'; $ARR='→'; $BUL='•'
function RGBv($r,$g,$b){ [int]$r + [int]$g*256 + [int]$b*65536 }
$cTitle = RGBv 18 64 90       # dark navy
$cHead  = RGBv 14 106 158     # teal blue
$cGrey  = RGBv 107 114 128    # slate grey
$cInk   = RGBv 33 37 41       # near-black body
$cShotBg= RGBv 238 241 244    # light grey box
$cNoteBg= RGBv 234 244 239    # light green note

# ---- content ---------------------------------------------------------------
$Docs = @(
@{ file='01-access-and-sign-in.docx'; title='Access the App and Sign In'; blocks=@(
  @{t='h';v='Purpose'}
  @{t='p';v='This guide tells you how to open The SCoR Hub. It also tells you how to sign in with your TCRCE Microsoft account.'}
  @{t='h';v='Before you start'}
  @{t='bullets';v=@('Use a supported web browser. For example, use Google Chrome, Microsoft Edge, or Firefox.','Get your TCRCE Microsoft account (Entra ID) and your Multi-Factor Authentication (MFA) app or device ready.')}
  @{t='h';v='Sign in'}
  @{t='steps';v=@('Open your web browser.','Go to https://data.tcrce.ca.','Click "Sign in" at the top right.','If your browser is already signed in, the app opens. If not, wait for the Microsoft sign-in page.','Type your TCRCE email address. Click "Next".','Type your password. Click "Sign in".','If the system asks, approve the sign-in request on your phone.','Wait for the home page. Make sure it shows "Welcome back" and your name.')}
  @{t='h';v='The home page and menu'}
  @{t='p';v='The home page shows one card for each task. Click a card to start the task. The same tasks are in the top menu.'}
  @{t='bullets';v=@('"Data Entry" - record results for a class during an open cycle.','"Reports" - view your students, charts, and each student''s history.','"Programming" - confirm which students have an IPP or Adaptations, by subject.')}
  @{t='note';v='You do not see every card or menu item. The app shows only the ones for your role. Regional analysts also see "Cycles", "Ingest", and "Maintenance".'}
  @{t='h';v='Sign out'}
  @{t='steps';v=@('Find your name at the top right.','Click "Sign out".')}
  @{t='shot';v='The SCoR Hub home page after sign-in. Show the header (top-left "The SCoR Hub"), the top menu, and the task cards.'}
)}
@{ file='02-choose-a-class-or-group.docx'; title='Choose a Class or Group'; blocks=@(
  @{t='h';v='Purpose'}
  @{t='p';v='This guide tells you how to choose the class or group you want. The same picker is used in Data Entry, Reports, and Programming.'}
  @{t='h';v='Before you start'}
  @{t='bullets';v=@('Sign in to the app. See "Access the App and Sign In".','In Data Entry, first click the cycle card for the subject. The picker opens after that.','In Reports and Programming, the picker is the first thing you see.')}
  @{t='h';v='Find your class'}
  @{t='steps';v=@('Look at "My classes". It shows the homerooms and course sections that you teach.','If you have oversight of other classes, click "All groups" to see them.','Use the "School" and "Grade" filters to make the list shorter.','Click the card for the homeroom, the course section, or the whole grade that you want.','Wait for the roster grid (Data Entry) or the report (Reports / Programming).')}
  @{t='h';v='Combine sections (optional)'}
  @{t='p';v='You can open more than one section of the SAME subject as one combined roster.'}
  @{t='steps';v=@('Select each section that you want.','Click "Combine".','The app opens all the selected sections together as one roster.')}
  @{t='note';v='You see only the classes and groups that your role allows. A teacher sees their own classes; an admin or analyst sees the classes in their school(s) or region.'}
  @{t='shot';v='The "Choose a group" picker. Show the "My classes" / "All groups" tabs, the School and Grade filters, and the group cards.'}
)}
@{ file='03-enter-reading-data.docx'; title='Enter Reading Data'; blocks=@(
  @{t='h';v='Purpose'}
  @{t='p';v='This guide tells you how to record reading levels for a class in a reading cycle.'}
  @{t='h';v='Before you start'}
  @{t='bullets';v=@('Sign in to the app. See "Access the App and Sign In".','Make sure the reading cycle is open.')}
  @{t='h';v='Open the class roster'}
  @{t='steps';v=@('Click "Data Entry" in the top menu.','Find the "Reading" section.','Click the reading cycle card for your class.','Choose a group. See "Choose a Class or Group".','Wait for the roster grid.')}
  @{t='h';v='Show a small group (optional)'}
  @{t='steps';v=@('Click "Students (N of M shown)" above the grid.','Click "Clear all".','Select the checkbox for each student that you want to show.','Click "Students" again to close the list.')}
  @{t='note';v='The app keeps your entries for hidden students. Hidden students still save.'}
  @{t='h';v='Enter and save reading levels'}
  @{t='steps';v=@('Find the student row.','In the "New level" column, open the dropdown and select the reading level.',"Look at the ""$D"" column. It shows the difference from the expected level.",'Look at the "Previous cycle" column. It shows the last recorded level.','Do the same for each student.','Click "Save N change(s)" at the bottom.','Wait for the message "Saved N".')}
  @{t='h';v='Record the same level again ("New Data")'}
  @{t='p';v='The "New Data" checkbox ticks by itself when you change a level. To record a NEW result that is the same as last time (a real second data point), tick "New Data" yourself. Save sends every ticked row.'}
  @{t='note';v='A row with no change and no tick is not sent. This is normal.'}
  @{t='shot';v='The reading roster grid. Show the "New level" and "'+$D+'" columns, the "Previous cycle" column, and the "New Data" checkbox.'}
)}
@{ file='04-enter-writing-data.docx'; title='Enter Writing Data'; blocks=@(
  @{t='h';v='Purpose'}
  @{t='p';v='This guide tells you how to record writing scores for a class in a writing cycle.'}
  @{t='h';v='Before you start'}
  @{t='bullets';v=@('Sign in to the app. See "Access the App and Sign In".','Make sure the writing cycle is open.')}
  @{t='h';v='Open the class roster'}
  @{t='steps';v=@('Click "Data Entry" in the top menu.','Find the "Writing" section.','Click the writing cycle card for your class.','Choose a group. See "Choose a Class or Group".','Wait for the roster grid.')}
  @{t='h';v='The four traits'}
  @{t='p';v='A writing result has four traits. Give a score from 1 to 4 for each trait.'}
  @{t='bullets';v=@('"Ideas"','"Org." - Organization','"Lang." - Language','"Conv." - Conventions')}
  @{t='h';v='Enter and save writing scores'}
  @{t='steps';v=@('Find the student row.','In each of the "Ideas", "Org.", "Lang.", and "Conv." columns, open the dropdown and select a score from 1 to 4.','Look at the "Avg" column. It shows the average of the scores.','Look at the "Achievement" column. It shows the band.','Do the same for each student.','Click "Save N change(s)" at the bottom.','Wait for the message "Saved N".')}
  @{t='note';v='You must give all four scores for a student, or the row is not saved. The app shows "All four traits required - not saved".'}
  @{t='h';v='Scribed conventions'}
  @{t='p';v='If someone else physically wrote for the student, set "Conv." to "SCR" (Scribed). A scribed conventions score is left out of the average.'}
  @{t='h';v='Record the same score again ("New Data")'}
  @{t='p';v='The "New Data" checkbox ticks by itself when you change a score. To record a new result that is the same as last time, tick "New Data" yourself. Save sends every ticked row.'}
  @{t='shot';v='The writing roster grid. Show the four trait columns, the "Avg" and "Achievement" columns, the "SCR" option, and the "New Data" checkbox.'}
)}
@{ file='05-enter-math-data.docx'; title='Enter Math Data'; blocks=@(
  @{t='h';v='Purpose'}
  @{t='p';v='This guide tells you how to record math results for a class. You record one result for each student and each task.'}
  @{t='h';v='Before you start'}
  @{t='bullets';v=@('Sign in to the app. See "Access the App and Sign In".','Make sure the math cycle is open.')}
  @{t='h';v='Open the task matrix'}
  @{t='steps';v=@('Click "Data Entry" in the top menu.','Find the "Math" section.','Click the math cycle card for your class.','Choose a group. See "Choose a Class or Group".','Wait for the task matrix.')}
  @{t='h';v='Read the matrix'}
  @{t='p';v='The matrix shows one ROW for each task and one COLUMN for each student. Tasks are in groups called units.'}
  @{t='bullets';v=@("A check mark ($CHK) means the student can do the task.","A cross ($CRS) means the student cannot do the task.",'"IPP" means the student has a Math Individual Program Plan for this task.','A blank cell means no result.','The "Class %" column shows how many students can do the task.','Each task can show an answer key next to it, as a marking reference. For a French Immersion class, the task and the answer key show in French.')}
  @{t='h';v='Enter a result'}
  @{t='steps';v=@('Find the task row and the student column.',"Click the cell one time to show a check mark ($CHK) for ""can do"".","Click the cell again to show a cross ($CRS) for ""cannot do"".",'Click the cell again to clear the result.','Do the same for each cell that you want to change.','Click "Save N change(s)" at the top.','Wait for the message "Saved N".')}
  @{t='note';v="For a student with a Math IPP, the cell starts at ""IPP"". The clicks move IPP $ARR $CHK $ARR $CRS $ARR clear $ARR IPP."}
  @{t='h';v='Show or hide tasks'}
  @{t='steps';v=@('Click "Edit checklist".','Clear the checkbox for each task that you want to hide.','Use "Select all" or "Clear all" to change a whole grade or unit.','Click "Done editing".')}
  @{t='note';v='To show every task again, click "Show all tasks". Click a unit header to collapse or open its tasks. The app resets these view choices at your next sign-in.'}
  @{t='shot';v='The math matrix. Show the units, the "Class %" column, a check mark and a cross, and a task answer key.'}
)}
@{ file='06-reports-class-and-cohort.docx'; title='Reports: Class and Cohort'; blocks=@(
  @{t='h';v='Purpose'}
  @{t='p';v='This guide tells you how to view your students as a group. You can filter the group, read charts, and open one student.'}
  @{t='h';v='Before you start'}
  @{t='bullets';v=@('Sign in to the app. See "Access the App and Sign In".')}
  @{t='h';v='Open Reports'}
  @{t='steps';v=@('Click "Reports" in the top menu.','Choose a group. See "Choose a Class or Group".','Click "Reading" or "Writing" to choose the subject.')}
  @{t='note';v='Reports shows Reading and Writing. Math reporting is not in Reports yet.'}
  @{t='h';v='Filter the group'}
  @{t='steps';v=@('Click "Show filters".','Set the "Grade" range with the two dropdowns.','Use the other filters to narrow the group. For example, use "Homeroom", "School", "Program", or "Achievement".','Look at the count. It shows how many students match.','Click "Reset" to clear the filters.')}
  @{t='h';v='Read the charts'}
  @{t='bullets';v=@('"Current achievement distribution" - a donut chart. The center shows how many students have a result.','"Achievement by month (last 6 months)" - a bar chart.')}
  @{t='note';v='The charts do not count students with an IPP. The charts do not count students without a result.'}
  @{t='img';v='reports-charts.png';w=6.3}
  @{t='h';v='Open one student'}
  @{t='steps';v=@('Find the student in the table.','Click the name of the student.','Wait for the student page. See "Reports: A Student".')}
  @{t='img';v='reports-cohort-table.png';w=6.0}
)}
@{ file='07-reports-a-student.docx'; title='Reports: A Student'; blocks=@(
  @{t='h';v='Purpose'}
  @{t='p';v='This guide tells you how to view the result history and the progress of one student.'}
  @{t='h';v='Before you start'}
  @{t='bullets';v=@('Sign in to the app. See "Access the App and Sign In".','Open Reports and find the student. See "Reports: Class and Cohort".')}
  @{t='h';v='Open a student'}
  @{t='steps';v=@('On the Reports table, click the name of the student.','Wait for the student page. The title is the name of the student.')}
  @{t='h';v='Read the page'}
  @{t='bullets';v=@('The line under the name shows the grade, program, school, homeroom, and IPP status.','Click "Reading" or "Writing" to change the subject.',"""Assessment history"" - a table with one row for each result (Cycle, Date, Level, $D, Achievement).",'"Reading level over time" or "Writing average over time" - a chart of the progress.')}
  @{t='img';v='reports-student-page.png';w=5.6}
  @{t='h';v='Move to another student'}
  @{t='bullets';v=@("Click ""Next $ARR"" to open the next student.","Click ""$ARR Prev"" to open the previous student.","Click ""$ARR Back to students"" to return to the group.")}
  @{t='note';v='If the student has a confirmed IPP, the app does not show an achievement band. The app tracks the student for personal progress.'}
)}
@{ file='08-programming-ipps-and-adaptations.docx'; title='Programming: IPPs and Adaptations'; blocks=@(
  @{t='h';v='Purpose'}
  @{t='p';v='This guide tells you how to confirm each student''s Individual Program Plans (IPPs) and Adaptations, by subject. The app uses this to read the data correctly. You do not create the plan in the app.'}
  @{t='h';v='About Programming'}
  @{t='p';v='PowerSchool tells the app which students have an IPP, but not the subject area. You confirm whether it applies to Reading, Writing, or Math. You also record each student''s Adaptations by subject.'}
  @{t='h';v='Before you start'}
  @{t='bullets';v=@('Sign in to the app. See "Access the App and Sign In".')}
  @{t='h';v='Open Programming'}
  @{t='steps';v=@('Click "Programming" in the top menu.','Choose a group. See "Choose a Class or Group".','Wait for the grid.')}
  @{t='h';v='Read the grid'}
  @{t='p';v='The grid shows one row for each student. There are columns for IPP and for Adaptations, across Reading, Writing, and Math.'}
  @{t='h';v='Confirm a student'}
  @{t='steps';v=@('Find the student row.','For each subject, set IPP and Adaptations to "No" or "Yes".','For a French Immersion student in grade 3 or higher, the literacy choice has four values: "No", "FLA-Only" (French), "ELA-Only" (English), or "Both".','Do the same for each student.','Click "Save".')}
  @{t='note';v='A colour cue shows how much is still left to confirm. The app does not save your choices until you click Save.'}
  @{t='shot';v='The Programming grid. Show the IPP and Adaptation columns for Reading / Writing / Math, and the "No" / "Yes" (and "FLA-Only" / "ELA-Only" / "Both") choices.'}
)}
)

# ---- render ----------------------------------------------------------------
$word = New-Object -ComObject Word.Application
$word.Visible = $false
try {
  foreach ($doc in $Docs) {
    $d = $word.Documents.Add()
    $ps = $d.PageSetup
    $ps.TopMargin=$word.InchesToPoints(0.55); $ps.BottomMargin=$word.InchesToPoints(0.55)
    $ps.LeftMargin=$word.InchesToPoints(0.7); $ps.RightMargin=$word.InchesToPoints(0.7)
    $sel = $word.Selection

    function Style($size,$bold,$color,$italic,$spAfter){
      $sel.Font.Name='Calibri'; $sel.Font.Size=[single]$size
      $sel.Font.Bold=$(if($bold){1}else{0}); $sel.Font.Italic=$(if($italic){1}else{0}); $sel.Font.Color=[int]$color
      $sel.ParagraphFormat.SpaceAfter=[single]$spAfter; $sel.ParagraphFormat.SpaceBefore=[single]0
      $sel.ParagraphFormat.LeftIndent=[single]0; $sel.ParagraphFormat.FirstLineIndent=[single]0
      $sel.ParagraphFormat.Shading.BackgroundPatternColor=[int]-16777216  # wdColorAutomatic (none)
    }

    # Title
    Style 21 $true $cTitle $false 2
    $sel.TypeText($doc.title); $sel.TypeParagraph()
    # Meta line
    Style 9 $false $cGrey $true 8
    $sel.TypeText("The SCoR Hub  $DOT  How-to guide  $DOT  v0.6.0"); $sel.TypeParagraph()

    foreach ($b in $doc.blocks) {
      switch ($b.t) {
        'h' {
          Style 12.5 $true $cHead $false 3
          $sel.ParagraphFormat.SpaceBefore=[single]6
          $sel.TypeText($b.v); $sel.TypeParagraph()
        }
        'p' {
          Style 10.5 $false $cInk $false 5
          $sel.TypeText($b.v); $sel.TypeParagraph()
        }
        'steps' {
          $n=1
          foreach ($s in $b.v) {
            Style 10.5 $false $cInk $false 3
            $sel.ParagraphFormat.LeftIndent=$word.InchesToPoints(0.3)
            $sel.ParagraphFormat.FirstLineIndent=$word.InchesToPoints(-0.3)
            $sel.TypeText(("{0}.`t{1}" -f $n,$s)); $sel.TypeParagraph()
            $n++
          }
        }
        'bullets' {
          foreach ($s in $b.v) {
            Style 10.5 $false $cInk $false 3
            $sel.ParagraphFormat.LeftIndent=$word.InchesToPoints(0.3)
            $sel.ParagraphFormat.FirstLineIndent=$word.InchesToPoints(-0.2)
            $sel.TypeText(("$BUL`t{0}" -f $s)); $sel.TypeParagraph()
          }
        }
        'note' {
          Style 10 $false $cInk $true 6
          $sel.ParagraphFormat.LeftIndent=$word.InchesToPoints(0.12)
          $sel.ParagraphFormat.Shading.BackgroundPatternColor=$cNoteBg
          $sel.Font.Italic=1
          $sel.TypeText("Note:  " + $b.v); $sel.TypeParagraph()
        }
        'shot' {
          Style 9.5 $false $cGrey $true 6
          $sel.ParagraphFormat.Shading.BackgroundPatternColor=$cShotBg
          $sel.TypeText("[ SCREENSHOT ]  " + $b.v); $sel.TypeParagraph()
        }
        'img' {
          $p = Join-Path $ImgDir $b.v
          if (Test-Path $p) {
            Style 10 $false $cInk $false 6
            $shape = $sel.InlineShapes.AddPicture($p)
            $shape.LockAspectRatio = -1
            $shape.Width = $word.InchesToPoints([double]$b.w)
            $sel.TypeParagraph()
          } else {
            Style 9.5 $false $cGrey $true 6
            $sel.TypeText("[ IMAGE MISSING: $($b.v) ]"); $sel.TypeParagraph()
          }
        }
      }
    }

    $outPath = [string](Join-Path $OutDir $doc.file)
    if (Test-Path $outPath) { Remove-Item $outPath -Force }
    $d.SaveAs2($outPath, 16)   # 16 = wdFormatDocumentDefault (.docx)
    $d.Close(0)
    Write-Host "Wrote $($doc.file)"
  }
}
finally {
  $word.Quit()
  [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
}
Write-Host "DONE. 8 guides in $OutDir"
