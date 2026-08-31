$ErrorActionPreference = 'Stop'
$vivadoBin = 'D:\vivado\vivado\Vivado\2023.1\bin'
$rtl = Join-Path $PSScriptRoot '..'

# Keep xvlog/xelab/xsim generated databases next to this testbench rather than
# in the project root.  This also makes the script independent of the caller's
# current working directory.
Push-Location $PSScriptRoot
try {

& (Join-Path $vivadoBin 'xvlog.bat') -sv `
    (Join-Path $rtl 'window3x3_gray.sv') `
    (Join-Path $rtl 'median3x3_u8.sv') `
    (Join-Path $rtl 'window3x3_median.sv') `
    (Join-Path $PSScriptRoot 'tb_window3x3_median.sv')
if ($LASTEXITCODE -ne 0) { throw "xvlog failed: $LASTEXITCODE" }

& (Join-Path $vivadoBin 'xelab.bat') tb_window3x3_median -s tb_window3x3_median_sim
if ($LASTEXITCODE -ne 0) { throw "xelab failed: $LASTEXITCODE" }

& (Join-Path $vivadoBin 'xsim.bat') tb_window3x3_median_sim -runall
if ($LASTEXITCODE -ne 0) { throw "xsim failed: $LASTEXITCODE" }
} finally {
    Pop-Location
}
