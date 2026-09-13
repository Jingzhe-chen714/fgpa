param(
    [string]$PythonExe='python',
    [string]$VivadoBin='D:\vivado\vivado\Vivado\2023.1\bin',
    [switch]$Small,
    [switch]$Implement
)
# Current, authoritative acceptance entry. Every generated product stays in
# case4/build; the caller's directory and other contest projects are untouched.
$ErrorActionPreference='Stop'
$case4Root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$buildRoot=Join-Path $case4Root 'build'
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
$statusPath=Join-Path $buildRoot 'validation_status.json'
@{Status='running';Small=[bool]$Small;Implement=[bool]$Implement;Started=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8
function Invoke-ValidationPython([string]$Script,[string[]]$ScriptArgs,[string]$Log) {
    & $PythonExe -B (Join-Path $case4Root $Script) @ScriptArgs 2>&1 | Tee-Object -FilePath (Join-Path $buildRoot $Log)
    if($LASTEXITCODE -ne 0){throw "Python validation failed: $Script"}
}
try {
    Invoke-ValidationPython 'test_golden.py' @() 'golden_tests.log'
    Invoke-ValidationPython 'verify_fixed_gray.py' @('--json',(Join-Path $buildRoot 'fixed_gray_report.json')) 'fixed_gray.log'
    Invoke-ValidationPython 'scripts/generate_stream_vectors.py' @() 'vector_generation.log'
    & (Join-Path $PSScriptRoot 'run_core_fixes.ps1') -VivadoBin $VivadoBin
    & (Join-Path $PSScriptRoot 'run_stream_regression.ps1') -VivadoBin $VivadoBin -Small:$Small
    if($Implement) {
        $timingRoot=Join-Path $buildRoot 'timing_zynq'
        New-Item -ItemType Directory -Path $timingRoot -Force | Out-Null
        Push-Location $timingRoot
        try {
            & (Join-Path $VivadoBin 'vivado.bat') -mode batch -nojournal -log current.log -source (Join-Path $PSScriptRoot 'implement_zynq.tcl') -tclargs current 2>&1 | Out-File current_console.log -Encoding utf8
            if($LASTEXITCODE -ne 0){throw 'Zynq implementation failed; see build/timing_zynq/current.log'}
            Select-String -LiteralPath current.log -Pattern '^CASE4_' | ForEach-Object Line
        } finally {Pop-Location}
    }
} catch {
    @{Status='failed';Small=[bool]$Small;Implement=[bool]$Implement;Error=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8
    throw
}
@{Status='complete';Small=[bool]$Small;FullFrames=(-not $Small);ImplementationRequested=[bool]$Implement;Finished=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8
Write-Output "CASE4_VALIDATION_PASS full_frames=$(-not $Small) implementation=$([bool]$Implement)"
