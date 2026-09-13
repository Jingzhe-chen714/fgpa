param(
    [string]$VivadoBin='D:\vivado\vivado\Vivado\2023.1\bin',
    [string]$BuildName='core_fixes',
    [string]$TestFilter='*'
)
$ErrorActionPreference='Stop'
$case4Root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$buildRoot=Join-Path $case4Root ('build/'+$BuildName)
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
$statusPath=Join-Path $buildRoot 'run_status.json'
@{Status='running';Filter=$TestFilter;Started=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8
'[]' | Set-Content -LiteralPath (Join-Path $buildRoot 'results.json') -Encoding utf8
$cases=[Collections.Generic.List[object]]::new()
$wrappers=[Collections.Generic.List[string]]::new()
function Add-Case([string]$Name,[string]$Module,[string]$Parameters,[string]$Marker,[bool]$Negative=$false) {
    $wrappers.Add("module $Name; $Module $Parameters dut(); endmodule")
    $cases.Add([pscustomobject]@{Name=$Name;Marker=$Marker;Negative=$Negative})
}
foreach($top in @('tb_gray_rgb','tb_gray_sobel_core','tb_gray_sobel_core_565','tb_gray_median_sobel_core',
                 'tb_gray_sobel_core_xilinx_bram','tb_gray_median_sobel_core_xilinx_bram','tb_window3x3_gray_xilinx_bram',
                 'tb_image_operators','tb_case4_sobel_extremes','tb_case4_sobel_edge_ops','tb_hex_core','tb_reference_sanity',
                 'tb_reset_primitives','tb_gray_stream','tb_window3x3_median')) {
    $parameters=''
    if($top -eq 'tb_hex_core') { $parameters='#(.DEFAULT_VECTOR_DIR("'+$case4Root.Replace('\','/')+'/tb/vectors"))' }
    Add-Case ('fix_'+$top) $top $parameters 'PASS'
}
Add-Case 'fix_width_default' 'tb_sobel_widths' '' 'SOBEL_WIDTH_PASS'
Add-Case 'fix_width_minimum' 'tb_sobel_widths' '#(.P(8),.PART(10),.GRAD(11),.MAG(11))' 'SOBEL_WIDTH_PASS'
Add-Case 'fix_width_16' 'tb_sobel_widths' '#(.MAG(16))' 'SOBEL_WIDTH_PASS'
Add-Case 'fix_width_32' 'tb_sobel_widths' '#(.PART(16),.GRAD(24),.MAG(32))' 'SOBEL_WIDTH_PASS'
Add-Case 'fix_width_pixel4' 'tb_sobel_widths' '#(.P(4))' 'SOBEL_WIDTH_PASS'
Add-Case 'fix_width_pixel12' 'tb_sobel_widths' '#(.P(12),.MAG(16))' 'SOBEL_WIDTH_PASS'
Add-Case 'fix_width_pixel1' 'tb_sobel_widths' '#(.P(1))' 'SOBEL_WIDTH_PASS'
foreach($pixelBits in @(1,8,12)) {
    Add-Case ('fix_median_'+$pixelBits) 'tb_median_pipeline' "#(.P($pixelBits))" 'MEDIAN_PIPELINE_PASS'
}
for($fault=0;$fault -lt 6;$fault++) {
    $marker=if($fault -lt 4){'CHECKER_REJECT_X_DATA'}else{'CHECKER_REJECT_X_CONTROL'}
    Add-Case ('fix_checker_'+$fault) 'tb_checker_faults' "#(.FAULT($fault))" $marker $true
}
$guards=@('MAG_W','PART_W','GRAD_W','FORMAT','FORMAT','MEDIAN_SIZE','COORD','WINDOW_SIZE','BACKEND','MEDIAN_PIPE','MEDIAN_PIPE','OVERLAY_RGB','COORD','MAG_W')
for($bad=0;$bad -lt $guards.Count;$bad++) {
    $marker='CASE4_PARAM_'+$guards[$bad]+':'
    # W=4 violates BOTH the cascade minimum and its W-2 second window's
    # minimum. Time-zero initial-block order may report either exact cause.
    if($bad -eq 5){$marker='CASE4_PARAM_MEDIAN_SIZE:|CASE4_PARAM_WINDOW_SIZE:'}
    Add-Case ('fix_guard_'+$bad) 'tb_parameter_guards' "#(.BAD($bad))" $marker $true
}
# Generated parameter wrappers avoid Windows .bat argument parsing of '='.
$wrappers | Set-Content -LiteralPath (Join-Path $buildRoot 'test_configurations.sv') -Encoding utf8
$rtl=@(Get-ChildItem -LiteralPath (Join-Path $case4Root 'rtl') -Filter '*.sv' | ForEach-Object FullName)
$benches=@(Get-ChildItem -LiteralPath (Join-Path $case4Root 'tb') -Filter '*.sv' | ForEach-Object FullName)
$benches+=@(Get-ChildItem -LiteralPath (Join-Path $case4Root 'rtl/tb') -Filter '*.sv' | ForEach-Object FullName)
$xpm=Join-Path (Split-Path -Parent $VivadoBin) 'data/ip/xpm/xpm_memory/hdl/xpm_memory.sv'
function Invoke-Compile([string]$Tool,[string[]]$ToolArgs,[string]$Log) {
    & (Join-Path $VivadoBin $Tool) @ToolArgs 2>&1 | Out-File -LiteralPath $Log -Encoding utf8
    if($LASTEXITCODE -ne 0){Get-Content -LiteralPath $Log -Tail 20;throw "$Tool failed"}
}
$results=[Collections.Generic.List[object]]::new()
Push-Location $buildRoot
try {
    Invoke-Compile 'xvlog.bat' (@('-sv',$xpm)+$rtl+$benches+@('test_configurations.sv')) 'compile.log'
    foreach($test in $cases) {
        if($test.Name -notlike $TestFilter){continue}
        Invoke-Compile 'xelab.bat' @($test.Name,'-s',$test.Name) ($test.Name+'_elab.log')
        $case4Args=@($test.Name,'-runall','-nolog')
        & (Join-Path $VivadoBin 'xsim.bat') @case4Args 2>&1 | Out-File ($test.Name+'.log') -Encoding utf8
        $simExit=$LASTEXITCODE
        $output=Get-Content -LiteralPath ($test.Name+'.log') -Raw
        if($test.Negative) {
            # Only the intended parameter/checker fatal counts, not any crash.
            $expectedPattern=($test.Marker.Split('|') | ForEach-Object {[regex]::Escape($_)}) -join '|'
            if($output -notmatch ('Fatal:.*(?:'+$expectedPattern+')')) {
                Write-Output $output;throw "Expected rejection missing: $($test.Name)"
            }
            $result='EXPECTED_REJECTION'
        } else {
            if($simExit -ne 0 -or $output -notmatch $test.Marker -or $output -match '(?im)^(Fatal:|ERROR:|ERROR |FAIL:)|_FAIL') {
                Write-Output $output;throw "Regression failed: $($test.Name)"
            }
            $result='PASS'
        }
        Write-Output "$result $($test.Name)"
        $results.Add([pscustomobject]@{Test=$test.Name;Result=$result;Marker=$test.Marker;Log=$test.Name+'.log'})
        $results | ConvertTo-Json | Set-Content -LiteralPath results.json -Encoding utf8
    }
} catch {
    @{Status='failed';Filter=$TestFilter;Passed=$results.Count;Error=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8
    throw
} finally {Pop-Location}
if($results.Count -eq 0){throw 'No tests matched the requested filter'}
@{Status='complete';Filter=$TestFilter;FullSuite=($TestFilter -eq '*');Passed=$results.Count;Finished=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8
Write-Output "CASE4_CORE_FIXES_ALL_PASS tests=$($results.Count)"
