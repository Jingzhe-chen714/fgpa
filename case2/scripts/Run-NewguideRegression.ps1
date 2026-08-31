param(
    [string]$PythonPath = 'C:\Users\30982\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe',
    [string]$VivadoBin = 'D:\vivado\vivado\Vivado\2023.1\bin',
    [string]$RunName = ('xsim_newguide_' + (Get-Date -Format 'yyyyMMdd_HHmmss')),
    [int]$StageTimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
if ($RunName -notmatch '^[A-Za-z0-9_-]+$') { throw 'RunName must be a simple directory name.' }
$case2Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDir = Join-Path (Join-Path $case2Root 'tb') $RunName
if (Test-Path -LiteralPath $runDir) { throw "Refusing to reuse run directory: $runDir" }
New-Item -ItemType Directory -Path $runDir | Out-Null
$launcher = Join-Path $PSScriptRoot 'Start-DetachedEdaTool.ps1'

function Invoke-EdaStage([string]$StageName, [string]$Tool, [string]$Arguments, [string]$PassPattern = '') {
    $stageLog = Join-Path $runDir ($StageName + '.log')
    $stageStatus = Join-Path $runDir ($StageName + '.status.json')
    $toolPath = (Resolve-Path -LiteralPath (Join-Path $VivadoBin ($Tool + '.bat'))).Path
    & $launcher -PythonPath $PythonPath -WorkingDirectory $runDir `
        -LogPath $stageLog -StatusPath $stageStatus `
        -ToolCommandLine ('"' + $toolPath + '" ' + $Arguments) | Out-Null
    Write-Output "STAGE_STARTED $StageName"
    $stageTimer = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        Start-Sleep -Milliseconds 250
        $stageResult = $null
        if (Test-Path -LiteralPath $stageStatus) {
            # A worker may be between truncating and completing a JSON write.
            try { $stageResult = Get-Content -Raw -LiteralPath $stageStatus | ConvertFrom-Json }
            catch { $stageResult = $null }
        }
        if ($null -ne $stageResult -and $stageResult.state -in @('completed', 'failed')) {
            if ($stageResult.worker_in_job -ne $false -or $stageResult.returncode -ne 0) {
                throw "Stage failed: $StageName; inspect $stageStatus and $stageLog"
            }
            if ($PassPattern -and -not (Select-String -LiteralPath $stageLog -Pattern $PassPattern -Quiet)) {
                throw "Expected pass marker missing in $stageLog"
            }
            Write-Output "STAGE_PASS $StageName"
            return
        }
        if ($stageTimer.Elapsed.TotalSeconds -gt $StageTimeoutSeconds) {
            throw "Stage timeout: $StageName. Detached tool was NOT killed; inspect $stageStatus."
        }
    }
}

# Resolve source paths relative to the existing Efinity file list, preserving
# package-first order but excluding the Efinity-only top-level probes.
$flistDir = Join-Path $case2Root 'efinity_smoke'
$sourcePaths = @(Get-Content -LiteralPath (Join-Path $flistDir 'case2_rtl_all.f') | ForEach-Object {
    $entry = $_.Trim()
    if ($entry -and -not $entry.StartsWith('#') -and -not $entry.StartsWith('case2_rtl_probe_')) {
        (Resolve-Path -LiteralPath (Join-Path $flistDir $entry)).Path
    }
})
$tests = @(
    @{Top='tb_c2_axi4lite_csr_adapter';File='tb\bus\tb_c2_axi4lite_csr_adapter.sv';Pass='TB_C2_AXI4LITE_CSR_ADAPTER_PASS'},
    @{Top='tb_c2_mem_to_axi4_adapter';File='tb\bus\tb_c2_mem_to_axi4_adapter.sv';Pass='TB_C2_MEM_TO_AXI4_ADAPTER_PASS'},
    @{Top='tb_c2_mem_to_axi4_adapter_128';File='tb\bus\tb_c2_mem_to_axi4_adapter_128.sv';Pass='TB_C2_MEM_TO_AXI4_ADAPTER_PASS'},
    @{Top='tb_render_cmd_mem_engine_read_burst';File='tb\mem\tb_render_cmd_mem_engine_read_burst.sv';Pass='TB_RENDER_CMD_MEM_ENGINE_READ_BURST_PASS'},
    @{Top='tb_render_cmd_mem_engine_burst';File='tb\tb_render_cmd_mem_engine_burst.sv';Pass='TB_RENDER_CMD_MEM_ENGINE_BURST_PASS'},
    @{Top='tb_c2_cmd_mem_engine_burst';File='tb\tb_c2_cmd_mem_engine_burst.sv';Pass='TB_C2_CMD_MEM_ENGINE_BURST_PASS'},
    @{Top='tb_c2_stride_alignment';File='tb\cmd\tb_c2_stride_alignment.sv';Pass='TB_C2_STRIDE_ALIGNMENT_PASS'},
    @{Top='tb_cmd_mem';File='tb\tb_cmd_mem.sv';Pass='tb_cmd_mem PASS'},
    @{Top='tb_c2_renderer_system';File='tb\system\tb_c2_renderer_system.sv';Pass='TB_C2_RENDERER_SYSTEM_PASS'},
    @{Top='tb_c2_renderer_system_axi_shell';File='tb\system\tb_c2_renderer_system_axi_shell.sv';Pass='TB_C2_RENDERER_SYSTEM_AXI_SHELL_PASS'},
    @{Top='tb_c2_renderer_system_ip_stub';File='tb\system\tb_c2_renderer_system_ip_stub.sv';Pass=''}
)
foreach ($test in $tests) {
    $sourcePaths += (Resolve-Path -LiteralPath (Join-Path $case2Root $test.File)).Path
}
$sourceArgs = ($sourcePaths | ForEach-Object { '"' + $_ + '"' }) -join ' '
Invoke-EdaStage 'compile_all' 'xvlog' ('-sv ' + $sourceArgs)
foreach ($test in $tests) {
    $snapshot = $test.Top + '_verified'
    Invoke-EdaStage ($test.Top + '_elab') 'xelab' ($test.Top + ' -s ' + $snapshot)
    if ($test.Pass) {
        Invoke-EdaStage ($test.Top + '_sim') 'xsim' ($snapshot + ' -runall') $test.Pass
    }
}
Write-Output "NEWGUIDE_REGRESSION_PASS simulations=10 elaborations=11 run_dir=$runDir"
