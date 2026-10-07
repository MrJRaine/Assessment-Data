param(
  [Parameter(Mandatory)][string]$Path,   # source .xlsx
  [Parameter(Mandatory)][string]$OutCsv  # target CSV (load-ready)
)
# Transform the math team's workbook -> load-ready MathTasks CSV for usp_LoadMathTasks.
# Reads the .xlsx directly (OOXML = zip of XML). XmlDocument.Load honours UTF-8 (French accents).
# Target 12 cols (Stg_MathTask order): GradeCode, AssessmentMonth, UnitName, UnitOrder,
#   QuestionNumber, DisplayOrder, OutcomeCode, TaskDescriptionEN, TaskDescriptionFR,
#   AnswerKey, AnswerKeyFR, ActiveFlag.
# Transforms: AssessmentMonth 10 -> 9 (fall cycle is September; team authors October);
#   UnitName = "Unit " + Unit#; UnitOrder = Unit#; descriptions/keys whitespace-collapsed.
# COPY INTO config matched: comma delimiter, double-quote qualifier, header row (FIRSTROW=2 skips it).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
function LoadXml([string]$p){ $d = New-Object System.Xml.XmlDocument; $d.Load($p); $d }
function Clean($s){
  # Only neutralize CSV-breaking chars (newlines/tabs) + trim. PRESERVE internal spacing
  # so the load matches the previously-authored bank (collapsing double-spaces churns ~70
  # existing rows for nothing).
  if ($null -eq $s) { return '' }
  $s = [string]$s
  $s = $s -replace '[\r\n\t]+',' '
  $s.Trim()
}
# Strip a TRAILING outcome-code parenthetical, e.g. " (N01.01)" or " (N010.01)." — the code
# lives in its own OutcomeCode column and was never in the team's sheet (per project convention).
# Keeps any trailing period and leaves legit mid-text parentheticals alone (anchored to end).
function StripCode($s){ ((Clean $s) -replace '\s*\([A-Za-z]{1,2}\d{2,3}\.\d{2}\)(\.?)\s*$','$1').Trim() }
function Q($s){ '"' + ((Clean $s) -replace '"','""') + '"' }
function QDesc($s){ '"' + ((StripCode $s) -replace '"','""') + '"' }

$tmp  = Join-Path ([System.IO.Path]::GetTempPath()) ("xlsx_" + [guid]::NewGuid().ToString("N"))
$copy = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString("N") + ".zip")
Copy-Item -LiteralPath $Path -Destination $copy -Force
[System.IO.Compression.ZipFile]::ExtractToDirectory($copy, $tmp)

# shared strings
$ss = New-Object System.Collections.Generic.List[string]
$ssPath = Join-Path $tmp 'xl\sharedStrings.xml'
if (Test-Path $ssPath) { $sx = LoadXml $ssPath; foreach ($si in $sx.sst.ChildNodes) { [void]$ss.Add($si.InnerText) } }

# sheet file -> sheet name
$names = @{}
$wb  = LoadXml (Join-Path $tmp 'xl\workbook.xml')
$rel = LoadXml (Join-Path $tmp 'xl\_rels\workbook.xml.rels')
$relMap = @{}
foreach ($r in $rel.Relationships.Relationship) { $relMap[$r.Id] = $r.Target }
foreach ($s in $wb.workbook.sheets.sheet) {
  $rid = $null
  foreach ($a in $s.Attributes) { if ($a.LocalName -eq 'id') { $rid = $a.Value } }
  if ($rid -and $relMap[$rid]) { $names[(Split-Path $relMap[$rid] -Leaf)] = $s.name }
}

function RowCells($row){
  $h = @{}
  foreach ($c in $row.c) {
    $col = ($c.r -replace '\d','')
    if     ($c.t -eq 's')         { $v = $ss[[int]$c.v] }
    elseif ($c.t -eq 'inlineStr') { $v = $c.is.InnerText }
    else                          { $v = [string]$c.v }
    $h[$col] = $v
  }
  $h
}

