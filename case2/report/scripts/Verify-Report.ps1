param(
    [string]$ReportPath = (Join-Path $PSScriptRoot '..\赛题二_二维图形加速系统设计报告.md')
)

$ErrorActionPreference = 'Stop'
$reportFile = (Resolve-Path -LiteralPath $ReportPath).Path
$reportText = Get-Content -LiteralPath $reportFile -Raw -Encoding UTF8
$issues = [System.Collections.Generic.List[string]]::new()
$lines = Get-Content -LiteralPath $reportFile -Encoding UTF8

foreach ($number in 1..8) {
    $count = [regex]::Matches($reportText, "(?m)^## $number ").Count
    if ($count -ne 1) { $issues.Add("Chapter $number heading count: $count") }
}
foreach ($heading in @('摘要', '参考资料', '附录A 命令格式与控制寄存器', '附录B 工程与证据索引', '附录C 待补充材料清单')) {
    if ($reportText -notmatch ('(?m)^## ' + [regex]::Escape($heading) + '\r?$')) {
        $issues.Add("Missing heading: $heading")
    }
}

$usedIds = @([regex]::Matches($reportText, '\[(R\d+)\]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$definedIds = @([regex]::Matches($reportText, '(?m)^\[(R\d+)\] ') | ForEach-Object { $_.Groups[1].Value })
foreach ($id in $usedIds) {
    if (@($definedIds | Where-Object { $_ -eq $id }).Count -ne 1) { $issues.Add("Undefined/duplicate reference: $id") }
}
if ($definedIds.Count -ne 11) { $issues.Add("Expected 11 local source records; found $($definedIds.Count)") }

$checkedPaths = [System.Collections.Generic.List[string]]::new()
foreach ($match in [regex]::Matches($reportText, '\]\((?:<(?<path>[CD]:/[^>]+)>|(?<path>[CD]:/[^)]+))\)')) {
    $path = $match.Groups['path'].Value
    if (-not (Test-Path -LiteralPath $path)) { $issues.Add("Missing linked source: $path") }
    $checkedPaths.Add($path)
}
if ([regex]::Matches($reportText, '(?m)^```').Count % 2 -ne 0) { $issues.Add('Unbalanced code fences') }
if ([regex]::Matches($reportText, '(?m)^\$\$\r?$').Count % 2 -ne 0) { $issues.Add('Unbalanced display-math fences') }

$tableColumns = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -match '^#{1,6} ') {
        if ($i -gt 0 -and $lines[$i-1].Trim().Length -gt 0) { $issues.Add("Missing blank before heading at line $($i+1)") }
        if ($i+1 -lt $lines.Count -and $lines[$i+1].Trim().Length -gt 0) { $issues.Add("Missing blank after heading at line $($i+1)") }
    }
    if ($line -match '^\|') {
        $n = [regex]::Matches($line, '(?<!\\)\|').Count
        if ($tableColumns -eq 0) { $tableColumns = $n }
        elseif ($n -ne $tableColumns) { $issues.Add("Inconsistent table columns at line $($i+1): $n vs $tableColumns") }
    } else { $tableColumns = 0 }
}

$banned = '首先|其次|最后|此外|另外|接下来|总之|值得注意的是|需要指出的是|必须强调的是|我认为|我觉得|实验目的|回填模板|讨论提示|请用户|用户替换|写作要求|修改要求'
foreach ($match in [regex]::Matches($reportText, $banned)) { $issues.Add("Style/process wording: $($match.Value)") }
if ($reportText -match '\*\*|__|(?m)^\s*[-*+]\s+') { $issues.Add('Bold emphasis or body bullet list found') }
if ($reportText -match '<<<<<<<|>>>>>>>|\uFFFD') { $issues.Add('Conflict marker or replacement character found') }

$placeholderCount = [regex]::Matches($reportText, '【待补充[^】]*】').Count
$measurementSlots = [regex]::Matches($reportText, '待实测').Count
if ($placeholderCount -eq 0 -or $measurementSlots -eq 0) { $issues.Add('Expected unfinished-work/measurement slots are absent') }
foreach ($expected in @('2265', '647', '3680', '3840', '2384', '2134', '804', 'RGB565', '4 KiB', 'AXI4-Lite')) {
    if ($reportText.Replace(',', '') -notlike "*$expected*") { $issues.Add("Expected evidence/term absent: $expected") }
}

$evidencePath = Join-Path $PSScriptRoot '..\tables\verification-evidence.json'
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
$logDirectory = Join-Path $evidence.source_root $evidence.regression_directory
$statuses = @(Get-ChildItem -LiteralPath $logDirectory -Filter '*.status.json' -File)
if ($statuses.Count -ne 22) { $issues.Add("Regression status count differs: $($statuses.Count)") }
foreach ($file in $statuses) {
    $status = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    if ($status.state -ne 'completed' -or $status.returncode -ne 0 -or $status.worker_in_job -ne $false) {
        $issues.Add("Regression status not accepted: $($file.Name)")
    }
}
foreach ($record in $evidence.functional_records) {
    $logPath = Join-Path $logDirectory ($record.test + '_sim.log')
    $logText = Get-Content -LiteralPath $logPath -Raw
    if ($logText -notmatch 'PASS') { $issues.Add("No PASS in source: $logPath") }
}

[pscustomobject]@{
    Report = $reportFile
    NonWhitespaceCharacters = ($reportText -replace '\s', '').Length
    ChineseCharacters = [regex]::Matches($reportText, '[\u4e00-\u9fff]').Count
    SourceRecords = $definedIds.Count
    LocalLinksChecked = $checkedPaths.Count
    UnfinishedWorkSlots = $placeholderCount
    MeasurementSlots = $measurementSlots
    ExistingRegressionStatusesChecked = $statuses.Count
    Issues = $issues.Count
} | Format-List

if ($issues.Count -gt 0) {
    $issues | ForEach-Object { Write-Output "FAIL: $_" }
    exit 1
}
Write-Output 'REPORT_QA_PASS (draft with intentional unfinished-work slots; not a board-validation claim)'
