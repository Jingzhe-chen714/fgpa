param(
    [string]$VivadoBin = 'D:\vivado\vivado\Vivado\2023.1\bin',
    [string]$Python = 'C:\Users\30982\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)

$ErrorActionPreference = 'Stop'
$casePath = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$simPath = Join-Path $PSScriptRoot 'xsim'
New-Item -ItemType Directory -Path $simPath -Force | Out-Null

function Invoke-Logged {
    param([string]$Exe, [string[]]$ToolArguments, [string]$Name, [string]$PassPattern = '')
    $logPath = Join-Path $PSScriptRoot ($Name + '.log')
    & $Exe @ToolArguments 2>&1 | Tee-Object -FilePath $logPath
    if ($LASTEXITCODE -ne 0) { throw "$Name exited with $LASTEXITCODE" }
    if ($PassPattern -and -not (Select-String -LiteralPath $logPath -Pattern $PassPattern -Quiet)) {
        throw "$Name completed without required PASS marker"
    }
}

Push-Location -LiteralPath $casePath
try {
    Invoke-Logged -Exe $Python -ToolArguments @('-B', '-X', 'utf8', 'test_golden.py') -Name 'golden_tests' -PassPattern '5 Golden tests passed'
    Invoke-Logged -Exe $Python -ToolArguments @('-B', '-X', 'utf8', 'verify_fixed_gray.py', '--json', (Join-Path $PSScriptRoot 'fixed_gray_report.json')) -Name 'fixed_gray' -PassPattern 'Fixed gray conversion: PASS'
} finally {
    Pop-Location
}

$rtlFiles = Get-ChildItem -LiteralPath (Join-Path $casePath 'rtl') -File -Filter '*.sv' | Sort-Object Name | ForEach-Object FullName
$tbFiles = Get-ChildItem -LiteralPath (Join-Path $casePath 'tb') -File -Filter '*.sv' | Sort-Object Name | ForEach-Object FullName
$xpmPath = Join-Path (Split-Path -Parent $VivadoBin) 'data\ip\xpm\xpm_memory\hdl\xpm_memory.sv'
if (-not (Test-Path -LiteralPath $xpmPath)) { throw 'Vivado XPM source not found' }

# The original HEX testbench has a fixed relative input path. Stage only its
# existing input vectors inside this isolated simulator working directory.
$vectorDestination = Join-Path $simPath 'case4\tb\vectors'
New-Item -ItemType Directory -Path $vectorDestination -Force | Out-Null
foreach ($vectorFile in Get-ChildItem -LiteralPath (Join-Path $casePath 'tb\vectors') -File -Filter '*.hex') {
    Copy-Item -LiteralPath $vectorFile.FullName -Destination (Join-Path $vectorDestination $vectorFile.Name)
}

$testTops = @(
    'tb_gray_rgb',
    'tb_image_operators',
    'tb_gray_sobel_core',
    'tb_gray_sobel_core_565',
    'tb_hex_core',
    'tb_gray_median_sobel_core',
    'tb_gray_sobel_core_640',
    'tb_window3x3_gray_xilinx_bram',
    'tb_gray_sobel_core_xilinx_bram',
    'tb_gray_median_sobel_core_xilinx_bram',
    'tb_gray_sobel_core_xilinx_bram_640',
    'tb_gray_median_sobel_core_xilinx_bram_640'
)

Push-Location -LiteralPath $simPath
try {
    Invoke-Logged -Exe (Join-Path $VivadoBin 'xvlog.bat') -ToolArguments (@('-sv', $xpmPath) + $rtlFiles + $tbFiles) -Name 'xvlog'
    foreach ($testTop in $testTops) {
        $snapshot = 'report_' + $testTop
        Invoke-Logged -Exe (Join-Path $VivadoBin 'xelab.bat') -ToolArguments @($testTop, '-s', $snapshot) -Name ($testTop + '_elab')
        Invoke-Logged -Exe (Join-Path $VivadoBin 'xsim.bat') -ToolArguments @($snapshot, '-runall', '-nolog') -Name $testTop -PassPattern 'PASS'
    }
} finally {
    Pop-Location
}
Write-Output 'REPORT VERIFICATION PASS: five Golden checks, exhaustive fixed gray, and twelve existing XSIM test tops.'
