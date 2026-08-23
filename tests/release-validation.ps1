[CmdletBinding()]
param([string]$Tag)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifest = Get-Content -LiteralPath (Join-Path $repoRoot '.codex-plugin\plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$version = [string]$manifest.version
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Plugin version is not strict semver: $version" }
if (-not [string]::IsNullOrWhiteSpace($Tag) -and $Tag -ne "v$version") { throw "Tag '$Tag' does not match plugin version v$version." }
$changelog = Get-Content -LiteralPath (Join-Path $repoRoot 'CHANGELOG.md') -Raw -Encoding UTF8
if ($changelog -notmatch ('(?m)^## ' + [regex]::Escape($version) + ' - ')) { throw "CHANGELOG.md has no release entry for $version." }
foreach ($path in @('scripts\doctor.ps1', 'scripts\doctor.sh')) {
    $content = Get-Content -LiteralPath (Join-Path $repoRoot $path) -Raw -Encoding UTF8
    if ($content -notmatch ('clientInfo.*version.*' + [regex]::Escape($version))) { throw "$path does not use plugin version $version in the MCP client info." }
}
Write-Output "Release metadata validation passed for $version."
