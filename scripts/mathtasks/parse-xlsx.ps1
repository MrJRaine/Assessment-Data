param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Out)
# Read a .xlsx WITHOUT Excel/Python: a .xlsx is OOXML = a ZIP of XML parts. Unzip, resolve
# sharedStrings + sheet XML, dump each cell as <col>=<value> (and [f=formula] where present).
# XmlDocument.Load honours the XML declaration's UTF-8 encoding (Get-Content -Raw mangled accents).
Add-Type -AssemblyName System.IO.Compression.FileSystem
function LoadXml([string]$p) { $d = New-Object System.Xml.XmlDocument; $d.Load($p); $d }

$tmp  = Join-Path ([System.IO.Path]::GetTempPath()) ("xlsx_" + [guid]::NewGuid().ToString("N"))
$copy = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString("N") + ".zip")
Copy-Item -LiteralPath $Path -Destination $copy -Force       # copy first so an open-in-Excel lock doesn't block
[System.IO.Compression.ZipFile]::ExtractToDirectory($copy, $tmp)

$lines = New-Object System.Collections.Generic.List[string]

$ss = New-Object System.Collections.Generic.List[string]
$ssPath = Join-Path $tmp 'xl\sharedStrings.xml'
if (Test-Path $ssPath) { $sx = LoadXml $ssPath; foreach ($si in $sx.sst.ChildNodes) { [void]$ss.Add($si.InnerText) } }

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

foreach ($file in (Get-ChildItem (Join-Path $tmp 'xl\worksheets') -Filter *.xml | Sort-Object Name)) {
  $nm = $names[$file.Name]; if (-not $nm) { $nm = $file.Name }
  [void]$lines.Add(""); [void]$lines.Add("### SHEET: $nm  ($($file.Name))")
  $wx = LoadXml $file.FullName
  foreach ($row in $wx.worksheet.sheetData.row) {
    $cells = @()
    foreach ($c in $row.c) {
      $col = ($c.r -replace '\d','')
      $f = $null; if ($c.f) { $f = $c.f.InnerText }
      if     ($c.t -eq 's')         { $v = $ss[[int]$c.v] }
      elseif ($c.t -eq 'inlineStr') { $v = $c.is.InnerText }
      else                          { $v = [string]$c.v }
      if ($v -ne $null -and $v -ne '') { $cells += ("$col=$v" + $(if ($f) { " [f=$f]" } else { "" })) }
    }
    if ($cells.Count) { [void]$lines.Add(("r{0}: {1}" -f $row.r, ($cells -join ' | '))) }
  }
}

[System.IO.File]::WriteAllLines($Out, $lines, (New-Object System.Text.UTF8Encoding($false)))
Remove-Item -LiteralPath $copy -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
"Wrote $($lines.Count) lines to $Out"
