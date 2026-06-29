param(
  [switch]$Restore
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$ScriptPath = $MyInvocation.MyCommand.Path
$ToolDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LocaleFile = Join-Path $ToolDir 'zh-CN.json'
$WebI18nDir = Join-Path $ToolDir 'web-i18n'
$PackageRoot = $ToolDir
$ParentDir = Split-Path -Parent $ToolDir
if ($ParentDir -and ((Get-ChildItem -LiteralPath $ParentDir -Filter '*.cmd' -File -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)) {
  $PackageRoot = $ParentDir
}
$Desktop = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($Desktop)) {
  $Desktop = Join-Path $env:USERPROFILE 'Desktop'
}

function Write-Info([string]$Message) {
  Write-Host "[Claude zh-CN] $Message"
}

function Ensure-Directory([string]$Path) {
  [System.IO.Directory]::CreateDirectory($Path) | Out-Null
}

function Get-ClaudeCandidates {
  $seen = @{}
  $items = New-Object System.Collections.ArrayList

  Get-Process -Name 'claude' -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Path) {
      $dir = Split-Path -Parent $_.Path
      if ($dir -and -not $seen.ContainsKey($dir)) {
        $seen[$dir] = $true
        [void]$items.Add($dir)
      }
    }
  }

  $localCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Claude'),
    (Join-Path $env:LOCALAPPDATA 'Claude'),
    (Join-Path $env:LOCALAPPDATA 'Claude-3p')
  )

  foreach ($base in $localCandidates) {
    if (Test-Path -Path $base) {
      if (Test-Path -Path (Join-Path $base 'claude.exe')) {
        if (-not $seen.ContainsKey($base)) {
          $seen[$base] = $true
          [void]$items.Add($base)
        }
      }
      Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $dir = $_.FullName
        if (Test-Path -Path (Join-Path $dir 'claude.exe')) {
          if (-not $seen.ContainsKey($dir)) {
            $seen[$dir] = $true
            [void]$items.Add($dir)
          }
        }
      }
    }
  }

  $fixedCopyRoot = Get-ClaudeZhInstallRoot
  $fixedCopyWindowsApps = Join-Path $fixedCopyRoot 'WindowsApps'
  if (Test-Path -Path $fixedCopyWindowsApps) {
    Get-ChildItem -Path $fixedCopyWindowsApps -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $dir = Join-Path $_.FullName 'app'
      if (Test-Path -Path (Join-Path $dir 'claude.exe')) {
        if (-not $seen.ContainsKey($dir)) {
          $seen[$dir] = $true
          [void]$items.Add($dir)
        }
      }
    }
  }

  Get-AppxPackage -Name 'Claude' -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.InstallLocation) {
      $dir = Join-Path $_.InstallLocation 'app'
      if (Test-Path -Path (Join-Path $dir 'claude.exe')) {
        if (-not $seen.ContainsKey($dir)) {
          $seen[$dir] = $true
          [void]$items.Add($dir)
        }
      }
    }
  }

  if (Test-Path -Path $Desktop) {
    Get-ChildItem -Path $Desktop -Directory -Filter 'Claude-zh-CN-*' -ErrorAction SilentlyContinue | ForEach-Object {
      $windowsAppsDir = Join-Path $_.FullName 'WindowsApps'
      if (Test-Path -Path $windowsAppsDir) {
        Get-ChildItem -Path $windowsAppsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
          $dir = Join-Path $_.FullName 'app'
          if (Test-Path -Path (Join-Path $dir 'claude.exe')) {
            if (-not $seen.ContainsKey($dir)) {
              $seen[$dir] = $true
              [void]$items.Add($dir)
            }
          }
        }
      }
    }
  }

  $windowsApps = Join-Path $env:ProgramFiles 'WindowsApps'
  if (Test-Path -Path $windowsApps) {
    Get-ChildItem -Path $windowsApps -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | ForEach-Object {
      $dir = Join-Path $_.FullName 'app'
      if (Test-Path -Path (Join-Path $dir 'claude.exe')) {
        if (-not $seen.ContainsKey($dir)) {
          $seen[$dir] = $true
          [void]$items.Add($dir)
        }
      }
    }
  }

  $items | Where-Object {
    (Test-Path -Path (Join-Path $_ 'claude.exe')) -and
    (Test-Path -Path (Join-Path $_ 'resources\en-US.json'))
  }
}

