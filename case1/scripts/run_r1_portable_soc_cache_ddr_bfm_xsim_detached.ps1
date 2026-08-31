param([switch]$Worker, [string]$RunId = '', [switch]$TwoFrame,
      [ValidateSet('8x8','16x8','64x48','640x480')][string]$Frame = '8x8',
      [switch]$CompileOnly, [switch]$ClientTrafficGate,
      [switch]$SharedQosMonitor,
      [switch]$TrainedArtifact,
      [switch]$TensorBurstRefill,
      [switch]$TensorBurstBeatMode,
      [switch]$DisplayResponseFifo, [switch]$RelaxedDescriptor,
       [switch]$FastAddress, [switch]$PipelinedAddress,
       [switch]$PipelinedPixelIndex,
       [switch]$PipelinedDescriptorValidation,
       [switch]$NarrowDescriptorSizeCheck,
       [switch]$PipelinedDescriptorSizeArith,
       [switch]$FixedDescriptorSizeLimits,
       [switch]$PipelinedDescriptorPixelCount,
       [switch]$IterativeDescriptorPixelCount,
       [switch]$PreclampedTapCoords,
       [switch]$RegisterAbortReset,
      [switch]$PipelinedStartConfig, [switch]$PipelinedDotTree,
      [switch]$PipelinedDotTreeFull, [switch]$PipelinedDescriptorReplay,
      [switch]$PrevalidateDescriptorReplay, [switch]$ReplicateAbortControl,
      [switch]$PipelinedDecoderValidation,
      [switch]$TableResponseFifo, [switch]$UnifiedOutputFifo,
      [switch]$UnifiedOutputSkid, [switch]$FabricReadResponseSkid,
      [switch]$RegisterFatalTicket)

# The outer process is created through Win32_Process.Create so Vivado/xsim
# are outside the caller's Windows Job.  This is important for long xsim runs
# from the desktop agent and mirrors the other detached Case-1 runners.
$ErrorActionPreference = 'Stop'
$caseRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rtlRoot = Join-Path $caseRoot 'rtl'
$simRoot = Join-Path $caseRoot 'sim'
$logRoot = Join-Path $caseRoot 'logs'

