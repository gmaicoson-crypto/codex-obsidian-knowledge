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
$pluginSelector = "$pluginName@$marketplaceName"
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
if ($marketplaces -notmatch [regex]::Escape($marketplaceName)) {
    Write-Output "Registering repository marketplace: $marketplaceName"
    Invoke-Codex @('plugin', 'marketplace', 'add', $repoRoot)
}
else {
    $matchingMarketplaceLine = $marketplaceLines | Where-Object { $_ -match [regex]::Escape($marketplaceName) } | Select-Object -First 1
    $normalizedMarketplaceOutput = Normalize-PathText ([string]$matchingMarketplaceLine)
    $normalizedRepoRoot = Normalize-PathText $repoRoot
    if (-not $normalizedMarketplaceOutput.Contains($normalizedRepoRoot)) {
        throw "Marketplace '$marketplaceName' already exists but points to a different location. No files or configuration were changed."
    }
    Write-Output "Repository marketplace is already registered: $marketplaceName"
}

$pluginLines = & codex plugin list 2>&1
$pluginListExitCode = $LASTEXITCODE
if ($pluginListExitCode -ne 0) {
    throw "Could not inspect installed Codex plugins. No files or configuration were changed. Exit code: $pluginListExitCode"
}
$plugins = $pluginLines | Out-String
$installedPattern = '(?m)^\s*' + [regex]::Escape($pluginSelector) + '\s+installed'
if ($plugins -match $installedPattern) {
    Write-Output "Plugin is already installed: $pluginSelector"
}
elseif (Test-Path -LiteralPath $cachePath) {
    throw "Plugin cache path already exists and is not reported as this installed plugin: $cachePath. Refusing to overwrite it."
}
else {
    Write-Output "Installing plugin: $pluginSelector"
    Invoke-Codex @('plugin', 'add', $pluginSelector)
}

Write-Output 'Codex plugin installation is complete.'
Write-Output 'Restart Codex and test the skill in a new conversation.'
