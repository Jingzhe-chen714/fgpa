<##
.SYNOPSIS
  Run a bounded, boardless Efinity map for the Case-1 Ti60 resource proxy.

.DESCRIPTION
  The foreground invocation only creates a WMI-detached worker.  The worker
  copies the three tiny project files into a private %TEMP% tree, runs the
  bundled Efinity Python runner with flow=map, extracts a compact resource
  summary, and removes the private tree in finally.  No P&R, bitstream,
  simulation, GUI, Vivado or xsim process is started.
##>
[CmdletBinding()]
param(
    [switch]$Worker,
    [string]$RunId = '',
    [string]$DesignName = 'c1_ti60_resource_proxy',
    [string]$TopModule = '',
    [string]$EfinityHome = 'D:\ELS\Efinity\2026.1',
    [int]$TimeoutSeconds = 180,
    [switch]$RunPnr,
    [switch]$ProjectInPlace
)

$ErrorActionPreference = 'Stop'
$caseRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$proxyRoot = Join-Path $caseRoot 'efinity'
$logRoot = Join-Path $caseRoot 'logs\efinity_resource_runs'

if (-not $Worker) {
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        $RunId = [guid]::NewGuid().ToString('N')
    }
    if ($RunId -notmatch '^[A-Za-z0-9_-]+$') { throw 'invalid RunId' }
    if ($DesignName -notmatch '^[A-Za-z0-9_]+$') { throw 'invalid DesignName' }
    if ([string]::IsNullOrWhiteSpace($TopModule)) { $TopModule = $DesignName }
    if ($TopModule -notmatch '^[A-Za-z0-9_]+$') { throw 'invalid TopModule' }
    $statusPath = Join-Path $logRoot "$RunId\status.json"
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $pnrArg = if ($RunPnr) { ' -RunPnr' } else { '' }
    $inPlaceArg = if ($ProjectInPlace) { ' -ProjectInPlace' } else { '' }
    $cmd = "`"$ps`" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Worker -RunId $RunId -DesignName $DesignName -TopModule $TopModule -EfinityHome `"$EfinityHome`" -TimeoutSeconds $TimeoutSeconds$pnrArg$inPlaceArg"
    $workerPid = $null
    try {
        $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd; CurrentDirectory = $caseRoot }
        if ($r.ReturnValue -eq 0) { $workerPid = [int]$r.ProcessId }
    } catch {
        # CIM/WMI is often denied inside a managed desktop job.  The native
        # helper uses CreateProcess(CREATE_BREAKAWAY_FROM_JOB) and is the
        # preferred fallback; either path keeps Efinity outside this turn's
        # Windows Job object.
    }
    if ($null -eq $workerPid) {
        $helper = Join-Path $caseRoot 'scripts\start_detached_process.ps1'
        if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) { throw 'detached process helper is missing' }
        $workerPid = [int](& $helper -CommandLine $cmd -CurrentDirectory $caseRoot)
    }
    [ordered]@{ run_id = $RunId; worker_pid = $workerPid; status_path = $statusPath } | ConvertTo-Json
    exit 0
}

if ($RunId -notmatch '^[A-Za-z0-9_-]+$') { throw 'invalid RunId' }
if ($DesignName -notmatch '^[A-Za-z0-9_]+$') { throw 'invalid DesignName' }
if ([string]::IsNullOrWhiteSpace($TopModule)) { $TopModule = $DesignName }
if ($TopModule -notmatch '^[A-Za-z0-9_]+$') { throw 'invalid TopModule' }
$runRoot = Join-Path $env:TEMP "c1_efinity_resource_${DesignName}_$RunId"
$runLog = Join-Path $logRoot $RunId
$statusPath = Join-Path $runLog 'status.json'
$summaryPath = Join-Path $runLog 'summary.json'
$latestPath = Join-Path $logRoot 'latest_status.json'
$watch = [Diagnostics.Stopwatch]::StartNew()
$script:step = 'setup'
New-Item -ItemType Directory -Force -Path $runRoot, $runLog | Out-Null

