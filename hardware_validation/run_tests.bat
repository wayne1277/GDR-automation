@echo off
setlocal
title Hardware Validation Tests
cd /d "%~dp0"

:: Self-elevate to Administrator (needed for adapter disable/enable)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cls
echo.
echo  ============================================================
echo   HARDWARE VALIDATION TEST SUITE
echo  ============================================================
echo   Running automated tests...
echo   Report will open automatically when done.
echo  ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0hw_tests.ps1"

echo.
echo  Press any key to exit.
pause > nul
