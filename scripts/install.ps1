[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VaultPath,

    [string]$CodexConfigPath,

    [ValidateSet('http', 'https')]
    [string]$Protocol = 'https',

    [ValidateRange(1, 65535)]
    [int]$Port = 27124,

    [string]$NoteRoot = 'Codex知识库',

    [switch]$AllowInsecureHttp,

    [switch]$NoSecretImport
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSScriptRoot
$assetMetadataPath = Join-Path $PSScriptRoot 'upstream-assets.json'
if (-not (Test-Path -LiteralPath $assetMetadataPath -PathType Leaf)) {
    throw "Upstream asset metadata is missing: $assetMetadataPath"
}
$assetMetadata = Get-Content -LiteralPath $assetMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
$pluginId = [string]$assetMetadata.pluginId
$pluginVersion = [string]$assetMetadata.version
$userProfile = [Environment]::GetFolderPath('UserProfile')
if ([string]::IsNullOrWhiteSpace($CodexConfigPath)) {
    $codexRoot = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        Join-Path $userProfile '.codex'
    }
    else {
        [System.IO.Path]::GetFullPath($env:CODEX_HOME)
    }
    $CodexConfigPath = Join-Path $codexRoot 'config.toml'
}

function Normalize-NoteRoot([string]$Path) {
    $normalized = ([string]$Path).Trim().Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($normalized) -or $normalized -eq '.') { return '' }
    if ([System.IO.Path]::IsPathRooted($normalized) -or $normalized.StartsWith('/') -or $normalized -match '(^|/)\.\.(/|$)') {
        throw 'NoteRoot must be a relative path inside the Obsidian Vault and cannot contain .. segments.'
    }
    $segments = $normalized.Trim('/').Split('/')
    foreach ($segment in $segments) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -in @('.', '..')) {
            throw 'NoteRoot contains an empty or navigation path segment.'
        }
        if ($segment -match '[\x00-\x1F]' -or $segment -match '[<>:"|?*]' -or $segment -match '[. ]$' -or $segment -match '^\s') {
            throw "NoteRoot contains an invalid filesystem segment: $segment"
        }
        if ($segment -match '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$') {
            throw "NoteRoot contains a reserved Windows filename: $segment"
        }
        if ($segment.Length -gt 120) { throw 'Each NoteRoot segment must be 120 characters or fewer.' }
    }
    $result = $segments -join '/'
    if ($result.Length -gt 240) { throw 'NoteRoot must be 240 characters or fewer.' }
    return $result
}

