@echo off
setlocal
if /i not "%~1"=="--elevated" (
  net session >nul 2>nul
  if errorlevel 1 (
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '--elevated' -Verb RunAs"
    exit /b
  )
)
set "TOOL_ROOT=%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "$root=$env:TOOL_ROOT; $script=Get-ChildItem -LiteralPath $root -Filter 'FixCoworkWorkspacePermission.ps1' -Recurse -File | Select-Object -First 1; if(-not $script){ throw 'Cannot find FixCoworkWorkspacePermission.ps1. Please keep all files in this folder.' }; & $script.FullName"
exit /b %ERRORLEVEL%