function Get-ClaudeInstall {
  $candidates = @(Get-ClaudeCandidates)
  if ($candidates.Count -eq 0) {
    throw 'Claude Desktop install directory was not found. Install and run Claude once, then retry.'
  }

  $windowsAppsRoot = Join-Path $env:ProgramFiles 'WindowsApps'
  $ranked = $candidates | ForEach-Object {
    $versionFile = Join-Path $_ 'version'
    $versionText = ''
    if (Test-Path -Path $versionFile) {
      $versionText = (Get-Content -Path $versionFile -Raw -Encoding UTF8).Trim()
    }
    [pscustomobject]@{
      AppDir = $_
      Version = $versionText
      IsWindowsApps = $_.StartsWith($windowsAppsRoot, [StringComparison]::OrdinalIgnoreCase)
      IsGeneratedCopy = Test-IsClaudeZhGeneratedPath $_
    }
  } | Sort-Object -Property @{Expression='Version';Descending=$true}, @{Expression='IsGeneratedCopy';Descending=$false}, @{Expression='IsWindowsApps';Descending=$true}

  $ranked | Select-Object -First 1
}

function Get-ClaudePackageFolderName([string]$AppDir) {
  $parts = $AppDir -split '[\\/]'
  for ($i = 0; $i -lt $parts.Count; $i++) {
    if ($parts[$i].ToLowerInvariant() -eq 'windowsapps' -and $i + 1 -lt $parts.Count) {
      return $parts[$i + 1]
    }
  }
  return 'Claude_zh-CN_x64__pzs8sxrjxfjjc'
}

function Get-ClaudeZhInstallRoot {
  if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    throw 'LOCALAPPDATA environment variable was not found.'
  }
  return (Join-Path $env:LOCALAPPDATA 'Programs\Claude-zh-CN')
}

