@echo off
setlocal EnableExtensions
set "PYTHONUTF8=1"
cd /d "%~dp0"
if errorlevel 1 goto directory_error

if exist ".venv\Scripts\python.exe" goto validate_environment

py -3.12 -c "import sys; sys.exit(sys.version_info < (3, 10))" >nul 2>&1
if not errorlevel 1 (
    set "SOBEL_PYTHON=py -3.12"
    goto create_environment
)
py -3.11 -c "import sys; sys.exit(sys.version_info < (3, 10))" >nul 2>&1
if not errorlevel 1 (
    set "SOBEL_PYTHON=py -3.11"
    goto create_environment
)
py -3 -c "import sys; sys.exit(sys.version_info < (3, 10))" >nul 2>&1
if not errorlevel 1 (
    set "SOBEL_PYTHON=py -3"
    goto create_environment
)
python -c "import sys; sys.exit(sys.version_info < (3, 10))" >nul 2>&1
if not errorlevel 1 (
    set "SOBEL_PYTHON=python"
    goto create_environment
)
echo Python 3.10 or newer was not found. Python 3.11 or 3.12 is recommended.
echo Install Python from https://www.python.org/downloads/windows/ and enable the launcher or PATH option.
echo Then run setup.bat again. Administrator privileges are not required.
goto failed

:create_environment
echo Creating the local Python environment...
%SOBEL_PYTHON% -m venv ".venv"
if errorlevel 1 (
    echo Could not create .venv. Check the Python installation and folder permissions.
    goto failed
)

:validate_environment
".venv\Scripts\python.exe" -c "import sys; sys.exit(sys.version_info < (3, 10))" >nul 2>&1
if errorlevel 1 (
    echo The existing .venv is unavailable or uses Python older than 3.10.
    echo Rename this folder's .venv directory, then run setup.bat again.
    goto failed
)
echo Installing the app dependencies in this folder's .venv...
".venv\Scripts\python.exe" -m pip install -r "%~dp0requirements.txt"
if errorlevel 1 (
    echo Dependency installation failed. Check the messages above and your network connection.
    echo Run setup.bat again after fixing the issue. See README.md for help.
    goto failed
)
echo.
echo Setup complete. Run start_simulation.bat for the simulator or start.bat for a real serial port.
exit /b 0

:directory_error
echo Could not open the app folder. Extract or copy the complete host_app folder to a local writable directory.
:failed
echo.
pause
exit /b 1
