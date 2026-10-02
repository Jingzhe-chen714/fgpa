@echo off
setlocal EnableExtensions
set "PYTHONUTF8=1"
cd /d "%~dp0"
if errorlevel 1 (
    echo Could not open the app folder. Copy the complete host_app folder to a local directory.
    pause
    exit /b 1
)
if not exist ".venv\Scripts\python.exe" (
    call "%~dp0setup.bat"
    if errorlevel 1 exit /b 1
)
".venv\Scripts\python.exe" -c "import PySide6, serial" >nul 2>&1
if errorlevel 1 (
    echo Dependencies are missing or unavailable. Run setup.bat and try again.
    pause
    exit /b 1
)
".venv\Scripts\python.exe" -m sobel_host %*
if errorlevel 1 (
    echo.
    echo The app stopped with an error. Keep the messages above for troubleshooting.
    echo Run setup.bat if dependencies have changed. See README.md for more help.
    pause
    exit /b 1
)
exit /b 0
