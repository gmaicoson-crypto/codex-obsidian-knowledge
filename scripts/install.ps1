[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VaultPath,

    [string]$CodexConfigPath = (Join-Path $env:USERPROFILE '.codex\config.toml'),

    [ValidateSet('http', 'https')]
    [string]$Protocol = 'https',

    [ValidateRange(1, 65535)]
    [int]$Port = 27124,

    [string]$NoteRoot = 'Codex知识库',

    [switch]$AllowInsecureHttp,

    [switch]$NoSecretImport
)

$ErrorActionPreference = 'Stop'

function Get-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path)
}

function Normalize-NoteRoot([string]$Path) {
    $normalized = $Path.Trim().Replace('\', '/')
    if ($normalized -eq '.') {
        return ''
    }
    if ([System.IO.Path]::IsPathRooted($normalized) -or $normalized.StartsWith('/') -or $normalized -match '(^|/)\.\.(/|$)') {
        throw 'NoteRoot must be a relative path inside the Obsidian Vault and cannot contain .. segments.'
    }
    return $normalized.Trim('/')
}

$resolvedVault = Get-FullPath $VaultPath
$resolvedConfig = Get-FullPath $CodexConfigPath
$normalizedNoteRoot = Normalize-NoteRoot $NoteRoot
$pluginDir = Join-Path $resolvedVault '.obsidian\plugins\obsidian-local-rest-api'
$manifestPath = Join-Path $pluginDir 'manifest.json'
$dataPath = Join-Path $pluginDir 'data.json'
$settingsPath = Join-Path $resolvedVault '.codex-obsidian-knowledge.json'

if (-not (Test-Path -LiteralPath $resolvedVault -PathType Container)) {
    throw "Vault directory does not exist: $resolvedVault"
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Obsidian Local REST API plugin is not installed: $manifestPath"
}
if (-not (Test-Path -LiteralPath $dataPath -PathType Leaf)) {
    throw "Obsidian Local REST API plugin data is missing. Open Obsidian and enable the plugin first: $dataPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$pluginData = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
$apiKey = [string]$pluginData.apiKey
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw 'The Local REST API plugin has no API key. Open its settings in Obsidian and generate one.'
}

if ($AllowInsecureHttp) {
    $Protocol = 'http'
    if ($Port -eq 27124) {
        $Port = 27123
    }
}

$endpoint = '{0}://127.0.0.1:{1}/mcp/' -f $Protocol, $Port
$envName = 'OBSIDIAN_LOCAL_REST_API_KEY'

if (-not $NoSecretImport) {
    [Environment]::SetEnvironmentVariable($envName, $apiKey, 'User')
    Write-Output "Imported the API key into the current user's $envName environment variable."
}
else {
    Write-Output "Skipped environment-variable import because -NoSecretImport was supplied."
}

$knowledgeSettings = @{
    version = 1
    noteRoot = $normalizedNoteRoot
} | ConvertTo-Json -Depth 4
Set-Content -LiteralPath $settingsPath -Value $knowledgeSettings -Encoding UTF8
if ([string]::IsNullOrWhiteSpace($normalizedNoteRoot)) {
    Write-Output "Knowledge note root: Vault root"
}
else {
    Write-Output "Knowledge note root: $normalizedNoteRoot"
}

$configDirectory = Split-Path -Parent $resolvedConfig
if (-not (Test-Path -LiteralPath $configDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
}

$currentConfig = ''
if (Test-Path -LiteralPath $resolvedConfig -PathType Leaf) {
    $currentConfig = Get-Content -LiteralPath $resolvedConfig -Raw -Encoding UTF8
}

$desiredSection = @"
[mcp_servers.obsidian]
url = "$endpoint"
bearer_token_env_var = "$envName"
startup_timeout_sec = 20
tool_timeout_sec = 60
"@
$desiredSection = $desiredSection.Trim()

$sectionMatch = [regex]::Match($currentConfig, '(?ms)^\[mcp_servers\.obsidian\]\s*$.*?(?=^\[|\z)')
if ($sectionMatch.Success) {
    $existingSection = $sectionMatch.Value
    $expectedLines = @(
        ('url = "{0}"' -f $endpoint),
        ('bearer_token_env_var = "{0}"' -f $envName),
        'startup_timeout_sec = 20',
        'tool_timeout_sec = 60'
    )
    foreach ($line in $expectedLines) {
        if ($existingSection -notmatch [regex]::Escape($line)) {
            throw "An existing [mcp_servers.obsidian] section differs from the requested endpoint. Review $resolvedConfig manually; no config was changed."
        }
    }
    Write-Output "Codex MCP section already matches $endpoint."
}
else {
    if ([string]::IsNullOrWhiteSpace($currentConfig)) {
        $newConfig = $desiredSection + [Environment]::NewLine
    }
    else {
        $newConfig = $currentConfig.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $desiredSection + [Environment]::NewLine
    }
    Set-Content -LiteralPath $resolvedConfig -Value $newConfig -Encoding UTF8
    Write-Output "Added the Obsidian MCP section to $resolvedConfig."
}

Write-Output "Endpoint: $endpoint"
Write-Output 'Restart Codex so it reloads the MCP configuration and environment variable.'
