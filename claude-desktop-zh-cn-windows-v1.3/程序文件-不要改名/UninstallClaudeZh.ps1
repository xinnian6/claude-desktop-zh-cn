$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function Write-Info([string]$Message) {
  Write-Host "[Claude zh-CN Uninstall] $Message"
}

function Get-NormalizedFullPath([string]$Path) {
  return ([System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/'))
}

function Set-ClaudeLocale([string]$Locale) {
  $configDir = Join-Path $env:LOCALAPPDATA 'Claude-3p'
  [System.IO.Directory]::CreateDirectory($configDir) | Out-Null
  $configPath = Join-Path $configDir 'config.json'

  if (Test-Path -LiteralPath $configPath) {
    $raw = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
      $config = [pscustomobject]@{}
    } else {
      $config = $raw | ConvertFrom-Json
    }
  } else {
    $config = [pscustomobject]@{}
  }

  if ($config.PSObject.Properties.Name -contains 'locale') {
    $config.locale = $Locale
  } else {
    $config | Add-Member -NotePropertyName 'locale' -NotePropertyValue $Locale
  }

  $json = $config | ConvertTo-Json -Depth 20
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($configPath, $json + [Environment]::NewLine, $utf8NoBom)
  return $configPath
}

if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
  throw 'LOCALAPPDATA environment variable was not found.'
}

$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\Claude-zh-CN'
$expected = Get-NormalizedFullPath $installRoot
if (-not $expected.EndsWith('\Programs\Claude-zh-CN', [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Unexpected install path: $expected"
}

Write-Info "Install root: $expected"
$processes = @(Get-Process -Name 'claude' -ErrorAction SilentlyContinue | Where-Object {
  $_.Path -and (Get-NormalizedFullPath $_.Path).StartsWith($expected, [System.StringComparison]::OrdinalIgnoreCase)
})
if ($processes.Count -gt 0) {
  Write-Info 'Stopping running zh-CN Claude process.'
  $processes | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 700
}

if (Test-Path -LiteralPath $expected) {
  Write-Info 'Removing zh-CN app copy.'
  Remove-Item -LiteralPath $expected -Recurse -Force
} else {
  Write-Info 'zh-CN app copy was not found; skipping app folder removal.'
}

$shortcutDirs = @(
  [Environment]::GetFolderPath('Desktop'),
  (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

$shell = New-Object -ComObject WScript.Shell
foreach ($shortcutDir in $shortcutDirs) {
  Get-ChildItem -LiteralPath $shortcutDir -Filter '*.lnk' -File -ErrorAction SilentlyContinue | ForEach-Object {
    try {
      $shortcut = $shell.CreateShortcut($_.FullName)
      if ($shortcut.TargetPath -and (Get-NormalizedFullPath $shortcut.TargetPath).StartsWith($expected, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $_.FullName -Force
        Write-Info "Removed shortcut: $($_.FullName)"
      }
    } catch {
    }
  }
}

$configPath = Set-ClaudeLocale 'en-US'
Write-Info "Locale preference set to en-US: $configPath"
Write-Info 'Done. Official Claude Desktop was not uninstalled.'