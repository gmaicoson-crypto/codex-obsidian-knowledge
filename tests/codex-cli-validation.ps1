[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { throw 'Codex CLI is required for plugin package validation.' }
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifest = Get-Content -LiteralPath (Join-Path $repoRoot '.codex-plugin\plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$marketplace = Get-Content -LiteralPath (Join-Path $repoRoot '.agents\plugins\marketplace.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$selector = "$($manifest.name)@$($marketplace.name)"
$temporaryCodexHome = Join-Path $PSScriptRoot ('.tmp-codex-plugin-validation-' + [guid]::NewGuid().ToString('N'))
$previousCodexHome = $env:CODEX_HOME
try {
    New-Item -ItemType Directory -Path $temporaryCodexHome -Force | Out-Null
    $env:CODEX_HOME = $temporaryCodexHome
    & (Join-Path $repoRoot 'scripts\install-plugin.ps1') -Approve | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Plugin installer failed against an isolated Codex Home.' }
    $plugins = (& codex plugin list 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0 -or $plugins -notmatch ('(?m)^\s*' + [regex]::Escape($selector) + '\s+installed')) {
        throw "Codex CLI did not report the isolated plugin as installed: $selector"
    }
    & (Join-Path $repoRoot 'scripts\install-plugin.ps1') -Approve | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Plugin installer was not idempotent in an isolated Codex Home.' }
    & codex plugin remove $selector | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Codex CLI could not remove the isolated test plugin.' }
    & codex plugin marketplace remove ([string]$marketplace.name) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Codex CLI could not remove the isolated test marketplace.' }
    Write-Output 'Codex CLI plugin package validation passed.'
}
finally {
    if ($null -eq $previousCodexHome) { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue } else { $env:CODEX_HOME = $previousCodexHome }
    $resolvedTemporary = [System.IO.Path]::GetFullPath($temporaryCodexHome)
    $expectedPrefix = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar + '.tmp-codex-plugin-validation-'
    if ($resolvedTemporary.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTemporary)) {
        Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
    }
}
