@echo off
setlocal EnableExtensions
call "%~dp0start.bat" --simulate %*
exit /b %errorlevel%
