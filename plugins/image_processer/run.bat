@echo off
:: Orbby Image Processor - Launch Script
:: This script uses a virtual drive to work around Windows MAX_PATH limit

echo === Orbby Image Processor ===

:: Remove any existing P: mapping
subst P: /d >nul 2>&1

:: Map project directory to P:
subst P: "%~dp0"
if %errorlevel% neq 0 (
    echo Failed to create virtual drive. Run as administrator or enable long paths.
    pause
    exit /b 1
)

:: Run from the shorter path
cd /d P:\example
echo Starting application...
echo.

:: Run the app (pass through all args)
flutter run -d windows %*

:: Cleanup
echo.
echo Cleaning up...
cd /d "%~dp0"
subst P: /d >nul 2>&1
pause
