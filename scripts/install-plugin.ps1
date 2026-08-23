[CmdletBinding()]
param(
    [switch]$Approve
)

$ErrorActionPreference = 'Stop'

if (-not $Approve) {
    throw 'Plugin installation changes the current user Codex configuration and plugin cache. Re-run with -Approve after the user confirms.'
}

if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
    throw 'Codex CLI was not found on PATH. Open this repository from a Codex installation and try again.'
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifestPath = Join-Path $repoRoot '.codex-plugin\plugin.json'
$marketplacePath = Join-Path $repoRoot '.agents\plugins\marketplace.json'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Plugin manifest not found: $manifestPath"
}
if (-not (Test-Path -LiteralPath $marketplacePath -PathType Leaf)) {
    throw "Marketplace manifest not found: $marketplacePath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$marketplace = Get-Content -LiteralPath $marketplacePath -Raw -Encoding UTF8 | ConvertFrom-Json
$pluginName = [string]$manifest.name
$marketplaceName = [string]$marketplace.name
if ($pluginName -notmatch '^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$') { throw "Invalid plugin name in manifest: $pluginName" }
if ($marketplaceName -notmatch '^[A-Za-z0-9_-]+$') { throw "Invalid marketplace name in manifest: $marketplaceName" }
$pluginSelector = "$pluginName@$marketplaceName"
$packageBuilder = Join-Path $repoRoot 'scripts\build-plugin-package.ps1'
if (-not (Test-Path -LiteralPath $packageBuilder -PathType Leaf)) { throw "Plugin package builder not found: $packageBuilder" }
& $packageBuilder | Out-Null
$userCodexRoot = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
}
else {
    [System.IO.Path]::GetFullPath($env:CODEX_HOME)
}
$cachePath = Join-Path $userCodexRoot "plugins\cache\$marketplaceName\$pluginName\local"

function Normalize-PathText([string]$Value) {
    return $Value.Replace('/', '\').Replace('\\?\', '').TrimEnd('\').ToLowerInvariant()
}

function Invoke-Codex {
    param([string[]]$Arguments)

    & codex @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Codex command failed with exit code $($LASTEXITCODE): codex $($Arguments -join ' ')"
    }
}

$marketplaceLines = & codex plugin marketplace list 2>&1
$marketplaceListExitCode = $LASTEXITCODE
if ($marketplaceListExitCode -ne 0) {
    throw "Could not inspect configured Codex marketplaces. No files or configuration were changed. Exit code: $marketplaceListExitCode"
}
$marketplaces = $marketplaceLines | Out-String
$pluginLines = & codex plugin list 2>&1
$pluginListExitCode = $LASTEXITCODE
if ($pluginListExitCode -ne 0) {
    throw "Could not inspect installed Codex plugins. No files or configuration were changed. Exit code: $pluginListExitCode"
}
$plugins = $pluginLines | Out-String
$installedPattern = '(?m)^\s*' + [regex]::Escape($pluginSelector) + '\s+installed'
$pluginAlreadyInstalled = $plugins -match $installedPattern
if (-not $pluginAlreadyInstalled -and (Test-Path -LiteralPath $cachePath)) {
    throw "Plugin cache path already exists and is not reported as this installed plugin: $cachePath. Refusing to overwrite it."
}
$marketplaceAddedByThisRun = $false
$matchingMarketplaceLine = $marketplaceLines | Where-Object { (@([string]$_ -split '\s+', 2))[0] -eq $marketplaceName } | Select-Object -First 1
if ($null -eq $matchingMarketplaceLine) {
    Write-Output "Registering repository marketplace: $marketplaceName"
    Invoke-Codex @('plugin', 'marketplace', 'add', $repoRoot)
    $marketplaceAddedByThisRun = $true
}
else {
    $normalizedMarketplaceOutput = Normalize-PathText ([string]$matchingMarketplaceLine)
    $normalizedRepoRoot = Normalize-PathText $repoRoot
    if (-not $normalizedMarketplaceOutput.Contains($normalizedRepoRoot)) {
        throw "Marketplace '$marketplaceName' already exists but points to a different location. No files or configuration were changed."
    }
    Write-Output "Repository marketplace is already registered: $marketplaceName"
}

if ($pluginAlreadyInstalled) {
    Write-Output "Plugin is already installed: $pluginSelector"
}
else {
    Write-Output "Installing plugin: $pluginSelector"
    try {
        Invoke-Codex @('plugin', 'add', $pluginSelector)
    }
    catch {
        if ($marketplaceAddedByThisRun) {
            try {
                Invoke-Codex @('plugin', 'marketplace', 'remove', $marketplaceName)
                Write-Output "Rolled back marketplace registration: $marketplaceName"
            }
            catch {
                Write-Warning "Plugin installation failed and marketplace rollback also failed. Remove '$marketplaceName' manually."
            }
        }
        throw
    }
}

Write-Output 'Codex plugin installation is complete.'
Write-Output 'Restart Codex and test the skill in a new conversation.'