function Write-Status([string]$State, [string]$Step, [int]$Code, [string]$Message, [object]$Metrics = $null) {
    $obj = [ordered]@{
        run_id = $RunId; state = $State; step = $Step; exit_code = $Code
        message = $Message; process_id = $PID
        elapsed_seconds = [math]::Round($watch.Elapsed.TotalSeconds, 3)
        log_directory = $runLog; summary_path = $summaryPath; metrics = $Metrics
    }
    $json = $obj | ConvertTo-Json -Depth 8
    $json | Set-Content -LiteralPath $statusPath -Encoding UTF8
    $json | Set-Content -LiteralPath $latestPath -Encoding UTF8
}

function Get-Tail([string]$Path, [int]$Lines = 120) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    return @(Get-Content -LiteralPath $Path -Tail $Lines -ErrorAction SilentlyContinue)
}

function Read-ResourceMetrics([string[]]$Files, [string]$TopName) {
    $all = New-Object System.Collections.Generic.List[string]
    foreach ($file in $Files) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        $item = Get-Item -LiteralPath $file
        # Reports are normally small; skip unexpectedly huge databases/logs.
        if ($item.Length -gt 16MB) { continue }
        foreach ($line in (Get-Content -LiteralPath $file -ErrorAction SilentlyContinue)) {
            if ($line -match '(?i)LE|logic element|DSP|multiplier|EBR|block ram|memory|register|resource') {
                [void]$all.Add($line.ToString())
            }
        }
    }
    $text = $all -join "`n"
    function FirstNumber([string[]]$Patterns) {
        foreach ($pattern in $Patterns) {
            $m = [regex]::Match($text, $pattern)
            if ($m.Success) { return [int](($m.Groups[1].Value -replace ',', '')) }
        }
        return $null
    }
    $primitiveLines = @($all | Where-Object { $_ -match '(?i)EFX_[A-Z0-9_]+\s*:\s*[0-9][0-9,]*' })
    $primitiveCounts = @{}
    foreach ($line in $primitiveLines) {
        $pm = [regex]::Match($line.ToString(), '(?i)\b(EFX_[A-Z0-9_]+)\s*:\s*([0-9][0-9,]*)')
        if ($pm.Success) {
            $key = $pm.Groups[1].Value.ToUpperInvariant()
            $value = [int](($pm.Groups[2].Value -replace ',', ''))
            if (-not $primitiveCounts.ContainsKey($key) -or $value -gt $primitiveCounts[$key]) { $primitiveCounts[$key] = $value }
        }
    }
    $moduleRow = $null
    $moduleRows = New-Object System.Collections.Generic.List[string]
    $moduleMetrics = [ordered]@{ ff = $null; srl = $null; adds = $null; luts = $null; comb4 = $null; rams = $null; dsp_mults = $null }
    foreach ($line in $all) {
        $row = [regex]::Match($line.ToString(), '(?im)^\s*(?:INFO\s*:\s*)?[^\s]+\s+([0-9][0-9,]*)\([0-9][0-9,]*\)\s+([0-9][0-9,]*)\([0-9][0-9,]*\)\s+([0-9][0-9,]*)\([0-9][0-9,]*\)\s+([0-9][0-9,]*)\([0-9][0-9,]*\)\s+([0-9][0-9,]*)\([0-9][0-9,]*\)\s+([0-9][0-9,]*)\([0-9][0-9,]*\)\s+([0-9][0-9,]*)\([0-9][0-9,]*\)\s*$')
        if ($row.Success -and $line.ToString() -match ([regex]::Escape($TopName) + ':' + [regex]::Escape($TopName))) {
            $moduleRow = $line.ToString()
            $keys = @('ff', 'srl', 'adds', 'luts', 'comb4', 'rams', 'dsp_mults')
            for ($ri = 0; $ri -lt $keys.Count; $ri++) {
                $moduleMetrics[$keys[$ri]] = [int](($row.Groups[$ri + 1].Value -replace ',', ''))
            }
        }
        if ($row.Success) { [void]$moduleRows.Add($line.ToString()) }
    }
    return [ordered]@{
        le = if ($null -ne $moduleMetrics.luts -and $moduleMetrics.luts -gt 0) { $moduleMetrics.luts } elseif ($primitiveCounts.ContainsKey('EFX_LUT4')) { $primitiveCounts['EFX_LUT4'] } else { FirstNumber @('(?im)\b(?:logic\s+elements?|LEs?)\b[^0-9\r\n]*([0-9][0-9,]*)', '(?im)\bLE\b\s*\|\s*([0-9][0-9,]*)') }
        registers = if ($null -ne $moduleMetrics.ff -and $moduleMetrics.ff -gt 0) { $moduleMetrics.ff } elseif ($primitiveCounts.ContainsKey('EFX_FF')) { $primitiveCounts['EFX_FF'] } else { $null }
        dsp = if ($primitiveCounts.Count -gt 0) { [int](($primitiveCounts.GetEnumerator() | Where-Object { $_.Key -match '^EFX_DSP' } | Measure-Object -Property Value -Sum).Sum) } elseif ($null -ne $moduleMetrics.dsp_mults) { $moduleMetrics.dsp_mults } else { $null }
        ebr = if ($null -ne $moduleMetrics.rams -and $moduleMetrics.rams -gt 0) { $moduleMetrics.rams } elseif ($primitiveCounts.Count -gt 0) { [int](($primitiveCounts.GetEnumerator() | Where-Object { $_.Key -match '^EFX_(?:EBR|RAM)' } | Measure-Object -Property Value -Sum).Sum) } else { $null }
        report_lines = $all.Count
        sample = @($all | Select-Object -First 300)
        primitive_lines = $primitiveLines
        primitive_counts = $primitiveCounts
        module_row = $moduleRow
        module_rows = @($moduleRows | Select-Object -First 40)
        module = $moduleMetrics
    }
}