function Get-NormalizedFullPath([string]$Path) {
  return ([System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/'))
}

function Remove-ClaudeZhInstallRoot([string]$TargetRoot) {
  $expected = Get-NormalizedFullPath (Get-ClaudeZhInstallRoot)
  $target = Get-NormalizedFullPath $TargetRoot
  if (-not $target.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove unexpected install path: $TargetRoot"
  }
  if (Test-Path -LiteralPath $target) {
    Write-Info "Removing existing zh-CN app copy: $target"
    Remove-Item -LiteralPath $target -Recurse -Force
  }
}

function Test-IsClaudeZhGeneratedPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $false
  }

  $normalized = $Path -replace '/', '\'
  $lower = $normalized.ToLowerInvariant()
  $installRoot = (Get-ClaudeZhInstallRoot) -replace '/', '\'
  if ($normalized.StartsWith($installRoot, [StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  return (
    $lower.Contains('\claude-zh-cn\') -or
    $lower.Contains('\claude-zh-cn-') -or
    $lower.Contains('\claude-cowork')
  )
}

function Test-CanWrite([string]$Dir) {
  try {
    $probe = Join-Path $Dir ('.claude-zh-write-test-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    [System.IO.File]::WriteAllText($probe, 'test', [System.Text.Encoding]::UTF8)
    [System.IO.File]::Delete($probe)
    return $true
  } catch {
    return $false
  }
}

function Get-StringSha256([string]$Text) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
  } finally {
    $sha.Dispose()
  }
}

function Get-FileSha256([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    return ''
  }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $stream = [System.IO.File]::OpenRead($Path)
  try {
    return -join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') })
  } finally {
    $stream.Dispose()
    $sha.Dispose()
  }
}

function Get-ClaudeBackupFingerprint([string]$AppDir) {
  $versionPath = Join-Path $AppDir 'version'
  $version = ''
  if (Test-Path -Path $versionPath) {
    $version = (Get-Content -Path $versionPath -Raw -Encoding UTF8).Trim()
  }

  $appAsar = Join-Path (Join-Path $AppDir 'resources') 'app.asar'
  $asarLength = 0
  $asarWriteTimeUtc = ''
  if (Test-Path -Path $appAsar) {
    $asar = Get-Item -Path $appAsar
    $asarLength = [int64]$asar.Length
    $asarWriteTimeUtc = $asar.LastWriteTimeUtc.ToString('o')
  }

  return [pscustomobject]@{
    Version = $version
    AppAsarLength = $asarLength
    AppAsarLastWriteTimeUtc = $asarWriteTimeUtc
  }
}

function Test-ClaudeBackupCurrent([string]$BackupDir, [string]$AppDir, $Fingerprint) {
  $manifestPath = Join-Path $BackupDir 'backup-manifest.json'
  if (-not (Test-Path -Path $manifestPath)) {
    return $false
  }

  try {
    $manifest = Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [string]::Equals([string]$manifest.sourceApp, $AppDir, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $false
    }
    if ([string]$manifest.version -ne [string]$Fingerprint.Version) {
      return $false
    }
    if ([int64]$manifest.appAsarLength -ne [int64]$Fingerprint.AppAsarLength) {
      return $false
    }
    if ([string]$manifest.appAsarLastWriteTimeUtc -ne [string]$Fingerprint.AppAsarLastWriteTimeUtc) {
      return $false
    }
    return $true
  } catch {
    return $false
  }
}

function Backup-Claude([string]$AppDir) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $backupRootName = 'Claude' + [char]0x5907 + [char]0x4EFD
  $finalBackup = Join-Path $PackageRoot $backupRootName
  $fingerprint = Get-ClaudeBackupFingerprint $AppDir

  if (Test-ClaudeBackupCurrent $finalBackup $AppDir $fingerprint) {
    return [pscustomobject]@{
      Path = $finalBackup
      Created = $false
    }
  }

  $backup = Join-Path $PackageRoot "ClaudeBackup-temp-$stamp"
  Ensure-Directory $backup
  Ensure-Directory (Join-Path $backup 'resources-json')
  Ensure-Directory (Join-Path $backup 'userdata')

  $resources = Join-Path $AppDir 'resources'
  if (Test-Path -Path (Join-Path $AppDir 'version')) {
    Copy-Item -Path (Join-Path $AppDir 'version') -Destination (Join-Path $backup 'version') -Force
  }
  if (Test-Path -Path (Join-Path $resources 'app.asar')) {
    Copy-Item -Path (Join-Path $resources 'app.asar') -Destination (Join-Path $backup 'app.asar') -Force
  }
  Copy-Item -Path (Join-Path $resources '*.json') -Destination (Join-Path $backup 'resources-json') -Force

  $config = Join-Path $env:LOCALAPPDATA 'Claude-3p\config.json'
  if (Test-Path -Path $config) {
    Copy-Item -Path $config -Destination (Join-Path $backup 'userdata\config.json') -Force
  }

  $manifest = [ordered]@{
    createdAt = (Get-Date).ToString('o')
    sourceApp = $AppDir
    resources = $resources
    version = $fingerprint.Version
    appAsarLength = $fingerprint.AppAsarLength
    appAsarLastWriteTimeUtc = $fingerprint.AppAsarLastWriteTimeUtc
    note = 'Backup created before applying Claude zh-CN localization.'
  } | ConvertTo-Json -Depth 5
  Set-Content -Path (Join-Path $backup 'backup-manifest.json') -Value $manifest -Encoding UTF8

  if (Test-Path -LiteralPath $finalBackup) {
    Remove-Item -LiteralPath $finalBackup -Recurse -Force
  }
  Rename-Item -LiteralPath $backup -NewName $backupRootName -Force
  return [pscustomobject]@{
    Path = $finalBackup
    Created = $true
  }
}

function Set-ClaudeLocale([string]$Locale) {
  $configDir = Join-Path $env:LOCALAPPDATA 'Claude-3p'
  Ensure-Directory $configDir
  $configPath = Join-Path $configDir 'config.json'

  if (Test-Path -Path $configPath) {
    $raw = Get-Content -Path $configPath -Raw -Encoding UTF8
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

function Write-Utf8NoBom([string]$Path, [string]$Text) {
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Read-JsonObject([string]$Path) {
  Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-JsonPropertyMap($Object) {
  $map = @{}
  foreach ($prop in $Object.PSObject.Properties) {
    $map[$prop.Name] = $prop.Value
  }
  return $map
}

function Get-ManualTranslationValue($Value) {
  if ($null -eq $Value) {
    return $null
  }
  if ($Value -is [string]) {
    return [string]$Value
  }

  foreach ($name in @('中文译文', '当前中文', '中文', 'translation', 'value')) {
    $field = $Value.PSObject.Properties.Item($name)
    if ($null -ne $field -and $null -ne $field.Value) {
      return [string]$field.Value
    }
  }

  return [string]$Value
}

function Test-SameJsonKeys($Left, $Right) {
  $leftNames = @($Left.PSObject.Properties | ForEach-Object { $_.Name })
  $rightMap = @{}
  foreach ($prop in $Right.PSObject.Properties) {
    $rightMap[$prop.Name] = $true
  }
  foreach ($name in $leftNames) {
    if (-not $rightMap.ContainsKey($name)) {
      return $false
    }
  }
  return $leftNames.Count -eq ($Right.PSObject.Properties | Measure-Object).Count
}

function Get-KnownWebLocaleMerge([string]$SourceLocale, [string]$PackagedLocale) {
  $knownFile = Join-Path $WebI18nDir 'known-source-locales.json'
  if (-not (Test-Path -Path $knownFile)) {
    return $null
  }

  $sourceHash = (Get-FileSha256 $SourceLocale).ToLowerInvariant()
  $packagedHash = (Get-FileSha256 $PackagedLocale).ToLowerInvariant()
  try {
    $knownItems = @(Get-Content -Path $knownFile -Raw -Encoding UTF8 | ConvertFrom-Json)
    foreach ($item in $knownItems) {
      if (([string]$item.sourceHash).ToLowerInvariant() -eq $sourceHash -and
          ([string]$item.packagedHash).ToLowerInvariant() -eq $packagedHash) {
        return [pscustomobject]@{
          Path = $PackagedLocale
          SourceKeys = [int]$item.keys
          PackagedKeys = [int]$item.keys
          MissingFilled = 0
          MemoryFilled = 0
          FallbackFilled = 0
          Merged = $false
          Known = $true
        }
      }
    }
  } catch {
  }

  return $null
}

function New-MergedWebLocale([string]$SourceLocale, [string]$PackagedLocale) {
  $knownMerge = Get-KnownWebLocaleMerge $SourceLocale $PackagedLocale
  if ($knownMerge) {
    return $knownMerge
  }

  $source = Read-JsonObject $SourceLocale
  $packaged = Read-JsonObject $PackagedLocale

  if (Test-SameJsonKeys $source $packaged) {
    return [pscustomobject]@{
      Path = $PackagedLocale
      SourceKeys = ($source.PSObject.Properties | Measure-Object).Count
      PackagedKeys = ($packaged.PSObject.Properties | Measure-Object).Count
      MissingFilled = 0
      MemoryFilled = 0
      FallbackFilled = 0
      Merged = $false
    }
  }

  $packagedMap = Get-JsonPropertyMap $packaged
  $memoryMap = @{}
  $memoryFile = Join-Path $WebI18nDir 'translation-memory.json'
  if (Test-Path -Path $memoryFile) {
    try {
      $memoryMap = Get-JsonPropertyMap (Read-JsonObject $memoryFile)
    } catch {
      $memoryMap = @{}
    }
  }

  $merged = [ordered]@{}
  $missing = 0
  $memoryFilled = 0
  $fallbackFilled = 0

  foreach ($prop in $source.PSObject.Properties) {
    $name = $prop.Name
    $sourceText = [string]$prop.Value
    if ($packagedMap.ContainsKey($name)) {
      $merged[$name] = $packagedMap[$name]
    } elseif ($memoryMap.ContainsKey($sourceText)) {
      $merged[$name] = $memoryMap[$sourceText]
      $missing++
      $memoryFilled++
    } else {
      $merged[$name] = $prop.Value
      $missing++
      $fallbackFilled++
    }
  }

  $tempDir = Join-Path $env:TEMP 'ClaudeZhPatch'
  Ensure-Directory $tempDir
  $mergedPath = Join-Path $tempDir 'zh-CN.merged.json'
  Write-Utf8NoBom $mergedPath (($merged | ConvertTo-Json -Depth 100) + [Environment]::NewLine)

  return [pscustomobject]@{
    Path = $mergedPath
    SourceKeys = ($source.PSObject.Properties | Measure-Object).Count
    PackagedKeys = ($packaged.PSObject.Properties | Measure-Object).Count
    MissingFilled = $missing
    MemoryFilled = $memoryFilled
    FallbackFilled = $fallbackFilled
    Merged = $true
  }
}

function Apply-ManualWebOverrides([string]$LocalePath) {
  $fullManualFile = Join-Path (Split-Path -Parent $ToolDir) '手动修改翻译.json'
  $manualFiles = @(
    (Join-Path $WebI18nDir 'manual-overrides.json'),
    $fullManualFile
  ) | Where-Object { Test-Path -Path $_ }

  $effectiveManualFiles = New-Object System.Collections.ArrayList
  $baselineFile = Join-Path $WebI18nDir 'manual-full-baseline.sha256'
  $baselineHash = ''
  if (Test-Path -Path $baselineFile) {
    $baselineHash = (Get-Content -Path $baselineFile -Raw -Encoding UTF8).Trim().ToLowerInvariant()
  }

  foreach ($manualFile in $manualFiles) {
    $rawManual = Get-Content -Path $manualFile -Raw -Encoding UTF8
    if ($rawManual.Trim() -eq '{}') {
      continue
    }
    if ($baselineHash -and [string]::Equals($manualFile, $fullManualFile, [System.StringComparison]::OrdinalIgnoreCase)) {
      $manualHash = (Get-FileSha256 $manualFile).ToLowerInvariant()
      if ($manualHash -eq $baselineHash) {
        continue
      }
    }
    [void]$effectiveManualFiles.Add($manualFile)
  }
  $manualFiles = @($effectiveManualFiles)

  if ($manualFiles.Count -eq 0) {
    return [pscustomobject]@{
      Path = $LocalePath
      Count = 0
      Applied = $false
    }
  }

  $locale = Read-JsonObject $LocalePath
  $count = 0
  foreach ($manualFile in $manualFiles) {
    $manual = Read-JsonObject $manualFile
    foreach ($prop in $manual.PSObject.Properties) {
      $translationValue = Get-ManualTranslationValue $prop.Value
      if ($null -eq $translationValue) {
        continue
      }
      $existing = $locale.PSObject.Properties.Item($prop.Name)
      if ($null -ne $existing) {
        $existing.Value = $translationValue
      } else {
        $locale | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $translationValue
      }
      $count++
    }
  }

  $tempDir = Join-Path $env:TEMP 'ClaudeZhPatch'
  Ensure-Directory $tempDir
  $manualPath = Join-Path $tempDir 'zh-CN.manual.json'
  Write-Utf8NoBom $manualPath (($locale | ConvertTo-Json -Depth 100) + [Environment]::NewLine)

  return [pscustomobject]@{
    Path = $manualPath
    Count = $count
    Applied = $true
  }
}

function Patch-TextFile([string]$Path, [string]$Old, [string]$New, [string]$Already) {
  $text = Get-Content -Path $Path -Raw -Encoding UTF8
  if ($Already -and $text.Contains($Already)) {
    return 'already patched'
  }
  if (-not $text.Contains($Old)) {
    throw "Patch pattern not found in $Path"
  }
  $text = $text.Replace($Old, $New)
  Write-Utf8NoBom $Path $text
  return 'patched'
}

function Find-FileContaining([string]$Root, [string]$Needle) {
  $files = Get-ChildItem -Path $Root -File -Filter '*.js' -Recurse -ErrorAction SilentlyContinue
  foreach ($file in $files) {
    if (Select-String -Path $file.FullName -Pattern $Needle -SimpleMatch -Quiet) {
      return $file.FullName
    }
  }
  return $null
}

function Patch-WebLocaleAllowlist([string]$Assets) {
  $withoutZh = '["en-US","de-DE","fr-FR","ko-KR","ja-JP","es-419","es-ES","it-IT","hi-IN","pt-BR","id-ID"]'
  $withZhLast = '["en-US","de-DE","fr-FR","ko-KR","ja-JP","es-419","es-ES","it-IT","hi-IN","pt-BR","id-ID","zh-CN"]'
  $withZhFirst = '["zh-CN","en-US","de-DE","fr-FR","ko-KR","ja-JP","es-419","es-ES","it-IT","hi-IN","pt-BR","id-ID"]'

  $files = Get-ChildItem -Path $Assets -File -Filter '*.js' -Recurse -ErrorAction SilentlyContinue
  foreach ($file in $files) {
    $text = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    if ($text.Contains($withZhFirst)) {
      return "already patched: $($file.Name)"
    }
    if ($text.Contains($withoutZh)) {
      $text = $text.Replace($withoutZh, $withZhFirst)
      Write-Utf8NoBom $file.FullName $text
      return "patched: $($file.Name)"
    }
    if ($text.Contains($withZhLast)) {
      $text = $text.Replace($withZhLast, $withZhFirst)
      Write-Utf8NoBom $file.FullName $text
      return "moved first: $($file.Name)"
    }
  }
  return 'allowlist not found'
}

function Test-PlainHardcodedSource([string]$Source) {
  if ($Source.Contains("`n") -or $Source.Contains("`r")) {
    return $false
  }
  foreach ($marker in @('"', '\', '=', ';', '=>')) {
    if ($Source.Contains($marker)) {
      return $false
    }
  }
  return $true
}

function Replace-HardcodedText([string]$Text, [string]$Source, [string]$Target) {
  if ([string]::IsNullOrEmpty($Source) -or $Source -eq $Target) {
    return [pscustomobject]@{ Text = $Text; Count = 0 }
  }

  if (Test-PlainHardcodedSource $Source) {
    $pattern = '(?<quote>["''`])' + [System.Text.RegularExpressions.Regex]::Escape($Source) + '\k<quote>'
    $count = [System.Text.RegularExpressions.Regex]::Matches($Text, $pattern).Count
    if ($count -eq 0) {
      return [pscustomobject]@{ Text = $Text; Count = 0 }
    }
    $updated = [System.Text.RegularExpressions.Regex]::Replace($Text, $pattern, {
      param($match)
      $quote = $match.Groups['quote'].Value
      return $quote + $Target + $quote
    })
    return [pscustomobject]@{ Text = $updated; Count = $count }
  }

  $count = ([System.Text.RegularExpressions.Regex]::Matches($Text, [System.Text.RegularExpressions.Regex]::Escape($Source))).Count
  if ($count -eq 0) {
    return [pscustomobject]@{ Text = $Text; Count = 0 }
  }
  return [pscustomobject]@{ Text = $Text.Replace($Source, $Target); Count = $count }
}

function Get-HardcodedWebReplacements {
  $pairs = New-Object System.Collections.ArrayList
  foreach ($pair in @(
    @('Buttery', '柔滑'),
    @('Airy', '轻盈'),
    @('Mellow', '温和'),
    @('Glassy', '清透'),
    @('Rounded', '圆润'),
    @("Harry Potter and the Philosopher's Stone", '哈利·波特与魔法石')
  )) {
    [void]$pairs.Add($pair)
  }

  $external = Join-Path $WebI18nDir 'hardcoded-replacements.json'
  if (Test-Path -Path $external) {
    $items = Get-Content -Path $external -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($item in $items) {
      if ($item.Count -eq 2 -and [string]$item[0] -and [string]$item[1]) {
        [void]$pairs.Add(@([string]$item[0], [string]$item[1]))
      }
    }
  }

  return @($pairs | Sort-Object -Property @{ Expression = { ([string]$_[0]).Length }; Descending = $true })
}

function Get-HardcodedReplacementHash($Replacements) {
  $normalized = New-Object System.Collections.ArrayList
  foreach ($entry in $Replacements) {
    [void]$normalized.Add(@([string]$entry[0], [string]$entry[1]))
  }
  $json = $normalized | ConvertTo-Json -Depth 4 -Compress
  return Get-StringSha256 $json
}

function Get-WebI18nInputFingerprint([string]$AppDir, [string]$SourceLocale) {
  $items = New-Object System.Collections.ArrayList
  [void]$items.Add([ordered]@{ id = 'format'; value = 'web-i18n-fast-v2' })

  foreach ($entry in @(
    @('script', $ScriptPath),
    @('app-version', (Join-Path $AppDir 'version')),
    @('source-en-US', $SourceLocale),
    @('packaged-zh-CN', (Join-Path $WebI18nDir 'zh-CN.json')),
    @('manual-overrides', (Join-Path $WebI18nDir 'manual-overrides.json')),
    @('manual-full', (Join-Path (Split-Path -Parent $ToolDir) '手动修改翻译.json')),
    @('manual-full-baseline', (Join-Path $WebI18nDir 'manual-full-baseline.sha256')),
    @('known-source-locales', (Join-Path $WebI18nDir 'known-source-locales.json')),
    @('web-overrides', (Join-Path $WebI18nDir 'zh-CN.overrides.json')),
    @('web-dynamic', (Join-Path $WebI18nDir 'dynamic\zh-CN.json')),
    @('hardcoded-replacements', (Join-Path $WebI18nDir 'hardcoded-replacements.json'))
  )) {
    [void]$items.Add([ordered]@{
      id = [string]$entry[0]
      hash = Get-FileSha256 ([string]$entry[1])
    })
  }

  $json = $items | ConvertTo-Json -Depth 5 -Compress
  return Get-StringSha256 $json
}

function Patch-HardcodedWebText([string]$Assets) {
  $replacements = @(Get-HardcodedWebReplacements)
  $replacementHash = Get-HardcodedReplacementHash $replacements
  $markerPath = Join-Path $Assets '.claude-zh-hardcoded-patch.json'

  if (Test-Path -Path $markerPath) {
    try {
      $marker = Get-Content -Path $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json
      if ([string]$marker.replacementsHash -eq [string]$replacementHash) {
        return 'hardcoded text already checked'
      }
    } catch {
    }
  }

  $filesChanged = 0
  $stringsChanged = 0
  $files = Get-ChildItem -Path $Assets -File -Filter '*.js' -Recurse -ErrorAction SilentlyContinue
  foreach ($file in $files) {
    $text = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    $updated = $text
    foreach ($entry in $replacements) {
      $source = [string]$entry[0]
      if ([string]::IsNullOrEmpty($source) -or -not $updated.Contains($source)) {
        continue
      }
      $result = Replace-HardcodedText $updated $source ([string]$entry[1])
      if ($result.Count -gt 0) {
        $updated = $result.Text
        $stringsChanged += $result.Count
      }
    }
    if ($updated -ne $text) {
      Write-Utf8NoBom $file.FullName $updated
      $filesChanged++
    }
  }

  $markerJson = [ordered]@{
    checkedAt = (Get-Date).ToString('o')
    replacementsHash = $replacementHash
    filesChanged = $filesChanged
    stringsChanged = $stringsChanged
  } | ConvertTo-Json -Depth 4
  Write-Utf8NoBom $markerPath $markerJson

  if ($filesChanged -eq 0) {
    return 'hardcoded text not found'
  }
  return "hardcoded text patched: files=$filesChanged, strings=$stringsChanged"
}

function Install-WebI18n([string]$AppDir) {
  $webLocale = Join-Path $WebI18nDir 'zh-CN.json'
  if (-not (Test-Path -Path $webLocale)) {
    return [pscustomobject]@{
      Installed = $false
      Message = 'web-i18n\zh-CN.json not found; main Claude.ai UI was not localized.'
    }
  }

  $ion = Join-Path $AppDir 'resources\ion-dist'
  $i18n = Join-Path $ion 'i18n'
  $dynamic = Join-Path $i18n 'dynamic'
  $assets = Join-Path $ion 'assets\v1'
  if (-not (Test-Path -Path $i18n) -or -not (Test-Path -Path $assets)) {
    throw "ion-dist i18n/assets directory not found under $AppDir"
  }

  $sourceLocale = Join-Path $i18n 'en-US.json'
  $fingerprint = Get-WebI18nInputFingerprint $AppDir $sourceLocale
  $installMarker = Join-Path $i18n '.claude-zh-web-i18n.json'
  $installedLocale = Join-Path $i18n 'zh-CN.json'
  if ((Test-Path -Path $installMarker) -and (Test-Path -Path $installedLocale)) {
    try {
      $marker = Get-Content -Path $installMarker -Raw -Encoding UTF8 | ConvertFrom-Json
      if ([string]$marker.fingerprint -eq [string]$fingerprint) {
        $cachedKeys = [string]$marker.keys
        if ([string]::IsNullOrWhiteSpace($cachedKeys)) {
          $cachedKeys = 'cached'
        }
        return [pscustomobject]@{
          Installed = $true
          Message = "web i18n already current; keys=$cachedKeys; skipped unchanged files"
        }
      }
    } catch {
    }
  }

  $preparedLocale = $webLocale
  $merge = $null
  if (Test-Path -Path $sourceLocale) {
    $merge = New-MergedWebLocale $sourceLocale $webLocale
    $preparedLocale = $merge.Path
  }

  $manualOverrides = Apply-ManualWebOverrides $preparedLocale
  $preparedLocale = $manualOverrides.Path

  Copy-Item -Path $preparedLocale -Destination (Join-Path $i18n 'zh-CN.json') -Force

  $webOverrides = Join-Path $WebI18nDir 'zh-CN.overrides.json'
  if (Test-Path -Path $webOverrides) {
    Copy-Item -Path $webOverrides -Destination (Join-Path $i18n 'zh-CN.overrides.json') -Force
  } else {
    Write-Utf8NoBom (Join-Path $i18n 'zh-CN.overrides.json') "{}$([Environment]::NewLine)"
  }

  Ensure-Directory $dynamic
  $webDynamic = Join-Path $WebI18nDir 'dynamic\zh-CN.json'
  if (Test-Path -Path $webDynamic) {
    Copy-Item -Path $webDynamic -Destination (Join-Path $dynamic 'zh-CN.json') -Force
  } else {
    Write-Utf8NoBom (Join-Path $dynamic 'zh-CN.json') "{}$([Environment]::NewLine)"
  }

  $listStatus = Patch-WebLocaleAllowlist $assets
  $hardcodedStatus = Patch-HardcodedWebText $assets

  $bootstrapFile = Find-FileContaining $assets 'const u=await c.json();return'
  if (-not $bootstrapFile) {
    $bootstrapFile = Find-FileContaining $assets 'const u=await c.json();u.locale="zh-CN";return'
  }
  if ($bootstrapFile) {
    $bootstrapStatus = Patch-TextFile $bootstrapFile `
      'const u=await c.json();return' `
      'const u=await c.json();u.locale="zh-CN";return' `
      'const u=await c.json();u.locale="zh-CN";return'
  } else {
    $bootstrapStatus = 'bootstrap pattern not found'
  }

  $keys = 0
  if ($merge) {
    $keys = [int]$merge.SourceKeys
  } else {
    try {
      $keys = ((Get-Content -Path $preparedLocale -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | Measure-Object).Count
    } catch {
      throw 'web-i18n\zh-CN.json is not valid JSON.'
    }
  }

  $mergeMessage = ''
  if ($merge -and $merge.Merged) {
    $mergeMessage = "; merged missing=$($merge.MissingFilled), memory=$($merge.MemoryFilled), fallback=$($merge.FallbackFilled)"
  }
  if ($manualOverrides.Applied) {
    $mergeMessage += "; manual=$($manualOverrides.Count)"
  }

  $installMarkerJson = [ordered]@{
    installedAt = (Get-Date).ToString('o')
    fingerprint = $fingerprint
    keys = $keys
    allowlist = $listStatus
    hardcoded = $hardcodedStatus
    bootstrap = $bootstrapStatus
  } | ConvertTo-Json -Depth 5
  Write-Utf8NoBom $installMarker $installMarkerJson

  return [pscustomobject]@{
    Installed = $true
    Message = "web i18n installed; keys=$keys$mergeMessage; allowlist=$listStatus; hardcoded=$hardcodedStatus; bootstrap=$bootstrapStatus"
  }
}

function New-ClaudeShortcut([string]$AppDir) {
  $target = Join-Path $AppDir 'claude.exe'
  $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
  Ensure-Directory $startMenu

  $shell = New-Object -ComObject WScript.Shell
  $oldShortcutPaths = @(
    (Join-Path $Desktop 'Claude.lnk'),
    (Join-Path $startMenu 'Claude.lnk')
  )

  foreach ($oldShortcutPath in $oldShortcutPaths) {
    if (-not (Test-Path -LiteralPath $oldShortcutPath)) {
      continue
    }
    try {
      $oldShortcut = $shell.CreateShortcut($oldShortcutPath)
      if (Test-IsClaudeZhGeneratedPath $oldShortcut.TargetPath) {
        Remove-Item -LiteralPath $oldShortcutPath -Force
        Write-Info "Removed old zh-CN shortcut: $oldShortcutPath"
      }
    } catch {
      Write-Info "Skipped shortcut cleanup: $oldShortcutPath"
    }
  }

  $shortcutPaths = @(
    (Join-Path $Desktop 'Claude zh-CN.lnk'),
    (Join-Path $startMenu 'Claude zh-CN.lnk')
  )

  foreach ($shortcutPath in $shortcutPaths) {
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $target
    $shortcut.WorkingDirectory = $AppDir
    $shortcut.Description = 'Claude zh-CN'
    $shortcut.Save()
  }

  return $shortcutPaths
}

function Stop-Claude {
  $processes = @(Get-Process -Name 'claude' -ErrorAction SilentlyContinue)
  if ($processes.Count -eq 0) {
    return
  }
  $processes | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 700
}

try {
  if ($Restore) {
    $configPath = Set-ClaudeLocale 'en-US'
    Write-Info "Locale preference restored to en-US: $configPath"
    Write-Info 'Restart Claude if it is already running.'
    exit 0
  }

  if (-not (Test-Path -Path $LocaleFile)) {
    throw "Missing locale file: $LocaleFile"
  }

  $localeJson = Get-Content -Path $LocaleFile -Raw -Encoding UTF8 | ConvertFrom-Json
  if (-not $localeJson.PSObject.Properties['S3MXlbjkax']) {
    throw 'Locale validation failed: required message key is missing.'
  }

  $install = Get-ClaudeInstall
  Write-Info "Found Claude: $($install.AppDir)"
  if ($install.Version) {
    Write-Info "Version: $($install.Version)"
  }

  $backup = Backup-Claude $install.AppDir
  if ($backup.Created) {
    Write-Info "Backup created: $($backup.Path)"
  } else {
    Write-Info "Backup already exists, reusing: $($backup.Path)"
  }

  Stop-Claude

  $targetAppDir = $install.AppDir
  $targetResources = Join-Path $targetAppDir 'resources'
  $mode = 'direct'

  if (-not (Test-CanWrite $targetResources)) {
    $mode = 'fixed-copy'
    $targetRoot = Get-ClaudeZhInstallRoot
    $packageFolder = Get-ClaudePackageFolderName $install.AppDir
    $targetAppDir = Join-Path $targetRoot (Join-Path 'WindowsApps' (Join-Path $packageFolder 'app'))
    Write-Info 'Install directory is not writable. Creating a fixed writable copy.'
    Write-Info "Copying to: $targetRoot"
    Remove-ClaudeZhInstallRoot $targetRoot
    Ensure-Directory (Split-Path -Parent $targetAppDir)
    Copy-Item -Path $install.AppDir -Destination $targetAppDir -Recurse -Force
    $targetResources = Join-Path $targetAppDir 'resources'
  }

  Copy-Item -Path $LocaleFile -Destination (Join-Path $targetResources 'zh-CN.json') -Force
  $webI18n = Install-WebI18n $targetAppDir
  $configPath = Set-ClaudeLocale 'zh-CN'
  $shortcut = New-ClaudeShortcut $targetAppDir

  Write-Info "Locale file written: $(Join-Path $targetResources 'zh-CN.json')"
  Write-Info $webI18n.Message
  Write-Info "Locale preference written: $configPath"
  foreach ($shortcutPath in @($shortcut)) {
    Write-Info "Shortcut created: $shortcutPath"
  }
  Write-Info "Mode: $mode"

  Start-Process -FilePath (Join-Path $targetAppDir 'claude.exe') -WorkingDirectory $targetAppDir
  Write-Info 'Done. Launch Claude from the desktop or Start Menu "Claude zh-CN" shortcut.'
} catch {
  Write-Host ''
  Write-Host '[Claude zh-CN] Failed:' -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red
  Write-Host ''
  Write-Host 'Existing backups were not deleted. Send the error text above to the maintainer.'
  exit 1
}
