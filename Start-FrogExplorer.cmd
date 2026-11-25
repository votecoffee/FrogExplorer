@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_windows.ps1" %*
set "FROG_LAUNCH_EXIT=%errorlevel%"
if not "%FROG_LAUNCH_EXIT%"=="0" pause
exit /b %FROG_LAUNCH_EXIT%
