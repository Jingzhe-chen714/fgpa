param(
    [Parameter(Mandatory=$true)][string]$PythonPath,
    [Parameter(Mandatory=$true)][string]$WorkingDirectory,
    [Parameter(Mandatory=$true)][string]$LogPath,
    [Parameter(Mandatory=$true)][string]$StatusPath,
    [Parameter(Mandatory=$true)][string]$ToolCommandLine
)

$ErrorActionPreference = 'Stop'
$toolPython = (Resolve-Path -LiteralPath $PythonPath).Path
$toolWorker = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'run_detached_tool.py')).Path
$toolWorkDir = (Resolve-Path -LiteralPath $WorkingDirectory).Path
$toolLog = [IO.Path]::GetFullPath($LogPath)
$toolStatus = [IO.Path]::GetFullPath($StatusPath)
foreach ($toolOutput in @($toolLog, $toolStatus)) {
    if (Test-Path -LiteralPath $toolOutput) { throw "Refusing to overwrite: $toolOutput" }
    if (-not (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($toolOutput)) -PathType Container)) {
        throw "Missing output directory: $toolOutput"
    }
}
if ($toolLog -eq $toolStatus) { throw 'Log and status paths must differ.' }
$toolArgs = @($toolPython, $toolWorker, '--worker', '--cwd', $toolWorkDir,
              '--log', $toolLog, '--status', $toolStatus, '--')
$toolPrefix = ($toolArgs | ForEach-Object {
    if ($_.Contains('"')) { throw 'Embedded quotes are not allowed in paths.' }
    '"' + $_.TrimEnd('\') + '"'
}) -join ' '
$toolStartup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0}
$toolResult = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
    CommandLine = $toolPrefix + ' ' + $ToolCommandLine
    CurrentDirectory = $toolWorkDir
    ProcessStartupInformation = $toolStartup
}
if ($toolResult.ReturnValue -ne 0) {
    throw "Win32_Process.Create failed: $($toolResult.ReturnValue)"
}
[pscustomobject]@{WorkerPid=$toolResult.ProcessId;Log=$toolLog;Status=$toolStatus}