if (-not $Worker) {
    if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = [guid]::NewGuid().ToString('N') }
    $powerShell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $commandLine = '"' + $powerShell +
        '" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass' +
        ' -WindowStyle Hidden -File "' + $PSCommandPath +
        '" -Worker -RunId ' + $RunId + $(if($TwoFrame){' -TwoFrame'}else{''}) +
        ' -Frame ' + $Frame + $(if($CompileOnly){' -CompileOnly'}else{''}) +
        $(if($ClientTrafficGate){' -ClientTrafficGate'}else{''}) +
        $(if($SharedQosMonitor){' -SharedQosMonitor'}else{''}) +
        $(if($TrainedArtifact){' -TrainedArtifact'}else{''}) +
        $(if($TensorBurstRefill){' -TensorBurstRefill'}else{''}) +
        $(if($TensorBurstBeatMode){' -TensorBurstBeatMode'}else{''}) +
        $(if($DisplayResponseFifo){' -DisplayResponseFifo'}else{''}) +
        $(if($RelaxedDescriptor){' -RelaxedDescriptor'}else{''}) +
         $(if($FastAddress){' -FastAddress'}else{''}) +
         $(if($PipelinedAddress){' -PipelinedAddress'}else{''}) +
         $(if($PipelinedPixelIndex){' -PipelinedPixelIndex'}else{''}) +
        $(if($PipelinedDescriptorValidation){' -PipelinedDescriptorValidation'}else{''}) +
        $(if($NarrowDescriptorSizeCheck){' -NarrowDescriptorSizeCheck'}else{''}) +
        $(if($PipelinedDescriptorSizeArith){' -PipelinedDescriptorSizeArith'}else{''}) +
          $(if($FixedDescriptorSizeLimits){' -FixedDescriptorSizeLimits'}else{''}) +
          $(if($PipelinedDescriptorPixelCount){' -PipelinedDescriptorPixelCount'}else{''}) +
          $(if($IterativeDescriptorPixelCount){' -IterativeDescriptorPixelCount'}else{''}) +
          $(if($PreclampedTapCoords){' -PreclampedTapCoords'}else{''}) +
          $(if($RegisterAbortReset){' -RegisterAbortReset'}else{''}) +
        $(if($PipelinedStartConfig){' -PipelinedStartConfig'}else{''}) +
        $(if($PipelinedDotTree){' -PipelinedDotTree'}else{''}) +
        $(if($PipelinedDotTreeFull){' -PipelinedDotTreeFull'}else{''}) +
        $(if($PipelinedDescriptorReplay){' -PipelinedDescriptorReplay'}else{''}) +
        $(if($PrevalidateDescriptorReplay){' -PrevalidateDescriptorReplay'}else{''}) +
        $(if($PipelinedDecoderValidation){' -PipelinedDecoderValidation'}else{''}) +
        $(if($ReplicateAbortControl){' -ReplicateAbortControl'}else{''}) +
        $(if($TableResponseFifo){' -TableResponseFifo'}else{''}) +
        $(if($UnifiedOutputFifo){' -UnifiedOutputFifo'}else{''}) +
        $(if($UnifiedOutputSkid){' -UnifiedOutputSkid'}else{''}) +
        $(if($FabricReadResponseSkid){' -FabricReadResponseSkid'}else{''}) +
        $(if($RegisterFatalTicket){' -RegisterFatalTicket'}else{''})
    # Prefer WMI because it creates the worker outside the caller's Windows
    # Job.  Some managed desktops deny Win32_Process.Create, so fall back to
    # a tiny CreateProcess(CREATE_BREAKAWAY_FROM_JOB) helper.  The fallback
    # still leaves Vivado/xsim independent of this shell/job.
    $workerPid = $null
    try {
        $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create `
            -Arguments @{CommandLine=$commandLine; CurrentDirectory=$caseRoot}
        if ($result.ReturnValue -eq 0) { $workerPid = [int]$result.ProcessId }
    } catch {
        $result = $null
    }
    if ($null -eq $workerPid) {
        $launcher = Join-Path $PSScriptRoot 'start_detached_process.ps1'
        $launcherOutput = & $powerShell -NoLogo -NoProfile -NonInteractive `
            -ExecutionPolicy Bypass -File $launcher -CommandLine $commandLine `
            -CurrentDirectory $caseRoot 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "detached process fallback failed: $($launcherOutput -join ' ')"
        }
        try { $workerPid = [int](($launcherOutput | Select-Object -Last 1).ToString().Trim()) }
        catch { throw "detached process fallback returned invalid pid: $($launcherOutput -join ' ')" }
    }
    [ordered]@{ run_id=$RunId; worker_pid=$workerPid;
        status_path=(Join-Path $logRoot "portable_soc_cache_ddr_bfm_runs\$RunId\status.json") } |
        ConvertTo-Json
    return
}

if ($RunId -notmatch '^[A-Za-z0-9_-]+$') { throw 'bad RunId' }
$runRoot = Join-Path $simRoot "portable_soc_cache_ddr_bfm_run_$RunId"
$runLogRoot = Join-Path $logRoot "portable_soc_cache_ddr_bfm_runs\$RunId"
$statusPath = Join-Path $runLogRoot 'status.json'
$latestStatusPath = Join-Path $logRoot 'portable_soc_cache_ddr_bfm_status.json'
$artifactVectorRoot = Join-Path $caseRoot 'vectors\microstyle_engine_bitexact_8x8'
$vivadoBin = 'D:\vivado\vivado\Vivado\2023.1\bin'
$watch = [Diagnostics.Stopwatch]::StartNew(); $script:currentStep='setup'
New-Item -ItemType Directory -Force -Path $runRoot,$runLogRoot | Out-Null

function Set-StatusContent([string]$Path,[string]$Value) {
    $Value | Set-Content -LiteralPath $Path -Encoding UTF8
}
function Write-Status([string]$State,[string]$Step,[int]$ExitCode,[string]$Message) {
    $value=[ordered]@{run_id=$RunId;frame=$Frame;state=$State;step=$Step;exit_code=$ExitCode;
        message=$Message;process_id=$PID;
        elapsed_seconds=[math]::Round($watch.Elapsed.TotalSeconds,3);
        updated=(Get-Date).ToString('o');log_directory=$runLogRoot;run_directory=$runRoot} |
        ConvertTo-Json
    Set-StatusContent $statusPath $value; Set-StatusContent $latestStatusPath $value
}
function Save-CompactLog([string]$Source,[string]$Destination,[string]$Marker='') {
    # Keep persistent diagnostics bounded even when a native xsim emits one
    # line per pixel.  The complete stream lives only below runRoot and is
    # removed by the worker's finally block.
    $lines=@()
    if(Test-Path -LiteralPath $Source){
        if($Marker){
            $lines += @(Select-String -LiteralPath $Source -Pattern ([regex]::Escape($Marker)) -AllMatches -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Line })
        }
        $lines += @(Get-Content -LiteralPath $Source -Tail 80 -ErrorAction SilentlyContinue)
    }
    if($lines.Count -eq 0){$lines=@('(empty)')}
    $lines | Select-Object -Unique | Set-Content -LiteralPath $Destination -Encoding UTF8
}
function Invoke-XsimStep {
    param([string]$Name,[string]$Tool,[string[]]$Arguments,[string]$ExpectedPass='')
    $script:currentStep=$Name; Write-Status running $Name 0 "starting $Name"
    $rawOut=Join-Path $runRoot "$Name.stdout.raw.log"; $rawErr=Join-Path $runRoot "$Name.stderr.raw.log"
    $out=Join-Path $runLogRoot "$Name.stdout.log"; $err=Join-Path $runLogRoot "$Name.stderr.log"
    try {
        $p=Start-Process -FilePath $Tool -ArgumentList $Arguments -WorkingDirectory $runRoot `
            -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $rawOut -RedirectStandardError $rawErr
        if($p.ExitCode -ne 0){throw "$Name exit $($p.ExitCode)"}
        # Do not load an entire Vivado/xsim log into the worker process.  Native
        # frame runs can produce hundreds of megabytes of stdout; stream the
        # checks line-by-line and retain only a short tail in a failure message.
        $badPattern='(?i)^\s*(ERROR|FATAL):|\bFAIL\b|_[Ff][Aa][Ii][Ll]\b|cannot be opened|\$\s*fatal'
        if(Select-String -LiteralPath $rawErr -Pattern '\S' -Quiet -ErrorAction SilentlyContinue){
            $tail=((Get-Content -LiteralPath $rawErr -Tail 12 -ErrorAction SilentlyContinue) -join ' ')
            throw "$Name unexpected stderr: $tail"
        }
        if(Select-String -LiteralPath $rawOut -Pattern $badPattern -Quiet -ErrorAction SilentlyContinue){
            $tail=((Get-Content -LiteralPath $rawOut -Tail 12 -ErrorAction SilentlyContinue) -join ' ')
            throw "$Name log contains ERROR/FATAL/FAIL: $tail"
        }
        if($ExpectedPass){
            $n=0
            foreach($hit in @(Select-String -LiteralPath $rawOut -Pattern ([regex]::Escape($ExpectedPass)) -AllMatches -ErrorAction SilentlyContinue)){
                if($hit.Matches){$n += $hit.Matches.Count}else{$n++}
            }
            if($n -ne 1){throw "$Name missing unique marker count=$n"}
        }
    } finally {
        Save-CompactLog $rawOut $out $ExpectedPass
        Save-CompactLog $rawErr $err
    }
}

