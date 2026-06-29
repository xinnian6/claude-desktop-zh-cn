@echo off
setlocal
if /i not "%~1"=="--elevated" (
  net session >nul 2>nul
  if errorlevel 1 (
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '--elevated' -Verb RunAs"
    exit /b
  )
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "$installRoot=Join-Path $env:LOCALAPPDATA 'Programs\Claude-zh-CN'; $expected=[System.IO.Path]::GetFullPath($installRoot).TrimEnd('\'); if(-not $expected.EndsWith('\Programs\Claude-zh-CN')){ throw 'Unexpected install path: ' + $expected }; Get-Process -Name 'claude' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and ([System.IO.Path]::GetFullPath($_.Path).StartsWith($expected, [System.StringComparison]::OrdinalIgnoreCase)) } | Stop-Process -Force -ErrorAction SilentlyContinue; if(Test-Path -LiteralPath $expected){ Remove-Item -LiteralPath $expected -Recurse -Force }; $links=@((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Claude zh-CN.lnk'),(Join-Path ([Environment]::GetFolderPath('Desktop')) 'Claude-zh-CN.lnk'),(Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Claude zh-CN.lnk'),(Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Claude-zh-CN.lnk')); foreach($link in $links){ if(Test-Path -LiteralPath $link){ Remove-Item -LiteralPath $link -Force } }; Write-Host 'Claude zh-CN uninstalled.'"
exit /b %ERRORLEVEL%
