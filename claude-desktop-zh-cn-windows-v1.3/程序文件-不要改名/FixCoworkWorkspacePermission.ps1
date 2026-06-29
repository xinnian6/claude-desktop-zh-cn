$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function Write-Info([string]$Message) {
  Write-Host "[Claude Cowork Fix] $Message"
}

$bundle = Join-Path $env:LOCALAPPDATA 'Claude-3p\vm_bundles\claudevm.bundle'
if (-not (Test-Path -LiteralPath $bundle)) {
  throw "Claude Cowork workspace bundle not found: $bundle"
}

Write-Info "Workspace bundle: $bundle"
Write-Info 'Stopping Claude if it is running.'
Get-Process -Name 'claude' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 700

$icacls = Join-Path $env:WINDIR 'System32\icacls.exe'
if (-not (Test-Path -LiteralPath $icacls)) {
  throw "icacls.exe not found: $icacls"
}

Write-Info 'Granting access to Windows virtual machine accounts.'
& $icacls $bundle /grant '*S-1-5-83-0:(OI)(CI)F' /T
if ($LASTEXITCODE -ne 0) {
  throw "icacls failed with exit code $LASTEXITCODE"
}

$rootfs = Join-Path $bundle 'rootfs.vhdx'
if (Test-Path -LiteralPath $rootfs) {
  Write-Info 'Current rootfs.vhdx permissions:'
  & $icacls $rootfs
}

Write-Info 'Done. Start Claude again and try Cowork.'
