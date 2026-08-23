[CmdletBinding()]
param([switch]$Clean)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifest = Get-Content -LiteralPath (Join-Path $repoRoot '.codex-plugin\plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$pluginName = [string]$manifest.name
if ($pluginName -notmatch '^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$') { throw "Invalid plugin name in manifest: $pluginName" }
$packagesRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'plugins'))
$packageRoot = [System.IO.Path]::GetFullPath((Join-Path $packagesRoot $pluginName))
$expectedPrefix = $packagesRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
$markerName = '.generated-by-codex-obsidian-knowledge'
$markerPath = Join-Path $packageRoot $markerName

if (-not $packageRoot.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Generated plugin package path escaped the repository plugins directory.'
}
if ($Clean) {
    if (Test-Path -LiteralPath $packageRoot) {
        if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw "Refusing to clean an unmanaged package path: $packageRoot" }
        Remove-Item -LiteralPath $packageRoot -Recurse -Force
    }
    Write-Output 'Generated plugin package cleaned.'
    return
}

New-Item -ItemType Directory -Path $packagesRoot -Force | Out-Null
$stagingRoot = Join-Path $packagesRoot ('.staging-' + [guid]::NewGuid().ToString('N'))
$backupRoot = Join-Path $packagesRoot ('.backup-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    foreach ($directory in @('.codex-plugin', 'assets', 'skills', 'templates', 'scripts', 'docs')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $directory) -Destination (Join-Path $stagingRoot $directory) -Recurse -Force
    }
    foreach ($file in @('README.md', 'PRIVACY.md', 'SECURITY.md', 'LICENSE', 'CHANGELOG.md')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $file) -Destination (Join-Path $stagingRoot $file) -Force
    }
    [System.IO.File]::WriteAllText((Join-Path $stagingRoot $markerName), "generated from repository root`n", [System.Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $packageRoot) {
        if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw "Plugin package path already exists and is not managed by this builder: $packageRoot" }
        Move-Item -LiteralPath $packageRoot -Destination $backupRoot -Force
    }
    try { Move-Item -LiteralPath $stagingRoot -Destination $packageRoot -Force }
    catch {
        if (Test-Path -LiteralPath $backupRoot) { Move-Item -LiteralPath $backupRoot -Destination $packageRoot -Force }
        throw
    }
    if (Test-Path -LiteralPath $backupRoot) { Remove-Item -LiteralPath $backupRoot -Recurse -Force }
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
}
Write-Output "Generated plugin package: $packageRoot"
