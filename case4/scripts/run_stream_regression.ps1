param([string]$VivadoBin='D:\vivado\vivado\Vivado\2023.1\bin',[switch]$Small)
$ErrorActionPreference='Stop'
$case4Root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$simRoot=Join-Path $case4Root 'build/stream_sim'
New-Item -ItemType Directory -Path $simRoot -Force | Out-Null
$statusPath=Join-Path $simRoot 'run_status.json'
@{Status='running';Small=[bool]$Small;Started=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8
'[]' | Set-Content -LiteralPath (Join-Path $simRoot 'results.json') -Encoding utf8
$configs=Get-Content -LiteralPath (Join-Path $case4Root 'build/stream_vectors/manifest.json') -Raw | ConvertFrom-Json
$wrappers=[Collections.Generic.List[string]]::new()
$tests=[Collections.Generic.List[object]]::new()
foreach($cfg in $configs) {
    if($Small -and $cfg.width -gt 17){continue}
    # Widened MAG port is checked through all four integrated core variants.
    $widths=if($cfg.width -le 17){@(11,16)}else{@(11)}
    foreach($magWidth in $widths) {
        $name='stream_'+$cfg.name+'_m'+$magWidth
        $dir=(Join-Path $case4Root ('build/stream_vectors/'+$cfg.name)).Replace('\','/')
        $wrappers.Add("module $name; tb_stream_regression #(.W($($cfg.width)),.H($($cfg.height)),.FORMAT($($cfg.fmt)),.MAG($magWidth),.DIRECTORY(`"$dir`"),.CYCLES($($cfg.cycles)),.N0($($cfg.expected[0])),.N1($($cfg.expected[1])),.N2($($cfg.expected[2])),.N3($($cfg.expected[3]))) dut(); endmodule")
        $tests.Add([pscustomobject]@{Name=$name;Expected=$cfg.expected;MagWidth=$magWidth})
    }
}
$wrappers | Set-Content -LiteralPath (Join-Path $simRoot 'stream_configurations.sv') -Encoding utf8
$rtl=Get-ChildItem -LiteralPath (Join-Path $case4Root 'rtl') -Filter '*.sv' | ForEach-Object FullName
$xpm=Join-Path (Split-Path -Parent $VivadoBin) 'data/ip/xpm/xpm_memory/hdl/xpm_memory.sv'
function Invoke-StreamTool([string]$Tool,[string[]]$ToolArgs,[string]$Log) {
    & (Join-Path $VivadoBin $Tool) @ToolArgs 2>&1 | Out-File -LiteralPath $Log -Encoding utf8
    if($LASTEXITCODE -ne 0){Get-Content -LiteralPath $Log -Tail 25;throw "$Tool failed"}
}
$results=[Collections.Generic.List[object]]::new()
Push-Location $simRoot
try {
    Invoke-StreamTool 'xvlog.bat' (@('-sv',$xpm)+$rtl+@((Join-Path $case4Root 'tb/tb_stream_regression.sv'),'stream_configurations.sv')) 'compile.log'
    foreach($test in $tests) {
        Invoke-StreamTool 'xelab.bat' @($test.Name,'-s',$test.Name) ($test.Name+'_elab.log')
        Invoke-StreamTool 'xsim.bat' @($test.Name,'-runall','-nolog') ($test.Name+'.log')
        $log=Get-Content -LiteralPath ($test.Name+'.log') -Raw
        $passes=@(Select-String -LiteralPath ($test.Name+'.log') -Pattern '^STREAM_PASS')
        if($passes.Count -ne 4 -or $log -match '(?im)^(Fatal:|ERROR:)|_FAIL') {throw "Incomplete stream regression: $($test.Name)"}
        $passes | ForEach-Object Line
        $results.Add([pscustomobject]@{Test=$test.Name;Variants=4;Expected=$test.Expected;MagWidth=$test.MagWidth;Log=$test.Name+'.log'})
        $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath results.json -Encoding utf8
    }
} catch {
    @{Status='failed';Small=[bool]$Small;Passed=$results.Count;Error=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8
    throw
} finally {Pop-Location}
if($results.Count -ne $tests.Count -or $tests.Count -eq 0){throw 'Incomplete stream test selection'}
@{Status='complete';Small=[bool]$Small;Passed=$results.Count;Variants=4*$results.Count;Finished=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8
Write-Output "CASE4_STREAM_ALL_PASS tests=$($results.Count) variants=$($results.Count*4)"
