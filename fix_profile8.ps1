#!/usr/bin/env pwsh
param(
  [string]$ProfilePath,
  [string]$ToolPath,
  [string]$WorkDir,
  [switch]$NoAutoInstall,
  [switch]$Force = $true,
  [switch]$VerboseLogs
)

$ErrorActionPreference = "Stop"

function LogInfo { param([string]$Message) Write-Host ">> $Message" }
function LogOk { param([string]$Message) Write-Host "OK $Message" -ForegroundColor Green }
function LogWarn { param([string]$Message) Write-Host "WARN $Message" -ForegroundColor Yellow }
function LogError { param([string]$Message) Write-Host "ERROR $Message" -ForegroundColor Red }

function Find-ToolInPath {
  $names = @("divine", "Divine", "ConverterApp")
  foreach ($name in $names) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Path }
  }
  return ""
}

function Get-LatestLslibUrl {
  $apiUrl = "https://api.github.com/repos/Norbyte/lslib/releases/latest"
  $release = Invoke-RestMethod -Uri $apiUrl
  $bestUrl = ""
  $bestScore = 9
  foreach ($asset in $release.assets) {
    $name = ($asset.name ?? "").ToLower()
    if (-not $name) { continue }
    if ($name -like "*.zip") {
      if ($name -like "*exporttool*") { $score = 0 }
      elseif ($name -like "*divine*") { $score = 1 }
      else { $score = 2 }
    } else {
      $score = 9
    }

    if ($score -lt $bestScore) {
      $bestScore = $score
      $bestUrl = $asset.browser_download_url
    }
  }
  return $bestUrl
}

function Download-Tool {
  param([string]$WorkDir)

  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $zipPath = Join-Path $WorkDir "lslib.zip"
  $extractDir = Join-Path $WorkDir "lslib"

  $url = Get-LatestLslibUrl
  if (-not $url) { throw "Could not find a downloadable LSLib asset in the latest release." }

  LogInfo "Downloading latest LSLib release..."
  Invoke-WebRequest -Uri $url -OutFile $zipPath

  New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
  Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

  $targets = @("ConverterApp.exe", "Divine.exe", "ConverterApp.dll", "Divine.dll")
  foreach ($target in $targets) {
    $match = Get-ChildItem -Path $extractDir -Recurse -File -Filter $target -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($match) { return $match.FullName }
  }

  throw "LSLib downloaded, but no Divine/ConverterApp tool was found."
}

function Resolve-ProfilePath {
  param([string]$Path)

  if ($Path -and (Test-Path $Path)) { return $Path }

  $root = Join-Path $env:LOCALAPPDATA "Larian Studios\Baldur's Gate 3\PlayerProfiles"
  if (-not (Test-Path $root)) { return "" }

  $matches = Get-ChildItem -Path $root -Recurse -File -Filter "profile8.lsf" -ErrorAction SilentlyContinue
  if (-not $matches) { return "" }

  $public = $matches | Where-Object { $_.Directory.Name -ieq "Public" } | Select-Object -First 1
  if ($public) { return $public.FullName }

  return ($matches | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

function Run-Tool {
  param([string]$ToolPath, [string]$InputPath, [string]$OutputPath)

  $lower = $ToolPath.ToLower()
  if ($lower.EndsWith(".dll")) {
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $dotnet) { throw "dotnet not found, but is required to run: $ToolPath" }
    & dotnet $ToolPath -a convert-resource -g bg3 -s $InputPath -d $OutputPath
  } else {
    & $ToolPath -a convert-resource -g bg3 -s $InputPath -d $OutputPath
  }
}

try {
  $defaultProfile = Join-Path $env:LOCALAPPDATA "Larian Studios\Baldur's Gate 3\PlayerProfiles\Public\profile8.lsf"
  if (-not $ProfilePath) { $ProfilePath = $defaultProfile }
  $ProfilePath = Resolve-ProfilePath -Path $ProfilePath

  if (-not $ProfilePath -or -not (Test-Path $ProfilePath)) {
    throw "profile8.lsf not found. Use -ProfilePath to specify the path."
  }

  if (-not $WorkDir) {
    $WorkDir = Join-Path ([IO.Path]::GetTempPath()) ("bg3-save-scavenger-" + [Guid]::NewGuid().ToString("N"))
  }
  New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

  if (-not $ToolPath) { $ToolPath = Find-ToolInPath }
  if (-not $ToolPath -and -not $NoAutoInstall) { $ToolPath = Download-Tool -WorkDir $WorkDir }
  if (-not $ToolPath) { throw "Could not find Divine/ConverterApp in PATH. Use -ToolPath to specify the path." }

  $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $backupPath = "$ProfilePath.bak.$timestamp"
  Copy-Item -Path $ProfilePath -Destination $backupPath -Force

  $backupDir = Join-Path $env:USERPROFILE "Documents\bg3_backups"
  New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
  $backupCopyPath = Join-Path $backupDir ("profile8.lsf.bak.$timestamp")
  Copy-Item -Path $ProfilePath -Destination $backupCopyPath -Force

  LogOk "Backup created: $backupPath"
  LogOk "Backup copy created: $backupCopyPath"

  $lsxPath = Join-Path $WorkDir "profile8.lsx"
  $lsfOut = Join-Path $WorkDir "profile8.lsf"

  LogInfo "Converting LSF -> LSX..."
  Run-Tool -ToolPath $ToolPath -InputPath $ProfilePath -OutputPath $lsxPath

  LogInfo "Removing DisabledSingleSaveSessions nodes..."
  $xml = New-Object xml
  $xml.PreserveWhitespace = $true
  $xml.Load($lsxPath)
  $nodes = $xml.SelectNodes("//node[@id='DisabledSingleSaveSessions']")
  $removed = 0
  foreach ($node in @($nodes)) {
    $null = $node.ParentNode.RemoveChild($node)
    $removed++
  }
  $xml.Save($lsxPath)

  if ($removed -eq 0) {
    if ($Force) {
      LogWarn "No DisabledSingleSaveSessions nodes found. Continuing due to -Force."
    } else {
      throw "No DisabledSingleSaveSessions nodes found. Aborting to keep original safe."
    }
  }

  LogOk "Removed $removed node(s)."

  LogInfo "Converting LSX -> LSF..."
  Run-Tool -ToolPath $ToolPath -InputPath $lsxPath -OutputPath $lsfOut

  Copy-Item -Path $lsfOut -Destination $ProfilePath -Force
  LogOk "Replaced profile8.lsf successfully."
} finally {
  if (-not $env:KEEP_WORKDIR -and $WorkDir -and (Test-Path $WorkDir)) {
    Remove-Item -Path $WorkDir -Recurse -Force
  }
}
