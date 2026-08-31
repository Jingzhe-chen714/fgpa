param(
    [Parameter(Mandatory = $true)]
    [string]$RunId
)

$ErrorActionPreference = 'Stop'
$caseRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rtlRoot = Join-Path $caseRoot 'rtl'
$simRoot = Join-Path $caseRoot 'sim'
$logRoot = Join-Path $caseRoot 'logs'
$runRoot = Join-Path $simRoot "xsim_run_$RunId"
$runLogRoot = Join-Path $logRoot "xsim_runs\$RunId"
$statusPath = Join-Path $runLogRoot 'status.json'
$latestStatusPath = Join-Path $logRoot 'xsim_status.json'
$vivadoBin = 'D:\vivado\vivado\Vivado\2023.1\bin'

New-Item -ItemType Directory -Force -Path $runRoot, $runLogRoot | Out-Null

function Set-StatusContent {
    param([string]$Path, [string]$Value)
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        try {
            $Value | Set-Content -LiteralPath $Path -Encoding UTF8 `
                -ErrorAction Stop
            return
        } catch [IO.IOException] {
            if ($attempt -eq 19) { throw }
            Start-Sleep -Milliseconds 25
        }
    }
}

function Write-Status {
    param(
        [string]$State,
        [string]$Step,
        [int]$ExitCode,
        [string]$Message
    )
    $status = [ordered]@{
        run_id = $RunId
        state = $State
        step = $Step
        exit_code = $ExitCode
        message = $Message
        process_id = $PID
        updated = (Get-Date).ToString('o')
        log_directory = $runLogRoot
    } | ConvertTo-Json
    Set-StatusContent -Path $statusPath -Value $status
    Set-StatusContent -Path $latestStatusPath -Value $status
}

function Invoke-VivadoStep {
    param(
        [string]$Name,
        [string]$Tool,
        [string[]]$Arguments,
        [string]$ExpectedPass = ''
    )
    Write-Status -State 'running' -Step $Name -ExitCode 0 -Message "starting $Name"
    $stdoutPath = Join-Path $runLogRoot "$Name.stdout.log"
    $stderrPath = Join-Path $runLogRoot "$Name.stderr.log"
    $process = Start-Process -FilePath $Tool -ArgumentList $Arguments `
        -WorkingDirectory $runRoot -WindowStyle Hidden -Wait -PassThru `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    if ($process.ExitCode -ne 0) {
        throw "$Name failed with exit code $($process.ExitCode)"
    }
    $stdout = Get-Content -Raw -LiteralPath $stdoutPath
    $stderr = Get-Content -Raw -LiteralPath $stderrPath
    $diagnostics = $stdout + "`n" + $stderr
    if ($diagnostics -match '(?im)(^|\s)(Fatal|Error):|\bFAIL\b|cannot be opened|\$\s*fatal') {
        throw "$Name reported a simulation fatal/error; inspect $stdoutPath"
    }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        throw "$Name wrote a diagnostic to stderr; inspect $stderrPath"
    }
    # xsim can return process exit code 0 after a SystemVerilog $fatal.  A
    # regression is therefore successful only when its unique PASS marker is
    # present and no simulator fatal/error/file-open diagnostic was printed.
    if ($ExpectedPass) {
        $passCount = [regex]::Matches(
            $diagnostics, [regex]::Escape($ExpectedPass)).Count
        if ($passCount -ne 1) {
            throw "$Name emitted $passCount copies of required marker $ExpectedPass; expected exactly one"
        }
    }
}

