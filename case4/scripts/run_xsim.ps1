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

foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Vivado simulator tool not found: $tool"
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

# The two snapshots are deliberately named differently.  Vivado's default
# work library is reused, so compiling the small tests in this order also
# serves as a full parser/elaboration smoke test for the current RTL set.
Invoke-VivadoTool $xvlog @('-sv',
    'case4\rtl\gray_rgb_stream.sv',
    'case4\tb\tb_gray_rgb.sv')
Invoke-VivadoTool $xelab @('tb_gray_rgb', '-s', 'case4_tb_gray')
Invoke-VivadoTool $xsim @('case4_tb_gray', '-runall', '-nolog')

Invoke-VivadoTool $xvlog @('-sv',
    'case4\rtl\rgb_unpack_stream.sv',
    'case4\rtl\window3x3_gray.sv',
    'case4\rtl\median3x3_u8.sv',
    'case4\rtl\window3x3_median.sv',
    'case4\rtl\case4_sobel_edge_ops.sv',
    'case4\rtl\case4_edge_expand.sv',
    'case4\tb\tb_image_operators.sv',
    'case4\rtl\case4_rgb_frontend.sv',
    'case4\rtl\gray_bt601_stream.sv',
    'case4\rtl\gray_rgb_stream.sv',
    'case4\rtl\case4_gray_sobel_core.sv',
    'case4\rtl\case4_gray_median_sobel_core.sv',
    'case4\tb\tb_gray_sobel_core.sv',
    'case4\tb\tb_gray_sobel_core_565.sv',
    'case4\tb\tb_hex_core.sv',
    'case4\tb\tb_gray_median_sobel_core.sv')
Invoke-VivadoTool $xelab @('tb_image_operators', '-s', 'case4_tb_operators')
Invoke-VivadoTool $xsim @('case4_tb_operators', '-runall', '-nolog')

Invoke-VivadoTool $xelab @('tb_gray_sobel_core', '-s', 'case4_tb_core')
Invoke-VivadoTool $xsim @('case4_tb_core', '-runall', '-nolog')

Invoke-VivadoTool $xelab @('tb_gray_sobel_core_565', '-s', 'case4_tb_core_565')
Invoke-VivadoTool $xsim @('case4_tb_core_565', '-runall', '-nolog')

Invoke-VivadoTool $xelab @('tb_gray_median_sobel_core', '-s', 'case4_tb_median_sobel')
Invoke-VivadoTool $xsim @('case4_tb_median_sobel', '-runall', '-nolog')

if (-not (Test-Path -LiteralPath 'case4\tb\vectors\metadata.json')) {
    throw 'Python Golden vectors are missing; run case4\generate_rtl_vectors.py first.'
}
Invoke-VivadoTool $xelab @('tb_hex_core', '-s', 'case4_tb_hex')
Invoke-VivadoTool $xsim @('case4_tb_hex', '-runall', '-nolog')

if ($Full640) {
    Invoke-VivadoTool $xvlog @('-sv', 'case4\tb\tb_gray_sobel_core_640.sv')
    Invoke-VivadoTool $xelab @('tb_gray_sobel_core_640', '-s', 'case4_tb_core_640')
    Invoke-VivadoTool $xsim @('case4_tb_core_640', '-runall', '-nolog')
}

Write-Host 'CASE4 XSIM PASS: gray + window/median/Sobel/threshold/overlay + packed cores + Python HEX scoreboard'