try {
    Write-Status 'running' 'prepare' 0 'detached Efinity Ti60 map started'
    if ($ProjectInPlace) {
        foreach ($name in @("$DesignName.xml", "$DesignName.sdc")) {
            $src = Join-Path $proxyRoot $name
            if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Missing in-place project file: $src" }
        }
    } else {
        foreach ($name in @("$DesignName.v", "$DesignName.sdc", "$DesignName.xml")) {
            $src = Join-Path $proxyRoot $name
            if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Missing proxy file: $src" }
            Copy-Item -LiteralPath $src -Destination (Join-Path $runRoot $name)
        }
    }
    $outDir = Join-Path $runRoot 'out'
    $workDir = Join-Path $runRoot 'work'
    New-Item -ItemType Directory -Force -Path $outDir, $workDir | Out-Null
    $efUnix = $EfinityHome.Replace('\', '/')
    $env:EFINITY_HOME = $efUnix
    $env:EFXPT_HOME = "$efUnix/pt"
    $env:EFXPGM_HOME = "$efUnix/pgm"
    $env:EFXDBG_HOME = "$efUnix/debugger"
    $env:EFXIPM_HOME = "$efUnix/ipm"
    $env:EFXSVF_HOME = "$efUnix/debugger/svf_player"
    $env:EFXSERDESDBG_HOME = "$efUnix/debugger/serdes_debug_tool"
    $env:EFINITY_USER_DIR_INI = ((Join-Path $env:LOCALAPPDATA 'Efinity\efinity\user_dir.ini').Replace('\', '/'))
    $env:PYTHONHOME = Join-Path $EfinityHome 'python311'
    $env:PATH = ((Join-Path $EfinityHome 'python311\bin') + ';' +
                 (Join-Path $EfinityHome 'bin') + ';' +
                 (Join-Path $EfinityHome 'scripts') + ';' + $env:PATH)

    $stdoutTmp = Join-Path $runRoot 'efinity.stdout.log'
    $stderrTmp = Join-Path $runRoot 'efinity.stderr.log'
    $python = Join-Path $EfinityHome 'python311\bin\python.exe'
    $runner = Join-Path $EfinityHome 'scripts\efx_run.py'
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw "Missing Efinity Python: $python" }
    if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) { throw "Missing Efinity runner: $runner" }
    $script:step = 'efx_map'
    $args = @($runner, $DesignName, '--prj', '-f', 'map',
              '--family', 'Titanium', '--device', 'Ti60F225',
              '--output_dir', $outDir, '--work_dir', $workDir,
              '--timeout', [string]$TimeoutSeconds,
              '--map_opts', "root=$TopModule")
    # The worker itself was created with CREATE_BREAKAWAY_FROM_JOB.  Invoke
    # the bundled Python directly so it inherits that detached process; this
    # also avoids Start-Process rebuilding a Windows environment block with
    # duplicate Path/PATH entries on some managed hosts.
    $projectCwd = if ($ProjectInPlace) { $proxyRoot } else { $runRoot }
    Push-Location $projectCwd
    try {
        & $python @args 1> $stdoutTmp 2> $stderrTmp
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    $stdoutTail = Get-Tail $stdoutTmp
    $stderrTail = Get-Tail $stderrTmp
    $stdoutTail | Set-Content -LiteralPath (Join-Path $runLog 'efinity.stdout.tail.log') -Encoding UTF8
    $stderrTail | Set-Content -LiteralPath (Join-Path $runLog 'efinity.stderr.tail.log') -Encoding UTF8
    if ($exitCode -ne 0) { throw "Efinity runner exit code $exitCode" }

    $pnrExit = $null
    $pnrTail = @()
    $pnrErrTail = @()
    if ($RunPnr) {
        $script:step = 'efx_pnr'
        $pnrStdoutTmp = Join-Path $runRoot 'efinity_pnr.stdout.log'
        $pnrStderrTmp = Join-Path $runRoot 'efinity_pnr.stderr.log'
        $pnrArgs = @($runner, $DesignName, '--prj', '-f', 'pnr',
                     '--family', 'Titanium', '--device', 'Ti60F225',
                     '--output_dir', $outDir, '--work_dir', $workDir,
                     '--timeout', [string]$TimeoutSeconds)
        Push-Location $projectCwd
        try {
            & $python @pnrArgs 1> $pnrStdoutTmp 2> $pnrStderrTmp
            $pnrExit = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        $pnrTail = Get-Tail $pnrStdoutTmp
        $pnrErrTail = Get-Tail $pnrStderrTmp
        $pnrTail | Set-Content -LiteralPath (Join-Path $runLog 'efinity.pnr.stdout.tail.log') -Encoding UTF8
        $pnrErrTail | Set-Content -LiteralPath (Join-Path $runLog 'efinity.pnr.stderr.tail.log') -Encoding UTF8
        if ($pnrExit -ne 0) { throw "Efinity PNR runner exit code $pnrExit" }
    }

    $reports = @(Get-ChildItem -LiteralPath $runRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.rpt', '.log', '.xml', '.txt') })
    $metrics = Read-ResourceMetrics ($reports | Select-Object -ExpandProperty FullName) $DesignName
    if ($metrics.sample) {
        $metrics.sample | Set-Content -LiteralPath (Join-Path $runLog 'resource_lines.sample.log') -Encoding UTF8
        $metrics.Remove('sample')
    }
    if ($metrics.primitive_lines) {
        $metrics.primitive_lines | Set-Content -LiteralPath (Join-Path $runLog 'resource_primitives.log') -Encoding UTF8
        $metrics.Remove('primitive_lines')
    }
    $pnrResources = [ordered]@{
        memory_blocks_used = $null; memory_blocks_total = $null; memory_blocks_percent = $null
        dsp_blocks_used = $null; dsp_blocks_total = $null; dsp_blocks_percent = $null
    }
    foreach ($report in $reports) {
        if ($report.Length -gt 16MB) { continue }
        foreach ($line in (Get-Content -LiteralPath $report.FullName -ErrorAction SilentlyContinue)) {
            $rm = [regex]::Match($line.ToString(), '(?im)^\s*Memory Blocks:\s*([0-9]+)\s*/\s*([0-9]+)\s*\(([0-9.]+)%')
            if ($rm.Success) { $pnrResources.memory_blocks_used = [int]$rm.Groups[1].Value; $pnrResources.memory_blocks_total = [int]$rm.Groups[2].Value; $pnrResources.memory_blocks_percent = [double]$rm.Groups[3].Value }
            $rd = [regex]::Match($line.ToString(), '(?im)^\s*DSP Blocks:\s*([0-9]+)\s*/\s*([0-9]+)\s*\(([0-9.]+)%')
            if ($rd.Success) { $pnrResources.dsp_blocks_used = [int]$rd.Groups[1].Value; $pnrResources.dsp_blocks_total = [int]$rd.Groups[2].Value; $pnrResources.dsp_blocks_percent = [double]$rd.Groups[3].Value }
        }
    }
    $marker = ($DesignName.ToUpperInvariant() + '_MAP_PASS')
    $timingLines = @($reports | ForEach-Object {
        if ($_.Length -le 16MB) {
            Get-Content -LiteralPath $_.FullName -ErrorAction SilentlyContinue |
                Where-Object { $_ -match '(?i)slack|fmax|frequency|critical path|period|arrival|required|wns|tns|timing' }
        }
    } | Select-Object -First 160)
    if ($timingLines.Count -gt 0) {
        $timingLines | Set-Content -LiteralPath (Join-Path $runLog 'timing_lines.sample.log') -Encoding UTF8
    }
    $timingText = $timingLines -join "`n"
    $timing = [ordered]@{
        post_place_period_ns = $null; post_place_frequency_mhz = $null;
        final_period_ns = $null; final_frequency_mhz = $null;
        max_period_ns = $null; max_frequency_mhz = $null;
        post_place_slack_ns = $null; post_place_hold_slack_ns = $null;
        final_slack_ns = $null; final_hold_slack_ns = $null
    }
    $periods = [regex]::Matches($timingText, '(?im)Geomean max period:\s*([0-9]+(?:\.[0-9]+)?)')
    if ($periods.Count -ge 1) {
        $timing.post_place_period_ns = [double]$periods[0].Groups[1].Value
        $timing.post_place_frequency_mhz = [math]::Round(1000.0 / $timing.post_place_period_ns, 3)
        $timing.max_period_ns = $timing.post_place_period_ns
        $timing.max_frequency_mhz = $timing.post_place_frequency_mhz
    }
    if ($periods.Count -ge 2) {
        $timing.final_period_ns = [double]$periods[$periods.Count - 1].Groups[1].Value
        $timing.final_frequency_mhz = [math]::Round(1000.0 / $timing.final_period_ns, 3)
        $timing.max_period_ns = $timing.final_period_ns
        $timing.max_frequency_mhz = $timing.final_frequency_mhz
    }
    $slacks = [regex]::Matches($timingText, '(?im)Worst Negative Slack \(WNS\).*?value="([-+]?[0-9]+(?:\.[0-9]+)?) ns"')
    $holds = [regex]::Matches($timingText, '(?im)Worst Hold Slack \(WHS\).*?value="([-+]?[0-9]+(?:\.[0-9]+)?) ns"')
    if ($slacks.Count -ge 1) { $timing.post_place_slack_ns = [double]$slacks[0].Groups[1].Value }
    if ($slacks.Count -ge 2) { $timing.final_slack_ns = [double]$slacks[$slacks.Count - 1].Groups[1].Value }
    if ($holds.Count -ge 1) { $timing.post_place_hold_slack_ns = [double]$holds[0].Groups[1].Value }
    if ($holds.Count -ge 2) { $timing.final_hold_slack_ns = [double]$holds[$holds.Count - 1].Groups[1].Value }
    if ($RunPnr) { $metrics.timing = $timing; $metrics.pnr_resources = $pnrResources }
    $marker = ($DesignName.ToUpperInvariant() + $(if ($RunPnr) { '_MAP_PNR_PASS' } else { '_MAP_PASS' }))
    $summary = [ordered]@{
        run_id = $RunId; marker = $marker; state = 'complete';
        efinity_version = '2026.1.132.3.9'; family = 'Titanium';
        device = 'Ti60F225'; flow = $(if ($RunPnr) { 'map+pnr' } else { 'map' });
        pnr_exit_code = $pnrExit; timing = $timing; pnr_resources = $pnrResources; metrics = $metrics; report_file_count = $reports.Count
    }
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    $watch.Stop(); Write-Status 'complete' 'done' 0 $marker $metrics
} catch {
    $watch.Stop()
    $message = $_.Exception.Message
    $failureLines = @()
    foreach ($logFile in (Get-ChildItem -LiteralPath $runRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.log', '.out', '.rpt') })) {
        if ($logFile.Length -le 16MB) {
            $failureLines += @(Get-Content -LiteralPath $logFile.FullName -Tail 80 -ErrorAction SilentlyContinue |
                Where-Object { $_ -match '(?i)error|fail|cannot|missing|not found|undefined|unconnected' })
        }
    }
    if ($failureLines.Count -gt 0) {
        $failureLines | Select-Object -Last 120 | Set-Content -LiteralPath (Join-Path $runLog 'failure_focus.log') -Encoding UTF8
        $tail = ($failureLines | Select-Object -Last 12) -join ' | '
        $message = "$message; failure_tail=$tail"
    }
    Write-Status 'failed' $script:step 1 $message
    exit 1
} finally {
    if (Test-Path -LiteralPath $runRoot) {
        Remove-Item -LiteralPath $runRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
