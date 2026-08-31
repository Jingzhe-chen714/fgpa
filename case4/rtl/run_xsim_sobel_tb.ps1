$ErrorActionPreference = 'Stop'

# Kept as a backwards-compatible entry point.  The old agent-local testbench
# path was replaced by the project-level regression so that all operators are
# checked together and no stale path is required.
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
& (Join-Path $root 'case4\scripts\run_xsim.ps1') -VivadoBin 'D:\vivado\vivado\Vivado\2023.1\bin'
if ($LASTEXITCODE -ne 0) { throw "case4 XSIM regression failed with exit code $LASTEXITCODE" }
