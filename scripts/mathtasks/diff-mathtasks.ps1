param(
  [Parameter(Mandatory)][string[]]$Old,   # old per-grade CSV paths (as received)
  [Parameter(Mandatory)][string]$New      # new combined CSV path
)
# Differential between the previously-loaded math task bank and the new one.
# Normalizes old AssessmentMonth 10 -> 9 first (old files predate the dim fix) so the
# natural key (GradeCode, AssessmentMonth, UnitName, QuestionNumber) aligns and we see
# TRUE content changes, not month-relabel noise.
$ErrorActionPreference = 'Stop'
$cmp = 'UnitOrder','DisplayOrder','OutcomeCode','TaskDescriptionEN','TaskDescriptionFR','AnswerKey','AnswerKeyFR','ActiveFlag'
function NK($r){ "$($r.GradeCode)|$($r.AssessmentMonth)|$($r.UnitName)|$($r.QuestionNumber)" }

$oldRows = @()
foreach ($f in $Old) {
  $rows = Import-Csv -Path $f
  foreach ($r in $rows) { if ($r.AssessmentMonth -eq '10') { $r.AssessmentMonth = '9' } }
  $oldRows += $rows
}
$newRows = Import-Csv -Path $New

$oldH = @{}; foreach ($r in $oldRows) { $oldH[(NK $r)] = $r }
$newH = @{}; foreach ($r in $newRows) { $newH[(NK $r)] = $r }

$added   = New-Object System.Collections.Generic.List[string]
$removed = New-Object System.Collections.Generic.List[string]
$changed = New-Object System.Collections.Generic.List[string]

foreach ($k in $newH.Keys) { if (-not $oldH.ContainsKey($k)) { [void]$added.Add($k) } }
foreach ($k in $oldH.Keys) { if (-not $newH.ContainsKey($k)) { [void]$removed.Add($k) } }
foreach ($k in $newH.Keys) {
  if ($oldH.ContainsKey($k)) {
    $o = $oldH[$k]; $n = $newH[$k]
    $diffs = @()
    foreach ($c in $cmp) { if ([string]$o.$c -ne [string]$n.$c) { $diffs += $c } }
    if ($diffs.Count) { [void]$changed.Add("$k  :: " + ($diffs -join ', ')) }
  }
}

"OLD rows (normalized): $($oldRows.Count)   NEW rows: $($newRows.Count)"
""
"== ADDED (new NK, not in old) : $($added.Count) =="
$added | Sort-Object | ForEach-Object { "  + $_" }
""
"== REMOVED (in old, gone from new) : $($removed.Count) =="
$removed | Sort-Object | ForEach-Object { "  - $_" }
""
"== CHANGED (same NK, field(s) differ) : $($changed.Count) =="
$changed | Sort-Object | ForEach-Object { "  ~ $_" }
""
"-- changed-field frequency --"
$fieldHits = @{}
foreach ($line in $changed) { foreach ($c in $cmp) { if ($line -match "\b$c\b") { $fieldHits[$c] = 1 + ($fieldHits[$c] | ForEach-Object {$_}) } } }
foreach ($c in $cmp) { if ($fieldHits.ContainsKey($c)) { "  {0,-18} {1}" -f $c, $fieldHits[$c] } }
