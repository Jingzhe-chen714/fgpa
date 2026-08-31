param(
    [string]$ReportRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$reportPath = Join-Path $ReportRoot '赛题四_系统设计与验证报告.md'
$reportText = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
$reportLines = Get-Content -LiteralPath $reportPath -Encoding UTF8
$problems = [System.Collections.Generic.List[string]]::new()

$parts = @('front_matter.md', 'chapters/01_requirements.md', 'chapters/02_architecture.md',
    'chapters/03_algorithms.md', 'chapters/04_rtl.md', 'chapters/05_verification.md',
    'chapters/06_integration.md', 'chapters/07_conclusion.md', 'back_matter.md')
$expectedText = ($parts | ForEach-Object {
    (Get-Content -LiteralPath (Join-Path $ReportRoot $_) -Raw -Encoding UTF8).TrimEnd() -replace "`r`n", "`n"
}) -join "`n`n"
if (($reportText.TrimEnd() -replace "`r`n", "`n") -cne $expectedText) {
    $problems.Add('Merged report differs from accepted source pieces.')
}
if (@($reportLines | Where-Object { $_ -match '^# ' }).Count -ne 1) {
    $problems.Add('Expected exactly one main title.')
}
$chapterNumbers = @($reportLines | Where-Object { $_ -match '^## [1-7] ' } |
    ForEach-Object { [regex]::Match($_, '^## ([1-7]) ').Groups[1].Value })
if (($chapterNumbers -join ',') -ne '1,2,3,4,5,6,7') {
    $problems.Add('Expected seven chapters in order.')
}

$linkPattern = '!?\[[^\]]*\]\((?:<(?<angle>[^>]+)>|(?<plain>[^)\s]+))\)'
$allLinks = [regex]::Matches($reportText, $linkPattern)
foreach ($link in $allLinks) {
    $target = $link.Groups['angle'].Value
    if (-not $target) { $target = $link.Groups['plain'].Value }
    if ($target -match '^[A-Za-z]:[/\\]' -and -not (Test-Path -LiteralPath $target)) {
        $problems.Add("Missing local link: $target")
    }
}
foreach ($sourceId in 1..9) {
    if ($reportText -notmatch "(?m)^\[$sourceId\] ") {
        $problems.Add("Missing reference entry [$sourceId].")
    }
}

$codeOpen = $false
$mathOpen = $false
$tableColumns = 0
$tableCount = 0
for ($lineIndex = 0; $lineIndex -lt $reportLines.Count; $lineIndex++) {
    $line = $reportLines[$lineIndex]
    if ($line -match '^```') { $codeOpen = -not $codeOpen; continue }
    if ($codeOpen) { continue }
    if ($line -eq '$$') { $mathOpen = -not $mathOpen; continue }
    if ($mathOpen) { continue }
    if ($line -match '^\|') {
        $columns = [regex]::Matches($line, '(?<!\\)\|').Count - 1
        if ($tableColumns -eq 0) { $tableColumns = $columns; $tableCount++ }
        elseif ($columns -ne $tableColumns) { $problems.Add("Table column mismatch at line $($lineIndex + 1).") }
    } else { $tableColumns = 0 }
    if ($line -match '^#{1,6} ' -and $lineIndex + 1 -lt $reportLines.Count -and
        -not [string]::IsNullOrWhiteSpace($reportLines[$lineIndex + 1])) {
        $problems.Add("Missing blank after heading at line $($lineIndex + 1).")
    }
}
if ($codeOpen -or $mathOpen) { $problems.Add('Unclosed code or display-math fence.') }
$equationTags = @([regex]::Matches($reportText, '\\tag\{(3-[1-6])\}') |
    ForEach-Object { $_.Groups[1].Value })
if (($equationTags -join ',') -ne '3-1,3-2,3-3,3-4,3-5,3-6') {
    $problems.Add('Equation numbering is incomplete or duplicated.')
}

$simulationLogs = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'tb_*.log' -File |
    Where-Object { $_.Name -notlike '*_elab.log' })
if ($simulationLogs.Count -ne 12) { $problems.Add('Expected twelve simulator result logs.') }
foreach ($simulationLog in $simulationLogs) {
    $logText = Get-Content -LiteralPath $simulationLog.FullName -Raw
    if ($logText -notmatch 'PASS' -or $logText -match '(?im)^\s*(ERROR|FATAL)\b') {
        $problems.Add("Simulator log requires review: $($simulationLog.Name)")
    }
}

Write-Output "Report: $reportPath"
Write-Output "Characters: $($reportText.Length); chapters: $($chapterNumbers.Count); linked targets: $($allLinks.Count); tables: $tableCount"
Write-Output "Images: $([regex]::Matches($reportText, '!\[').Count); pending markers: $([regex]::Matches($reportText, '【待完成').Count)"
Write-Output "Equations: $($equationTags.Count); simulator PASS logs: $($simulationLogs.Count)"
if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Output "FAIL: $_" }
    exit 1
}
Write-Output 'REPORT ARTIFACT CHECK PASS'

