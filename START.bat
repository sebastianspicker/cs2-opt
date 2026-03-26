@echo off
setlocal
title CS2 Optimization Suite

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo  Starting as administrator...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:menu
cls
echo.
echo  =============================================
echo   CS2 OPTIMIZATION SUITE
echo   Tier System: T1=Auto T2=Prompt T3=Control
echo  =============================================
echo.
echo   [1]  Start / resume optimization
echo        (Phase 1 + 2 + 3)
echo.
echo   [2]  Cleanup / Soft-Reset
echo        (Shader Cache, Temp, DNS, ...)
echo.
echo   [3]  FPS Cap Calculator
echo        (Evaluate benchmark output)
echo.
echo   [4]  Show current log
echo.
echo   [5]  Reset progress
echo.
echo   [6]  Verify settings
echo        (Check registry keys after Windows Update)
echo.
echo   [7]  Restore / Rollback
echo        (Undo changes from specific steps)
echo.
echo   [8]  Backup summary
echo        (Show what was backed up before changes)
echo.
echo   [P]  Post-Reboot Setup (Phase 3)
echo        (Manual start if auto-start failed)
echo.
echo   [9]  Exit
echo.
set /p choice="  Choice [1-9/P]: "

if "%choice%"=="1" goto :phase1
if "%choice%"=="2" goto :cleanup
if "%choice%"=="3" goto :fpscap
if "%choice%"=="4" goto :showlog
if "%choice%"=="5" goto :resetprogress
if "%choice%"=="6" goto :verify
if "%choice%"=="7" goto :restore
if "%choice%"=="8" goto :backupsummary
if /i "%choice%"=="P" goto :phase3
if "%choice%"=="9" exit /b
goto :menu

:phase1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Optimize.ps1"
pause
goto :menu

:cleanup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Cleanup.ps1"
pause
goto :menu

:fpscap
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FpsCap-Calculator.ps1"
pause
goto :menu

:showlog
if not exist "C:\CS2_OPTIMIZE\Logs\optimize_current.log" (
    echo  No log found.
    pause
    goto :menu
)
powershell -Command "Get-Content 'C:\CS2_OPTIMIZE\Logs\optimize_current.log' | more"
pause
goto :menu

:verify
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Verify-Settings.ps1"
pause
goto :menu

:resetprogress
echo.
echo  Progress file will be deleted.
set /p confirm="  Are you sure? [y/N]: "
if /i "%confirm%"=="y" (
    if exist "C:\CS2_OPTIMIZE\progress.json" del "C:\CS2_OPTIMIZE\progress.json"
    echo  Reset complete.
)
if /i "%confirm%"=="j" (
    if exist "C:\CS2_OPTIMIZE\progress.json" del "C:\CS2_OPTIMIZE\progress.json"
    echo  Reset complete.
)
pause
goto :menu

:restore
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Set-StrictMode -Version Latest; $ScriptRoot='%~dp0'.TrimEnd('\'); . '%~dp0config.env.ps1'; . '%~dp0helpers.ps1'; Initialize-ScriptDefaults; Restore-Interactive"
pause
goto :menu

:backupsummary
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Set-StrictMode -Version Latest; $ScriptRoot='%~dp0'.TrimEnd('\'); . '%~dp0config.env.ps1'; . '%~dp0helpers.ps1'; Initialize-ScriptDefaults; Show-BackupSummary"
pause
goto :menu

:phase3
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PostReboot-Setup.ps1"
pause
goto :menu
