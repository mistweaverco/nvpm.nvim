# Migrate plugins from lazy.nvim's lazy-lock.json into nvpm (pinned commits).
#
# Usage:
#   .\migrate-from-lazy.nvim-package-manager.ps1 [-DryRun] [-Lockfile PATH] [-LazyRoot PATH]
#
# Resolves each lock entry to provider:owner/repo@commit via the plugin's git remote
# under the lazy root (lockfile only stores name + commit).

[CmdletBinding()]
param(
  [switch]$DryRun,
  [string]$Lockfile = "",
  [string]$LazyRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-Command {
  param([string]$Name)
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

foreach ($cmd in @("nvim", "nvpm", "git")) {
  if (-not (Test-Command $cmd)) {
    Write-Error "required command not found: $cmd"
  }
}

function Get-NvimStdpath {
  param([ValidateSet("config", "data", "cache", "state")][string]$Kind)
  $out = & nvim --headless -u NONE `
    -c "lua io.stdout:write(vim.fn.stdpath([[$Kind]]))" `
    -c "qa!" 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($out)) {
    Write-Error "failed to resolve Neovim stdpath('$Kind')"
  }
  return "$out".Trim()
}

if ([string]::IsNullOrWhiteSpace($Lockfile)) {
  $Lockfile = Join-Path (Get-NvimStdpath "config") "lazy-lock.json"
}
if ([string]::IsNullOrWhiteSpace($LazyRoot)) {
  $LazyRoot = Join-Path (Get-NvimStdpath "data") "lazy"
}

if (-not (Test-Path -LiteralPath $Lockfile -PathType Leaf)) {
  Write-Error "lazy-lock.json not found at: $Lockfile`nhint: pass -Lockfile PATH"
}
if (-not (Test-Path -LiteralPath $LazyRoot -PathType Container)) {
  Write-Error "lazy plugin root not found at: $LazyRoot`nhint: pass -LazyRoot PATH (plugins must be installed so remotes can be read)"
}

Write-Host "lockfile:  $Lockfile"
Write-Host "lazy root: $LazyRoot"

$lock = Get-Content -LiteralPath $Lockfile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($null -eq $lock) {
  Write-Error "lazy-lock.json must be a JSON object"
}

function ConvertTo-SourceId {
  param([string]$Url)
  $u = $Url.Trim()
  if ($u.EndsWith(".git")) { $u = $u.Substring(0, $u.Length - 4) }
  if ($u.EndsWith("/")) { $u = $u.TrimEnd("/") }

  $hostName = $null
  $path = $null

  if ($u -match '^git@([^:]+):(.+)$') {
    $hostName = $Matches[1]
    $path = $Matches[2]
  }
  elseif ($u -match '^ssh://(?:[^@]+@)?([^/]+)/(.+)$') {
    $hostName = $Matches[1]
    $path = $Matches[2]
  }
  elseif ($u -match '^https?://([^/]+)/(.+)$') {
    $hostName = $Matches[1]
    $path = $Matches[2]
  }
  elseif ($u -match '^git://([^/]+)/(.+)$') {
    $hostName = $Matches[1]
    $path = $Matches[2]
  }
  else {
    return $null
  }

  if ($hostName.Contains("@")) {
    $hostName = $hostName.Split("@")[-1]
  }
  $path = $path.TrimStart("/")
  if ($path.EndsWith(".git")) { $path = $path.Substring(0, $path.Length - 4) }

  $provider = switch ($hostName.ToLowerInvariant()) {
    "github.com" { "github" }
    "www.github.com" { "github" }
    "gitlab.com" { "gitlab" }
    "www.gitlab.com" { "gitlab" }
    "codeberg.org" { "codeberg" }
    "www.codeberg.org" { "codeberg" }
    "forgejo.org" { "forgejo" }
    "www.forgejo.org" { "forgejo" }
    default { $null }
  }
  if (-not $provider) {
    return $null
  }
  return "${provider}:${path}"
}

$pkgIds = New-Object System.Collections.Generic.List[string]
$skipped = 0
$resolved = 0

$names = @($lock.PSObject.Properties.Name | Sort-Object)
foreach ($name in $names) {
  if ($name -eq "lazy.nvim") {
    continue
  }
  $entry = $lock.$name
  if ($null -eq $entry) { continue }

  $commit = $null
  $url = $null
  if ($entry -is [string]) {
    # unexpected shape
    continue
  }
  if ($entry.PSObject.Properties.Name -contains "commit") {
    $commit = [string]$entry.commit
  }
  if ($entry.PSObject.Properties.Name -contains "url") {
    $url = [string]$entry.url
  }
  if ([string]::IsNullOrWhiteSpace($commit)) {
    Write-Warning "skip ${name}: missing commit"
    $skipped++
    continue
  }

  $sourceId = $null
  if (-not [string]::IsNullOrWhiteSpace($url)) {
    $sourceId = ConvertTo-SourceId $url
    if (-not $sourceId) {
      Write-Warning "${name}: lock url not a supported host: $url"
    }
  }

  if (-not $sourceId) {
    $pluginDir = Join-Path $LazyRoot $name
    if (-not (Test-Path -LiteralPath $pluginDir -PathType Container)) {
      Write-Warning "skip ${name}@${commit} - not installed under lazy root (need remote to map owner/repo)"
      $skipped++
      continue
    }
    try {
      $remoteUrl = (& git -C $pluginDir remote get-url origin 2>$null).Trim()
    }
    catch {
      $remoteUrl = ""
    }
    if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
      Write-Warning "skip ${name}@${commit} - no git remote 'origin' in $pluginDir"
      $skipped++
      continue
    }
    $sourceId = ConvertTo-SourceId $remoteUrl
    if (-not $sourceId) {
      Write-Warning "skip ${name}@${commit} - unsupported git host in remote: $remoteUrl"
      Write-Warning "       supported: github.com, gitlab.com, codeberg.org, forgejo.org"
      $skipped++
      continue
    }
  }

  $pkgId = "${sourceId}@${commit}"
  $pkgIds.Add($pkgId) | Out-Null
  $resolved++
  Write-Host "  + $name → $pkgId"
}

if ($pkgIds.Count -eq 0) {
  Write-Error "nothing to install ($skipped skipped)"
}

Write-Host ""
Write-Host "resolved: $resolved  skipped: $skipped"

$cmdArgs = @("add", "--force", "--plugin", "neovim") + $pkgIds.ToArray()
$display = "nvpm " + (($cmdArgs | ForEach-Object {
  if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
}) -join " ")

Write-Host ""
Write-Host "command: $display"

if ($DryRun) {
  Write-Host "dry-run: not executing"
  exit 0
}

Write-Host ""
& nvpm @cmdArgs
exit $LASTEXITCODE
