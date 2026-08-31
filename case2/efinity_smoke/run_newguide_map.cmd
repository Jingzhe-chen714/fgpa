@echo off
call D:\ELS\Efinity\2026.1\bin\setup.bat
if errorlevel 1 exit /b %errorlevel%
set CASE2_MAP_PROJECT=case2_rtl_probe_newguide_final
set CASE2_MAP_OUTPUT=outflow_sv_newguide_final
if not "%~1"=="" set "CASE2_MAP_PROJECT=%~1"
if not "%~2"=="" set "CASE2_MAP_OUTPUT=%~2"
python D:\ELS\Efinity\2026.1\scripts\efx_run_map.py %CASE2_MAP_PROJECT% --family Titanium --device Ti60F225 --flist case2_rtl_all.f --output_dir %CASE2_MAP_OUTPUT% --opt root=case2_rtl_probe_top_full
exit /b %errorlevel%