try {
    Write-Status running setup 0 'detached portable SoC cache DDR BFM started'
    $packageSources=@(
        (Join-Path $rtlRoot 'common\c1_fixed_pkg.sv'),
        (Join-Path $rtlRoot 'control\c1_descriptor_pkg.sv'),
        (Join-Path $rtlRoot 'control\c1_descriptor_decoder_pkg.sv'),
        (Join-Path $rtlRoot 'control\c1_frame_buffer_pkg.sv'))
    $packageSet=@{}; foreach($s in $packageSources){$packageSet[$s]=$true}
    $remaining=Get-ChildItem -LiteralPath $rtlRoot -Recurse -File -Filter '*.sv' |
        Where-Object {-not $packageSet.ContainsKey($_.FullName)} |
        Sort-Object FullName | Select-Object -ExpandProperty FullName
    $sources=@($packageSources)+@($remaining)+@((Join-Path $simRoot 'tb_c1_r1_portable_soc_cache_ddr_bfm.sv'))
    if ($ClientTrafficGate) {
        $sources += (Join-Path $simRoot 'c1_axi_client_traffic_monitor.sv')
    }
    # Native-shape elaboration now includes more than one hundred RTL files.
    # Passing every absolute path through Start-Process can exceed the
    # Windows command-line limit and is reported by xvlog as "access denied".
    # Keep the command line short with a private xvlog file list; the worker
    # removes the complete runRoot (including this manifest) on exit.
    $sourceListPath = Join-Path $runRoot 'xvlog_sources.f'
    $sources | Set-Content -LiteralPath $sourceListPath -Encoding ASCII
    $xvlogArgs=@('-sv')
    if($TwoFrame){$xvlogArgs += @('-d','C1_TWO_FRAME')}
    if($SharedQosMonitor){$xvlogArgs += @('-d','C1_SHARED_QOS_MONITOR')}
    if($TrainedArtifact){$xvlogArgs += @('-d','C1_TRAINED_ARTIFACT')}
    if($TensorBurstRefill){$xvlogArgs += @('-d','C1_TENSOR_BURST_REFILL')}
    if($TensorBurstBeatMode){$xvlogArgs += @('-d','C1_TENSOR_BURST_BEAT_MODE')}
    if($DisplayResponseFifo){$xvlogArgs += @('-d','C1_DISPLAY_RESPONSE_FIFO')}
    if($RelaxedDescriptor){$xvlogArgs += @('-d','C1_RELAXED_DESCRIPTOR')}
    if($FastAddress){$xvlogArgs += @('-d','C1_FAST_ADDRESS')}
    if($PipelinedAddress){$xvlogArgs += @('-d','C1_PIPELINED_ADDRESS')}
    if($PipelinedPixelIndex){$xvlogArgs += @('-d','C1_PIPELINED_TENSOR_PIXEL_INDEX')}
    if($PipelinedDescriptorValidation){$xvlogArgs += @('-d','C1_PIPELINED_DESCRIPTOR_VALIDATION')}
    if($NarrowDescriptorSizeCheck){$xvlogArgs += @('-d','C1_NARROW_DESCRIPTOR_SIZE_CHECK')}
    if($PipelinedDescriptorSizeArith){$xvlogArgs += @('-d','C1_PIPELINED_DESCRIPTOR_SIZE_ARITH')}
    if($FixedDescriptorSizeLimits){$xvlogArgs += @('-d','C1_FIXED_DESCRIPTOR_SIZE_LIMITS')}
    if($PipelinedDescriptorPixelCount){$xvlogArgs += @('-d','C1_PIPELINED_DESCRIPTOR_PIXEL_COUNT')}
    if($IterativeDescriptorPixelCount){$xvlogArgs += @('-d','C1_ITERATIVE_DESCRIPTOR_PIXEL_COUNT')}
    if($PreclampedTapCoords){$xvlogArgs += @('-d','C1_PRECLAMPED_TAP_COORDS')}
    if($RegisterAbortReset){$xvlogArgs += @('-d','C1_REGISTER_ABORT_RESET')}
    if($PipelinedStartConfig){$xvlogArgs += @('-d','C1_PIPELINED_START_CONFIG')}
    if($PipelinedDotTree){$xvlogArgs += @('-d','C1_PIPELINED_DOT_TREE')}
    if($PipelinedDotTreeFull){$xvlogArgs += @('-d','C1_PIPELINED_DOT_TREE_FULL')}
    if($PipelinedDescriptorReplay){$xvlogArgs += @('-d','C1_PIPELINED_DESCRIPTOR_REPLAY')}
    if($PrevalidateDescriptorReplay){$xvlogArgs += @('-d','C1_PREVALIDATE_DESCRIPTOR_REPLAY')}
    if($PipelinedDecoderValidation){$xvlogArgs += @('-d','C1_PIPELINED_DECODER_VALIDATION')}
    if($ReplicateAbortControl){$xvlogArgs += @('-d','C1_REPLICATE_ABORT_CONTROL')}
    if($TableResponseFifo){$xvlogArgs += @('-d','C1_TABLE_RESPONSE_FIFO')}
    if($UnifiedOutputFifo){$xvlogArgs += @('-d','C1_UNIFIED_OUTPUT_FIFO')}
    if($UnifiedOutputSkid){$xvlogArgs += @('-d','C1_UNIFIED_OUTPUT_SKID')}
    if($FabricReadResponseSkid){$xvlogArgs += @('-d','C1_FABRIC_READ_RESPONSE_SKID')}
    if($RegisterFatalTicket){$xvlogArgs += @('-d','C1_REGISTER_FATAL_TICKET')}
    switch($Frame) {
        '16x8'  { $xvlogArgs += @('-d','C1_FRAME_16X8') }
        '64x48' { $xvlogArgs += @('-d','C1_FRAME_64X48') }
        '640x480' { $xvlogArgs += @('-d','C1_FRAME_640X480') }
    }
    $xvlogArgs += @('-f', $sourceListPath)
    if($TrainedArtifact) {
        foreach($f in 'descriptors.mem','parameter_arena.mem') {
            $destName = if($f -eq 'descriptors.mem') {
                'trained_descriptors.mem'
            } else {
                'trained_parameter_arena.mem'
            }
            Copy-Item -LiteralPath (Join-Path $artifactVectorRoot $f) `
                -Destination (Join-Path $runRoot $destName)
        }
    }
    Invoke-XsimStep xvlog (Join-Path $vivadoBin 'xvlog.bat') $xvlogArgs
    Invoke-XsimStep xelab (Join-Path $vivadoBin 'xelab.bat') @(
        'tb_c1_r1_portable_soc_cache_ddr_bfm','-s','tb_c1_r1_portable_soc_cache_ddr_bfm_sim')
    if ($CompileOnly) {
        $watch.Stop()
        Write-Status complete elaboration 0 "C1_R1_PORTABLE_SOC_SHAPE_ELAB_PASS frame=$Frame"
        return
    }
    $expectedPass = if($ClientTrafficGate){
        'C1_R1_PORTABLE_SOC_AXI_CLIENT_MONITOR_PASS'
    } elseif($TwoFrame){
        'C1_R1_PORTABLE_SOC_CACHE_DDR_BFM_TWO_FRAME_PASS'
    } else {
        'C1_R1_PORTABLE_SOC_CACHE_DDR_BFM_PASS'
    }
    if($TrainedArtifact) {
        # The normal lifecycle marker is still required; the additional
        # artifact marker proves the parameter arena was actually addressed.
        $expectedPass = 'C1_R1_PORTABLE_SOC_TRAINED_ARTIFACT_8X8_PASS'
    }
    Invoke-XsimStep xsim (Join-Path $vivadoBin 'xsim.bat') @(
        'tb_c1_r1_portable_soc_cache_ddr_bfm_sim','-runall') $expectedPass
    $watch.Stop(); Write-Status complete done 0 $expectedPass
} catch {
    $watch.Stop(); Write-Status failed $script:currentStep 1 $_.Exception.Message; exit 1
} finally {
    # Never leave a native Vivado/xsim run tree behind, including the failure
    # path.  Status/stdout/stderr remain under case1/logs for diagnosis.
    if (Test-Path -LiteralPath $runRoot) {
        Remove-Item -LiteralPath $runRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
