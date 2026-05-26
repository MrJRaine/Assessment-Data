#requires -Version 5.1
# ============================================================================
# Excel template structure dumper
# Read-only, macros disabled. Dumps sheets, headers, sample data, formulas,
# charts, and conditional formatting rules to a markdown file.
# ============================================================================

param(
    [Parameter(Mandatory=$true)] [string]$Path,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$absPath = (Resolve-Path -LiteralPath $Path).Path
if (-not $OutputPath) {
    $OutputPath = Join-Path (Split-Path $absPath) "excel_template_structure.md"
}

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
try { $excel.AutomationSecurity = 3 } catch {}

$out = [System.Text.StringBuilder]::new()
function W($text = "") { [void]$out.AppendLine($text) }

function Get-VisibilityLabel($v) {
    switch ($v) {
        -1 { return "Visible" }
        0  { return "Hidden" }
        2  { return "VeryHidden" }
        default { return "Unknown($v)" }
    }
}

function Dump-Sheet($sheet) {
    $vis = Get-VisibilityLabel $sheet.Visible
    W ""
    W "### $($sheet.Name) -- $vis"

    $used = $null
    try { $used = $sheet.UsedRange } catch { W "- ERROR getting UsedRange: $_"; return }
    if (-not $used) { W "- (empty sheet)"; return }

    $rowCount = $used.Rows.Count
    $colCount = $used.Columns.Count
    $addr = $used.Address($false, $false)
    W "- Used range: $addr -- $rowCount rows x $colCount cols"

    W "- Headers (row 1):"
    for ($c = 1; $c -le $colCount; $c++) {
        $val = $used.Cells.Item(1, $c).Value2
        $valStr = if ($null -eq $val) { "<null>" } else { "$val" }
        W "  - Col $c`: $valStr"
    }

    $sampleRows = [Math]::Min($rowCount - 1, 5)
    if ($sampleRows -gt 0) {
        W "- Sample data (rows 2 to $($sampleRows + 1)):"
        for ($r = 2; $r -le ($sampleRows + 1); $r++) {
            $vals = @()
            for ($c = 1; $c -le $colCount; $c++) {
                $cv = $used.Cells.Item($r, $c).Value2
                $vals += if ($null -eq $cv) { "" } else { "$cv" }
            }
            W "  - Row $r`: [$($vals -join ' | ')]"
        }
    }

    $formulaSet = @{}
    $scanRows = [Math]::Min($rowCount, 10)
    for ($r = 1; $r -le $scanRows; $r++) {
        for ($c = 1; $c -le $colCount; $c++) {
            $f = $null
            try { $f = $used.Cells.Item($r, $c).Formula } catch {}
            if ($f -and "$f".StartsWith("=")) {
                $hdr = $used.Cells.Item(1, $c).Value2
                $hdrStr = if ($null -eq $hdr) { "Col$c" } else { "$hdr" }
                $formulaSet["${hdrStr}::${f}"] = $true
            }
        }
    }
    if ($formulaSet.Count -gt 0) {
        W "- Formulas (sampled from first 10 rows):"
        $shown = 0
        foreach ($k in ($formulaSet.Keys | Select-Object -First 40)) {
            W "  - $k"
            $shown++
        }
        if ($formulaSet.Count -gt 40) {
            W "  - ...and $($formulaSet.Count - 40) more distinct formula patterns"
        }
    }

    try {
        $chartObjs = $sheet.ChartObjects()
        if ($chartObjs.Count -gt 0) {
            W "- Charts ($($chartObjs.Count)):"
            foreach ($co in $chartObjs) {
                $ch = $co.Chart
                $title = ""
                try { if ($ch.HasTitle) { $title = $ch.ChartTitle.Text } } catch {}
                $src = ""
                try {
                    foreach ($s in $ch.SeriesCollection()) { $src = $s.Formula; break }
                } catch {}
                W "  - $($co.Name) (ChartType=$($ch.ChartType), Title='$title')"
                if ($src) { W "    SeriesFormula: $src" }
            }
        }
    } catch {}

    try {
        $cfCount = $used.FormatConditions.Count
        if ($cfCount -gt 0) {
            W "- Conditional formatting rules: $cfCount"
            for ($i = 1; $i -le [Math]::Min($cfCount, 25); $i++) {
                try {
                    $cf = $used.FormatConditions.Item($i)
                    $f1 = ""
                    try { $f1 = $cf.Formula1 } catch {}
                    $appliesTo = ""
                    try { $appliesTo = $cf.AppliesTo.Address } catch {}
                    $bgColor = ""
                    try { $bgColor = "$($cf.Interior.Color)" } catch {}
                    W "  - Rule $i`: Type=$($cf.Type), Formula='$f1', AppliesTo=$appliesTo, BgColor=$bgColor"
                } catch {}
            }
            if ($cfCount -gt 25) { W "  - ...and $($cfCount - 25) more CF rules" }
        }
    } catch {}

    try {
        $pts = $sheet.PivotTables()
        if ($pts.Count -gt 0) {
            W "- Pivot tables ($($pts.Count)):"
            foreach ($pt in $pts) {
                try { W "  - $($pt.Name) (SourceData=$($pt.PivotCache().SourceData))" } catch {}
            }
        }
    } catch {}
}

$wb = $null
try {
    $wb = $excel.Workbooks.Open($absPath, 0, $true)

    W "# Excel Template Structure"
    W "File: $absPath"
    W "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    W ""
    W "## Workbook"
    W "- Sheet count: $($wb.Sheets.Count)"

    try {
        $namesCount = $wb.Names.Count
        if ($namesCount -gt 0) {
            W ""
            W "## Defined Names ($namesCount)"
            foreach ($n in $wb.Names) {
                try { W "- ``$($n.Name)`` => $($n.RefersTo)" } catch {}
            }
        }
    } catch {}

    W ""
    W "## Sheets"

    foreach ($sheet in $wb.Sheets) {
        Dump-Sheet $sheet
    }

    [System.IO.File]::WriteAllText($OutputPath, $out.ToString(), [System.Text.UTF8Encoding]::new($false))
    Write-Host "Dump written to: $OutputPath" -ForegroundColor Green
}
finally {
    try { if ($wb) { $wb.Close($false) } } catch {}
    try { $excel.Quit() } catch {}
    try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null } catch {}
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
