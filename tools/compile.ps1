param(
    [string]$Python = "python",
    [string]$EfinityRoot = "D:\",
    [string]$Project = "",
    [switch]$Bitstream
)
$ErrorActionPreference = 'Stop'
if (-not $Project) { $Project = Join-Path $PSScriptRoot '..\FPGA_engin' }
$Project = (Resolve-Path -LiteralPath $Project).Path
$Runner = Join-Path $EfinityRoot 'bin\efx_run.bat'
& $Python (Join-Path $PSScriptRoot 'stage_manifest.py') $Project
if ($LASTEXITCODE -ne 0) { throw 'Source staging failed' }
Push-Location -LiteralPath $Project
try {
    & $Runner Case4_Ti60 --prj -f map
    if ($LASTEXITCODE -ne 0) { throw 'Synthesis failed' }
    & $Runner Case4_Ti60 --prj -f interface
    if ($LASTEXITCODE -ne 0) { throw 'Interface generation failed' }
    & $Python (Join-Path $PSScriptRoot 'refresh_constraints.py') $Project
    if ($LASTEXITCODE -ne 0) { throw 'Constraint refresh failed' }
    $ClockPlan = & $Python (Join-Path $PSScriptRoot 'configure_1080.py') $Project --check-only --generated
    if ($LASTEXITCODE -ne 0) { throw '1080 configuration check failed' }
    $ClockPlan | Set-Content -LiteralPath (Join-Path $Project 'native1080_clock_plan.json') -Encoding utf8
    & $Runner Case4_Ti60 --prj -f pnr
    if ($LASTEXITCODE -ne 0) { throw 'Place/route failed' }
    # Efinity can return success even if timing has negative slack.
    & $Python (Join-Path $PSScriptRoot 'check_timing.py') $Project
    if ($LASTEXITCODE -ne 0) { throw 'Timing closure failed; see timing report' }
    & $Python (Join-Path $PSScriptRoot 'check_placement.py') $Project --efinity-root $EfinityRoot
    if ($LASTEXITCODE -ne 0) { throw 'Physical placement verification failed; see placement check report' }
    if ($Bitstream) {
        & $Runner Case4_Ti60 --prj -f pgm
        if ($LASTEXITCODE -ne 0) { throw 'Bitstream generation failed' }
        & $Python (Join-Path $PSScriptRoot 'validate_build.py') $Project --efinity-root $EfinityRoot
        if ($LASTEXITCODE -ne 0) { throw 'Final source, implementation or bitstream validation failed' }
    }
} finally { Pop-Location }


