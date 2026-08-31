param(
    [string]$VivadoBin = 'D:\vivado\vivado\Vivado\2023.1\bin',
    [switch]$Full640
)

$ErrorActionPreference = 'Stop'
$case4 = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$project = (Resolve-Path (Join-Path $case4 '..')).Path
$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim = Join-Path $VivadoBin 'xsim.bat'
$vivadoRoot = (Resolve-Path (Join-Path $VivadoBin '..')).Path
$xpmMemory = Join-Path $vivadoRoot 'data\ip\xpm\xpm_memory\hdl\xpm_memory.sv'

foreach ($tool in @($xvlog, $xelab, $xsim, $xpmMemory)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Vivado/XPM file not found: $tool"
    }
}

Set-Location -LiteralPath $project

function Invoke-VivadoTool {
    param([string]$Tool, [string[]]$Arguments)
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado command failed ($LASTEXITCODE): $Tool $($Arguments -join ' ')"
    }
}

# Compile the XPM implementation explicitly.  This is deliberately separate
# from run_xsim.ps1: the portable regression must remain runnable without any
# Xilinx library, while this script is the current Xilinx-board adapter.
Invoke-VivadoTool $xvlog @('-sv',
    $xpmMemory,
    'case4\rtl\xilinx_bram_sdp_row.sv',
    'case4\rtl\window3x3_gray_xilinx_bram.sv',
    'case4\rtl\window3x3_gray.sv',
    'case4\rtl\rgb_unpack_stream.sv',
    'case4\rtl\gray_rgb_stream.sv',
    'case4\rtl\case4_rgb_frontend.sv',
    'case4\rtl\case4_sobel_edge_ops.sv',
    'case4\rtl\case4_gray_sobel_core.sv',
    'case4\rtl\case4_gray_sobel_core_xilinx_bram.sv',
    'case4\rtl\median3x3_u8.sv',
    'case4\rtl\case4_gray_median_sobel_core.sv',
    'case4\rtl\case4_gray_median_sobel_core_xilinx_bram.sv',
    'case4\tb\tb_window3x3_gray_xilinx_bram.sv',
    'case4\tb\tb_gray_sobel_core_xilinx_bram.sv',
    'case4\tb\tb_gray_median_sobel_core.sv',
    'case4\tb\tb_gray_median_sobel_core_xilinx_bram.sv',
    'case4\tb\tb_gray_sobel_core_640.sv',
    'case4\tb\tb_gray_sobel_core_xilinx_bram_640.sv',
    'case4\tb\tb_gray_median_sobel_core_640.sv',
    'case4\tb\tb_gray_median_sobel_core_xilinx_bram_640.sv')

Invoke-VivadoTool $xelab @('tb_window3x3_gray_xilinx_bram',
    '--snapshot', 'case4_tb_window_xilinx_bram')
Invoke-VivadoTool $xsim @('case4_tb_window_xilinx_bram', '-runall', '-nolog')

Invoke-VivadoTool $xelab @('tb_gray_sobel_core_xilinx_bram',
    '--snapshot', 'case4_tb_core_xilinx_bram')
Invoke-VivadoTool $xsim @('case4_tb_core_xilinx_bram', '-runall', '-nolog')

Invoke-VivadoTool $xelab @('tb_gray_median_sobel_core_xilinx_bram',
    '--snapshot', 'case4_tb_median_xilinx_bram')
Invoke-VivadoTool $xsim @('case4_tb_median_xilinx_bram', '-runall', '-nolog')

if ($Full640) {
    # The wrapper selects WINDOW_BACKEND=1 without relying on simulator-
    # specific generic override quoting in a Windows batch invocation.
    Invoke-VivadoTool $xelab @('tb_gray_sobel_core_xilinx_bram_640',
        '--snapshot', 'case4_tb_core_xilinx_bram_640')
    Invoke-VivadoTool $xsim @('case4_tb_core_xilinx_bram_640', '-runall', '-nolog')

    Invoke-VivadoTool $xelab @('tb_gray_median_sobel_core_xilinx_bram_640',
        '--snapshot', 'case4_tb_median_xilinx_bram_640')
    Invoke-VivadoTool $xsim @('case4_tb_median_xilinx_bram_640', '-runall', '-nolog')
}

if ($Full640) {
    Write-Host 'CASE4 XSIM XILINX BRAM PASS: window + packed cores + median cascade + 640x480 throughput'
} else {
    Write-Host 'CASE4 XSIM XILINX BRAM PASS: window + packed cores + median cascade'
}