$header = 'GradeCode,AssessmentMonth,UnitName,UnitOrder,QuestionNumber,DisplayOrder,OutcomeCode,TaskDescriptionEN,TaskDescriptionFR,AnswerKey,AnswerKeyFR,ActiveFlag'
$out = New-Object System.Collections.Generic.List[string]
[void]$out.Add($header)

$total = 0; $remap = 0
$perGM = [ordered]@{}                 # "grade|month(final)" -> count
$warnings = New-Object System.Collections.Generic.List[string]

foreach ($file in (Get-ChildItem (Join-Path $tmp 'xl\worksheets') -Filter *.xml | Sort-Object Name)) {
  $nm = $names[$file.Name]; if (-not $nm) { $nm = $file.Name }
  $wx = LoadXml $file.FullName
  $rows = @($wx.worksheet.sheetData.row)

  # locate header row (the one containing 'ActiveFlag' + 'Grade') and build name->letter map
  $colmap = $null
  foreach ($row in $rows) {
    $h = RowCells $row
    $vals = $h.Values | ForEach-Object { Clean $_ }
    if (($vals -contains 'ActiveFlag') -and ($vals -contains 'Grade')) {
      $colmap = @{}
      foreach ($k in $h.Keys) { $colmap[(Clean $h[$k])] = $k }
      $headerRowNum = [int]($row.r)
      break
    }
  }
  if (-not $colmap) { [void]$warnings.Add("Sheet '$nm': no header row found - skipped"); continue }

  function ColVal($h,$name){ $L = $colmap[$name]; if ($L) { $h[$L] } else { $null } }

  foreach ($row in $rows) {
    if ([int]($row.r) -le $headerRowNum) { continue }
    $h = RowCells $row
    $grade = Clean (ColVal $h 'Grade')
    if ($grade -eq '') { continue }   # blank/spacer row

    $monthRaw = Clean (ColVal $h 'Month')
    $monthInt = 0; [void][int]::TryParse($monthRaw, [ref]$monthInt)
    $month = $monthInt
    if ($monthInt -eq 10) { $month = 9; $remap++ }  # fall cycle is Sept(9); team authors Oct(10)

    $unitNum   = Clean (ColVal $h 'Unit#')
    $unitName  = if ($unitNum -ne '') { "Unit $unitNum" } else { '' }

    $fields = @(
      (Q $grade),
      (Q $month),
      (Q $unitName),
      (Q $unitNum),
      (Q (ColVal $h 'QuestionNumber')),
      (Q (ColVal $h 'DisplayOrder')),
      (Q (ColVal $h 'PerformanceIndicator Number')),
      (QDesc (ColVal $h 'TaskDescriptionEN')),
      (QDesc (ColVal $h 'TaskDescriptionFR')),
      (Q (ColVal $h 'AnswerKeyEN')),
      (Q (ColVal $h 'AnswerKeyFR')),
      (Q (ColVal $h 'ActiveFlag'))
    )
    [void]$out.Add(($fields -join ','))
    $total++
    $key = "$grade|$month"
    if ($perGM.Contains($key)) { $perGM[$key] = $perGM[$key] + 1 } else { $perGM[$key] = 1 }
  }
}

[System.IO.File]::WriteAllLines($OutCsv, $out, (New-Object System.Text.UTF8Encoding($false)))
Remove-Item -LiteralPath $copy -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

"Wrote $total data rows (+1 header) to $OutCsv"
"Rows remapped month 10 -> 9: $remap"
""
"Per grade+month (final month):"
foreach ($k in ($perGM.Keys | Sort-Object { ($_ -split '\|')[0] }, { [int](($_ -split '\|')[1]) })) {
  "  {0,-6} {1}" -f $k, $perGM[$k]
}
if ($warnings.Count) { ""; "WARNINGS:"; $warnings | ForEach-Object { "  $_" } }
