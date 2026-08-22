[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

foreach ($relativePath in @(
    'scripts\bootstrap.ps1',
    'scripts\doctor.ps1',
    'scripts\install.ps1',
    'scripts\install-plugin.ps1'
)) {
    $path = Join-Path $repoRoot $relativePath
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-True ($errors.Count -eq 0) "$relativePath has PowerShell parse errors."
}

foreach ($relativePath in @(
    '.codex-plugin\plugin.json',
    '.agents\plugins\marketplace.json'
)) {
    Get-Content -LiteralPath (Join-Path $repoRoot $relativePath) -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
}

$featureTemplates = @(
    'feature-overview.md',
    'implementation-details.md',
    'implementation-effect.md',
    'iteration-roadmap.md',
    'knowledge-application.md',
    'source-index.md'
)
foreach ($templateName in $featureTemplates) {
    $content = Get-Content -LiteralPath (Join-Path $repoRoot "templates\$templateName") -Raw -Encoding UTF8
    Assert-True ($content -match '(?ms)\A---\s+.*?type:\s*code-feature-summary\s+.*?project:\s*<project-id>\s+.*?feature:\s*<feature-id>\s+.*?---') "$templateName is missing the shared feature frontmatter."
}

$bootstrapPowerShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\bootstrap.ps1') -Raw -Encoding UTF8
$normalizeIndex = $bootstrapPowerShell.LastIndexOf('$noteRoot = Normalize-NoteRoot $NoteRoot', [System.StringComparison]::Ordinal)
$installIndex = $bootstrapPowerShell.LastIndexOf('$apiKey = Install-LocalRestApi', [System.StringComparison]::Ordinal)
Assert-True ($normalizeIndex -ge 0 -and $installIndex -ge 0 -and $normalizeIndex -lt $installIndex) 'bootstrap.ps1 must validate NoteRoot before installing the plugin.'
Assert-True ($bootstrapPowerShell -match 'enableInsecureServer') 'bootstrap.ps1 must enable the plugin HTTP server for the explicit fallback.'

$bootstrapShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\bootstrap.sh') -Raw -Encoding UTF8
Assert-True ($bootstrapShell -match 'data\.enableInsecureServer = true') 'bootstrap.sh must enable the plugin HTTP server for the explicit fallback.'
Assert-True ($bootstrapShell -match '\[\[ "\$NOTE_ROOT" != /\* \]\]') 'bootstrap.sh must reject absolute NoteRoot values before trimming them.'

$installShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\install-plugin.sh') -Raw -Encoding UTF8
Assert-True ($installShell.Contains('user_codex_root="${CODEX_HOME:-$HOME/.codex}"')) 'install-plugin.sh must treat CODEX_HOME as the Codex root.'

$doctorPowerShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\doctor.ps1') -Raw -Encoding UTF8
Assert-True ($doctorPowerShell -match 'Invoke-WebRequest -Uri \$endpoint -Method Post') 'doctor.ps1 must perform an MCP initialize request.'
Assert-True (-not $doctorPowerShell.Contains('Skipped HTTP handshake')) 'doctor.ps1 must not report a skipped HTTPS handshake as successful.'

$doctorShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\doctor.sh') -Raw -Encoding UTF8
Assert-True ($doctorShell -match 'bearer_token_env_var') 'doctor.sh must read the credential source from Codex config.'
Assert-True ($doctorShell -match 'method.*initialize') 'doctor.sh must perform an MCP initialize request.'

$testsRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$fixtureRoot = Join-Path $testsRoot ('.tmp-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
try {
    $invalidVault = Join-Path $fixtureRoot 'invalid-note-root-vault'
    New-Item -ItemType Directory -Path $invalidVault | Out-Null
    $invalidNoteRootRejected = $false
    try {
        & (Join-Path $repoRoot 'scripts\bootstrap.ps1') -VaultPath $invalidVault -NoteRoot '..' -Approve
    }
    catch {
        $invalidNoteRootRejected = $true
    }
    Assert-True $invalidNoteRootRejected 'bootstrap.ps1 did not reject an invalid NoteRoot.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $invalidVault '.obsidian'))) 'bootstrap.ps1 mutated the vault before rejecting NoteRoot.'

    $installVault = Join-Path $fixtureRoot 'install-vault'
    $pluginDirectory = Join-Path $installVault '.obsidian\plugins\obsidian-local-rest-api'
    New-Item -ItemType Directory -Path $pluginDirectory -Force | Out-Null
    @{ id = 'obsidian-local-rest-api'; version = '5.1.0' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $pluginDirectory 'manifest.json') -Encoding UTF8
    @{ apiKey = 'test-only-key'; enableInsecureServer = $false } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $pluginDirectory 'data.json') -Encoding UTF8
    $fixtureConfig = Join-Path $fixtureRoot 'codex\config.toml'
    & (Join-Path $repoRoot 'scripts\install.ps1') -VaultPath $installVault -CodexConfigPath $fixtureConfig -AllowInsecureHttp -NoSecretImport | Out-Null
    $fixturePluginData = Get-Content -LiteralPath (Join-Path $pluginDirectory 'data.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([bool]$fixturePluginData.enableInsecureServer) 'install.ps1 did not enable the plugin HTTP server.'
    $fixtureConfigText = Get-Content -LiteralPath $fixtureConfig -Raw -Encoding UTF8
    Assert-True ($fixtureConfigText -match 'http://127\.0\.0\.1:27123/mcp/') 'install.ps1 wrote the wrong HTTP fallback URL.'
}
finally {
    $resolvedFixtureRoot = [System.IO.Path]::GetFullPath($fixtureRoot)
    $expectedPrefix = $testsRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar + '.tmp-'
    if ($resolvedFixtureRoot.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedFixtureRoot)) {
        Remove-Item -LiteralPath $resolvedFixtureRoot -Recurse -Force
    }
}

Write-Output 'Repository validation passed.'