try {
    Write-Status -State 'running' -Step 'setup' -ExitCode 0 -Message 'detached worker started'
    $sources = @(
        '-sv',
        (Join-Path $rtlRoot 'common\c1_fixed_pkg.sv'),
        (Join-Path $rtlRoot 'common\c1_reset_sync.sv'),
        (Join-Path $rtlRoot 'common\c1_async_stream_fifo.sv'),
        (Join-Path $rtlRoot 'common\c1_event_cdc.sv'),
        (Join-Path $rtlRoot 'common\c1_ram_sdp_read_first.sv'),
        (Join-Path $rtlRoot 'common\c1_stream_fifo.sv'),
        (Join-Path $rtlRoot 'common\c1_window3x3.sv'),
        (Join-Path $rtlRoot 'video\c1_black_level_raw10.sv'),
        (Join-Path $rtlRoot 'video\c1_raw10_unpack4.sv'),
        (Join-Path $rtlRoot 'video\c1_debayer_rggb10_valid.sv'),
        (Join-Path $rtlRoot 'video\c1_color_correct.sv'),
        (Join-Path $rtlRoot 'video\c1_gamma_lut16.sv'),
        (Join-Path $rtlRoot 'video\c1_rgb_decimate.sv'),
        (Join-Path $rtlRoot 'video\c1_isp_pipeline.sv'),
        (Join-Path $rtlRoot 'video\r1_blc_bayer4_u10.sv'),
        (Join-Path $rtlRoot 'video\c1_r1_debayer_bilinear.sv'),
        (Join-Path $rtlRoot 'video\r1_rgb10_color_pipeline.sv'),
        (Join-Path $rtlRoot 'video\r1_resize_request_q16.sv'),
        (Join-Path $rtlRoot 'video\r1_bilinear_interp_rgb888.sv'),
        (Join-Path $rtlRoot 'video\c1_r1_resize_system.sv'),
        (Join-Path $rtlRoot 'video\c1_r1_resize_line_sampler.sv'),
        (Join-Path $rtlRoot 'video\c1_r1_resize_pipeline.sv'),
        (Join-Path $rtlRoot 'video\c1_r1_isp_pipeline.sv'),
        (Join-Path $rtlRoot 'cnn\c1_conv3x3_rgb3.sv'),
        (Join-Path $rtlRoot 'cnn\c1_dwconv3x3_rgb3.sv'),
        (Join-Path $rtlRoot 'cnn\c1_pwconv1x1_rgb3.sv'),
        (Join-Path $rtlRoot 'cnn\c1_requant_s8.sv'),
        (Join-Path $rtlRoot 'cnn\c1_residual_add_s8.sv'),
        (Join-Path $rtlRoot 'cnn\c1_residual_add_c8.sv'),
        (Join-Path $rtlRoot 'cnn\c1_r1_parameter_bank.sv'),
        (Join-Path $rtlRoot 'cnn\c1_rgb_s8_center_codec.sv'),
        (Join-Path $rtlRoot 'cnn\c1_r1_compute_ingress.sv'),
        (Join-Path $rtlRoot 'cnn\c1_r1_compute_egress.sv'),
        (Join-Path $rtlRoot 'cnn\c1_s8_dot8_accum.sv'),
        (Join-Path $rtlRoot 'cnn\c1_s8_dot8_accum_pipelined.sv'),
        (Join-Path $rtlRoot 'cnn\c1_s8_dot8_accum_treepipe.sv'),
        (Join-Path $rtlRoot 'cnn\c1_requant_bank8.sv'),
        (Join-Path $rtlRoot 'cnn\c1_dwconv3x3_c8_requant_core.sv'),
        (Join-Path $rtlRoot 'cnn\c1_dot8x8_requant_core.sv'),
        (Join-Path $rtlRoot 'cnn\c1_s8_upsample2_c8.sv'),
        (Join-Path $rtlRoot 'cnn\c1_s8_window3x3_same_c8.sv'),
        (Join-Path $rtlRoot 'cnn\c1_style_cnn3.sv'),
        (Join-Path $rtlRoot 'control\c1_descriptor_pkg.sv'),
        (Join-Path $rtlRoot 'control\c1_descriptor_decoder_pkg.sv'),
        (Join-Path $rtlRoot 'control\c1_frame_buffer_pkg.sv'),
        (Join-Path $rtlRoot 'control\c1_apb_csr.sv'),
        (Join-Path $rtlRoot 'control\c1_apb_r1_mux.sv'),
        (Join-Path $rtlRoot 'control\c1_apb_isp_config.sv'),
        (Join-Path $rtlRoot 'control\c1_frame_manager.sv'),
        (Join-Path $rtlRoot 'control\c1_layer_scheduler.sv'),
        (Join-Path $rtlRoot 'control\c1_descriptor_scheduler_subsystem.sv'),
        (Join-Path $rtlRoot 'control\c1_layer_command_decoder.sv'),
        (Join-Path $rtlRoot 'control\c1_frame_pair_resolver.sv'),
        (Join-Path $rtlRoot 'control\c1_r1_job_controller.sv'),
        (Join-Path $rtlRoot 'control\c1_r1_config_dispatcher.sv'),
        (Join-Path $rtlRoot 'control\c1_r1_stage_config_bank.sv'),
        (Join-Path $rtlRoot 'control\c1_r1_config_loader_subsystem.sv'),
        (Join-Path $rtlRoot 'control\c1_r1_job_frontend.sv'),
        (Join-Path $rtlRoot 'dma\c1_axi_xrgb_frame_writer.sv'),
        (Join-Path $rtlRoot 'dma\c1_axi_xrgb_frame_reader.sv'),
        (Join-Path $rtlRoot 'dma\c1_axi_descriptor_reader.sv'),
        (Join-Path $rtlRoot 'dma\c1_axi_frame_buffer_table_reader.sv'),
        (Join-Path $rtlRoot 'dma\c1_axi_parameter_loader.sv'),
        (Join-Path $rtlRoot 'dma\c1_axi2_serial_arbiter_128.sv'),
        (Join-Path $rtlRoot 'vendor\c1_camera_vendor_adapter_stub.sv'),
        (Join-Path $rtlRoot 'vendor\c1_memory_vendor_adapter_stub.sv'),
        (Join-Path $rtlRoot 'vendor\c1_sapphire_vendor_adapter_stub.sv'),
        (Join-Path $rtlRoot 'vendor\c1_video_vendor_adapter_stub.sv'),
        (Join-Path $rtlRoot 'top\c1_portable_top.sv'),
        (Join-Path $rtlRoot 'top\c1_pixel_pipeline_top.sv'),
        (Join-Path $rtlRoot 'top\c1_r1_rgb_source_mux.sv'),
        (Join-Path $rtlRoot 'top\c1_r1_compute_shell.sv'),
        (Join-Path $rtlRoot 'top\c1_r1_integration_skeleton.sv'),
        (Join-Path $rtlRoot 'top\c1_r1_boardless_frame_system.sv'),
        (Join-Path $rtlRoot 'display\c1_video_timing_720p.sv'),
        (Join-Path $rtlRoot 'display\c1_split_compositor.sv'),
        (Join-Path $simRoot 'tb_c1_stream_fifo.sv'),
        (Join-Path $simRoot 'tb_c1_reset_sync.sv'),
        (Join-Path $simRoot 'tb_c1_event_cdc.sv'),
        (Join-Path $simRoot 'tb_c1_layer_scheduler.sv'),
        (Join-Path $simRoot 'tb_c1_rgb_s8_center_codec.sv'),
        (Join-Path $simRoot 'tb_c1_style_cnn3.sv'),
        (Join-Path $simRoot 'tb_c1_raw10_unpack4.sv'),
        (Join-Path $simRoot 'tb_c1_gamma_lut16.sv'),
        (Join-Path $simRoot 'tb_c1_isp_pipeline.sv'),
        (Join-Path $simRoot 'tb_c1_isp_config.sv'),
        (Join-Path $simRoot 'tb_c1_pixel_pipeline_top.sv'),
        (Join-Path $simRoot 'tb_c1_control.sv'),
        (Join-Path $simRoot 'tb_c1_r1_integration_skeleton.sv')
    )
    Invoke-VivadoStep -Name 'xvlog' -Tool (Join-Path $vivadoBin 'xvlog.bat') -Arguments $sources
    Invoke-VivadoStep -Name 'xelab_arch' -Tool (Join-Path $vivadoBin 'xelab.bat') `
        -Arguments @('c1_portable_top', '-s', 'c1_portable_top_compile')
    Invoke-VivadoStep -Name 'xelab_fifo' -Tool (Join-Path $vivadoBin 'xelab.bat') `
        -Arguments @('tb_c1_stream_fifo', '-s', 'tb_c1_stream_fifo_sim')
    Invoke-VivadoStep -Name 'xsim_fifo' -Tool (Join-Path $vivadoBin 'xsim.bat') `
        -Arguments @('tb_c1_stream_fifo_sim', '-runall') `
        -ExpectedPass 'FIFO_RANDOM_STALL_PASS'
    Invoke-VivadoStep -Name 'xelab_reset_sync' -Tool (Join-Path $vivadoBin 'xelab.bat') `
        -Arguments @('tb_c1_reset_sync', '-s', 'tb_c1_reset_sync_sim')
    Invoke-VivadoStep -Name 'xsim_reset_sync' -Tool (Join-Path $vivadoBin 'xsim.bat') `
        -Arguments @('tb_c1_reset_sync_sim', '-runall') `
        -ExpectedPass 'C1_RESET_SYNC_PASS'
    Invoke-VivadoStep -Name 'xelab_event_cdc' -Tool (Join-Path $vivadoBin 'xelab.bat') `
        -Arguments @('tb_c1_event_cdc', '-s', 'tb_c1_event_cdc_sim')
    Invoke-VivadoStep -Name 'xsim_event_cdc' -Tool (Join-Path $vivadoBin 'xsim.bat') `
        -Arguments @('tb_c1_event_cdc_sim', '-runall') `
        -ExpectedPass 'C1_EVENT_CDC_PASS'
    Invoke-VivadoStep -Name 'xelab_scheduler' -Tool (Join-Path $vivadoBin 'xelab.bat') `
        -Arguments @('tb_c1_layer_scheduler', '-s', 'tb_c1_layer_scheduler_sim')
    Invoke-VivadoStep -Name 'xsim_scheduler' -Tool (Join-Path $vivadoBin 'xsim.bat') `
        -Arguments @('tb_c1_layer_scheduler_sim', '-runall') `
        -ExpectedPass 'C1_LAYER_SCHEDULER_PASS'
    Invoke-VivadoStep -Name 'xelab_rgb_s8_codec' -Tool (Join-Path $vivadoBin 'xelab.bat') `
        -Arguments @('tb_c1_rgb_s8_center_codec', '-s', 'tb_c1_rgb_s8_center_codec_sim')
    Invoke-VivadoStep -Name 'xsim_rgb_s8_codec' -Tool (Join-Path $vivadoBin 'xsim.bat') `
        -Arguments @('tb_c1_rgb_s8_center_codec_sim', '-runall') `
        -ExpectedPass 'C1_RGB_S8_CODEC_PASS'
    Invoke-VivadoStep -Name 'xelab_raw10' -Tool (Join-Path $vivadoBin 'xelab.bat') `
        -Arguments @('tb_c1_raw10_unpack4', '-s', 'tb_c1_raw10_unpack4_sim')
    Invoke-VivadoStep -Name 'xsim_raw10' -Tool (Join-Path $vivadoBin 'xsim.bat') `
        -Arguments @('tb_c1_raw10_unpack4_sim', '-runall') `
        -ExpectedPass 'C1_RAW10_UNPACK_PASS'
    Invoke-VivadoStep -Name 'xelab_gamma' -Tool (Join-Path $vivadoBin 'xelab.bat') `
        -Arguments @('tb_c1_gamma_lut16', '-s', 'tb_c1_gamma_lut16_sim')
    Invoke-VivadoStep -Name 'xsim_gamma' -Tool (Join-Path $vivadoBin 'xsim.bat') `
        -Arguments @('tb_c1_gamma_lut16_sim', '-runall') `
        -ExpectedPass 'C1_GAMMA_PASS'
    Invoke-VivadoStep -Name 'xelab_style' -Tool (Join-Path $vivadoBin 'xelab.bat') `
        -Arguments @('tb_c1_style_cnn3', '-s', 'tb_c1_style_cnn3_sim')
    Invoke-VivadoStep -Name 'xsim_style' -Tool (Join-Path $vivadoBin 'xsim.bat') `
        -Arguments @('tb_c1_style_cnn3_sim', '-runall') `
        -ExpectedPass 'C1_STYLE_CNN3_PASS'
    Invoke-VivadoStep -Name 'xelab_isp' -Tool (Join-Path $vivadoBin 'xelab.bat') `
        -Arguments @('tb_c1_isp_pipeline', '-s', 'tb_c1_isp_pipeline_sim')
    Invoke-VivadoStep -Name 'xsim_isp' -Tool (Join-Path $vivadoBin 'xsim.bat') `
        -Arguments @('tb_c1_isp_pipeline_sim', '-runall') `
        -ExpectedPass 'C1_ISP_PASS'
    Invoke-VivadoStep -Name 'xelab_isp_config' -Tool (Join-Path $vivadoBin 'xelab.bat') `
        -Arguments @('tb_c1_isp_config', '-s', 'tb_c1_isp_config_sim')
    Invoke-VivadoStep -Name 'xsim_isp_config' -Tool (Join-Path $vivadoBin 'xsim.bat') `
        -Arguments @('tb_c1_isp_config_sim', '-runall') `
        -ExpectedPass 'C1_ISP_CONFIG_PASS'
    Invoke-VivadoStep -Name 'xelab_system' -Tool (Join-Path $vivadoBin 'xelab.bat') `
        -Arguments @('tb_c1_pixel_pipeline_top', '-s', 'tb_c1_pixel_pipeline_top_sim')
    Invoke-VivadoStep -Name 'xsim_system' -Tool (Join-Path $vivadoBin 'xsim.bat') `
        -Arguments @('tb_c1_pixel_pipeline_top_sim', '-runall') `
        -ExpectedPass 'C1_PIXEL_SYSTEM_PASS'
    Invoke-VivadoStep -Name 'xelab_control' -Tool (Join-Path $vivadoBin 'xelab.bat') `
        -Arguments @('tb_c1_control', '-s', 'tb_c1_control_sim')
    Invoke-VivadoStep -Name 'xsim_control' -Tool (Join-Path $vivadoBin 'xsim.bat') `
        -Arguments @('tb_c1_control_sim', '-runall') `
        -ExpectedPass 'C1_CONTROL_PASS'
    Invoke-VivadoStep -Name 'xelab_r1_integration' -Tool (Join-Path $vivadoBin 'xelab.bat') `
        -Arguments @('tb_c1_r1_integration_skeleton', '-s', 'tb_c1_r1_integration_skeleton_sim')
    Invoke-VivadoStep -Name 'xsim_r1_integration' -Tool (Join-Path $vivadoBin 'xsim.bat') `
        -Arguments @('tb_c1_r1_integration_skeleton_sim', '-runall') `
        -ExpectedPass 'C1_R1_INTEGRATION_SKELETON_PASS'
    Write-Status -State 'complete' -Step 'done' -ExitCode 0 -Message 'C1 xsim regression complete'
} catch {
    Write-Status -State 'failed' -Step 'exception' -ExitCode 1 -Message $_.Exception.Message
    exit 1
}