function Write-Utf8JsonAtomic([string]$Path, [object]$Value) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $fileName = [System.IO.Path]::GetFileName($Path)
    $temporary = Join-Path $parent ('.{0}.{1}.tmp' -f $fileName, [guid]::NewGuid().ToString('N'))
    try {
        $json = ConvertTo-Json -InputObject $Value -Depth 20
        [System.IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force | Out-Null
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Write-Utf8TextAtomic([string]$Path, [string]$Value) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $fileName = [System.IO.Path]::GetFileName($Path)
    $temporary = Join-Path $parent ('.{0}.{1}.tmp' -f $fileName, [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($temporary, $Value, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force | Out-Null
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Get-McpConfigValues([string]$ConfigText) {
    $insideSection = $false
    $sectionExists = $false
    $values = @{}
    foreach ($line in ($ConfigText -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -gt 0 -and $trimmed[0] -eq [char]0xFEFF) { $trimmed = $trimmed.Substring(1).TrimStart() }
        if ($trimmed -match '^\[(?<section>[^\]]+)\]\s*(?:#.*)?$') {
            $insideSection = $Matches.section -eq 'mcp_servers.obsidian'
            if ($insideSection) { $sectionExists = $true }
            continue
        }
        if (-not $insideSection) { continue }
        $withoutComment = $trimmed -replace '\s+#.*$', ''
        if ($withoutComment -match '^(?<key>url|bearer_token_env_var)\s*=\s*"(?<value>[^"]*)"\s*$') {
            $values[$Matches.key] = $Matches.value
            continue
        }
        if ($withoutComment -match '^(?<key>startup_timeout_sec|tool_timeout_sec)\s*=\s*(?<value>[0-9]+)\s*$') {
            $values[$Matches.key] = $Matches.value
        }
    }
    return [PSCustomObject]@{ Exists = $sectionExists; Values = $values }
}

function Get-DesiredCodexConfig([string]$Endpoint) {
    $resolvedConfig = [System.IO.Path]::GetFullPath($CodexConfigPath)
    $currentConfig = if (Test-Path -LiteralPath $resolvedConfig -PathType Leaf) {
        Get-Content -LiteralPath $resolvedConfig -Raw -Encoding UTF8
    }
    else { '' }
    $parsed = Get-McpConfigValues $currentConfig
    $expected = @{
        url = $Endpoint
        bearer_token_env_var = 'OBSIDIAN_LOCAL_REST_API_KEY'
        startup_timeout_sec = '20'
        tool_timeout_sec = '60'
    }
    if ($parsed.Exists) {
        foreach ($key in $expected.Keys) {
            if (-not $parsed.Values.ContainsKey($key) -or [string]$parsed.Values[$key] -ne $expected[$key]) {
                throw "An existing [mcp_servers.obsidian] section differs from the requested endpoint. Review $resolvedConfig manually; no files were changed."
            }
        }
        return $currentConfig
    }
    $desiredSection = @(
        '[mcp_servers.obsidian]'
        "url = `"$Endpoint`""
        'bearer_token_env_var = "OBSIDIAN_LOCAL_REST_API_KEY"'
        'startup_timeout_sec = 20'
        'tool_timeout_sec = 60'
    ) -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($currentConfig)) { return $desiredSection + [Environment]::NewLine }
    return $currentConfig.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $desiredSection + [Environment]::NewLine
}

function Commit-Files([object[]]$Items) {
    $transactionRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-obsidian-config-$([guid]::NewGuid().ToString('N'))")
    $backupRoot = Join-Path $transactionRoot 'backup'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $backups = @()
    $committed = @()
    try {
        $backupIndex = 0
        foreach ($item in $Items) {
            if (Test-Path -LiteralPath $item.Target) {
                $backupPath = Join-Path $backupRoot ("item-{0}" -f $backupIndex)
                Move-Item -LiteralPath $item.Target -Destination $backupPath -Force | Out-Null
                $backups += [PSCustomObject]@{ Target = $item.Target; Backup = $backupPath }
                $backupIndex++
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $item.Target) -Force | Out-Null
            Move-Item -LiteralPath $item.Source -Destination $item.Target -Force | Out-Null
            $committed += $item.Target
        }
    }
    catch {
        for ($index = $committed.Count - 1; $index -ge 0; $index--) {
            if (Test-Path -LiteralPath $committed[$index]) { Remove-Item -LiteralPath $committed[$index] -Force }
        }
        for ($index = $backups.Count - 1; $index -ge 0; $index--) {
            $backup = $backups[$index]
            if (Test-Path -LiteralPath $backup.Backup) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $backup.Target) -Force | Out-Null
                Move-Item -LiteralPath $backup.Backup -Destination $backup.Target -Force | Out-Null
            }
        }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $transactionRoot) { Remove-Item -LiteralPath $transactionRoot -Recurse -Force }
    }
}

$resolvedVault = [System.IO.Path]::GetFullPath($VaultPath)
$resolvedConfig = [System.IO.Path]::GetFullPath($CodexConfigPath)
$normalizedNoteRoot = Normalize-NoteRoot $NoteRoot
$pluginDir = Join-Path $resolvedVault ".obsidian\plugins\$pluginId"
$manifestPath = Join-Path $pluginDir 'manifest.json'
$dataPath = Join-Path $pluginDir 'data.json'
$settingsPath = Join-Path $resolvedVault '.codex-obsidian-knowledge.json'

if (-not (Test-Path -LiteralPath $resolvedVault -PathType Container)) { throw "Vault directory does not exist: $resolvedVault" }
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or -not (Test-Path -LiteralPath (Join-Path $pluginDir 'main.js') -PathType Leaf)) {
    throw "Obsidian Local REST API plugin files are incomplete: $pluginDir"
}
try { $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "The Local REST API manifest is not valid JSON: $manifestPath" }
if ([string]$manifest.id -ne $pluginId -or [string]$manifest.version -ne $pluginVersion) {
    throw "The installed plugin does not match the pinned version $pluginId $pluginVersion."
}
if (-not (Test-Path -LiteralPath $dataPath -PathType Leaf)) { throw "Obsidian Local REST API plugin data is missing: $dataPath" }
try { $pluginData = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "The Local REST API data.json is not valid JSON: $dataPath" }
if ($null -eq $pluginData -or $pluginData -is [System.Array] -or $pluginData -is [string] -or $pluginData -is [System.ValueType]) { throw "The Local REST API data.json must contain a JSON object: $dataPath" }
$apiKey = [string]$pluginData.apiKey
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'The Local REST API plugin has no API key. Open its settings in Obsidian and generate one.' }

if ($Protocol -eq 'http' -and -not $AllowInsecureHttp) { throw 'Using HTTP requires the explicit -AllowInsecureHttp switch.' }
if ($AllowInsecureHttp) {
    $Protocol = 'http'
    if ($Port -eq 27124) { $Port = 27123 }
    if ($pluginData.psobject.Properties.Name -contains 'enableInsecureServer') { $pluginData.enableInsecureServer = $true }
    else { $pluginData | Add-Member -MemberType NoteProperty -Name enableInsecureServer -Value $true }
}
$endpoint = '{0}://127.0.0.1:{1}/mcp/' -f $Protocol, $Port
$desiredConfig = Get-DesiredCodexConfig $endpoint

$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-obsidian-install-$([guid]::NewGuid().ToString('N'))")
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
try {
    $stagingDataPath = Join-Path $stageRoot 'data.json'
    Write-Utf8JsonAtomic $stagingDataPath $pluginData
    $stagingSettingsPath = Join-Path $stageRoot '.codex-obsidian-knowledge.json'
    Write-Utf8JsonAtomic $stagingSettingsPath (@{ version = 1; noteRoot = $normalizedNoteRoot })
    $stagingConfigPath = Join-Path $stageRoot 'config.toml'
    Write-Utf8TextAtomic $stagingConfigPath $desiredConfig
    Commit-Files @(
        [PSCustomObject]@{ Source = $stagingDataPath; Target = $dataPath },
        [PSCustomObject]@{ Source = $stagingSettingsPath; Target = $settingsPath },
        [PSCustomObject]@{ Source = $stagingConfigPath; Target = $resolvedConfig }
    )
}
finally {
    if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
}

if (-not $NoSecretImport) {
    [Environment]::SetEnvironmentVariable('OBSIDIAN_LOCAL_REST_API_KEY', $apiKey, 'User')
    Set-Item -Path 'Env:OBSIDIAN_LOCAL_REST_API_KEY' -Value $apiKey
    Write-Output "Imported the API key into the current user's OBSIDIAN_LOCAL_REST_API_KEY environment variable."
}
else {
    Write-Output 'Skipped environment-variable import because -NoSecretImport was supplied.'
}
if ([string]::IsNullOrWhiteSpace($normalizedNoteRoot)) { Write-Output 'Knowledge note root: Vault root' }
else { Write-Output "Knowledge note root: $normalizedNoteRoot" }
Write-Output "Endpoint: $endpoint"
Write-Output 'Restart Codex so it reloads the MCP configuration and environment variable.'
