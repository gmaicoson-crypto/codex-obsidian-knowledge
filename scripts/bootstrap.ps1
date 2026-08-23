[CmdletBinding()]
param(
    [string]$VaultPath,

    [string]$CodexConfigPath,

    [string]$NoteRoot = 'Codex知识库',

    [switch]$Approve,

    [switch]$AllowInsecureHttp,

    [switch]$NoSecretImport
)

$ErrorActionPreference = 'Stop'

$assetMetadataPath = Join-Path $PSScriptRoot 'upstream-assets.json'
if (-not (Test-Path -LiteralPath $assetMetadataPath -PathType Leaf)) {
    throw "Upstream asset metadata is missing: $assetMetadataPath"
}
$assetMetadata = Get-Content -LiteralPath $assetMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
$pluginId = [string]$assetMetadata.pluginId
$localRestApiVersion = [string]$assetMetadata.version
$pluginReleaseBase = [string]$assetMetadata.releaseBase
$assetHashes = @{}
foreach ($asset in $assetMetadata.assets.psobject.Properties) {
    $assetHashes[$asset.Name] = ([string]$asset.Value).ToLowerInvariant()
}
$secretEnvName = 'OBSIDIAN_LOCAL_REST_API_KEY'
$userProfile = [Environment]::GetFolderPath('UserProfile')
$runningOnWindows = $env:OS -eq 'Windows_NT' -or [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$runningOnMacOS = -not $runningOnWindows -and ($IsMacOS -or [Environment]::OSVersion.Platform -eq [PlatformID]::MacOSX)

if ([string]::IsNullOrWhiteSpace($CodexConfigPath)) {
    $codexRoot = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        Join-Path $userProfile '.codex'
    }
    else {
        [System.IO.Path]::GetFullPath($env:CODEX_HOME)
    }
    $CodexConfigPath = Join-Path $codexRoot 'config.toml'
}

function Write-Utf8Json([string]$Path, [object]$Value) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $fileName = [System.IO.Path]::GetFileName($Path)
    $temporary = Join-Path $parent ('.{0}.{1}.tmp' -f $fileName, [guid]::NewGuid().ToString('N'))
    try {
        $json = ConvertTo-Json -InputObject $Value -Depth 20
        [System.IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force | Out-Null
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Write-Utf8Text([string]$Path, [string]$Value, [switch]$OwnerOnly) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $fileName = [System.IO.Path]::GetFileName($Path)
    $temporary = Join-Path $parent ('.{0}.{1}.tmp' -f $fileName, [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($temporary, $Value, [System.Text.UTF8Encoding]::new($false))
        if ($OwnerOnly) {
            if (-not $runningOnMacOS) {
                throw 'Owner-only file permissions are supported by this script on macOS only.'
            }
            $chmod = Get-Command chmod -ErrorAction SilentlyContinue
            if ($null -eq $chmod) {
                throw 'chmod is required to protect the API key file on macOS.'
            }
            & $chmod.Source '600' $temporary
            if ($LASTEXITCODE -ne 0) {
                throw "Could not set owner-only permissions on temporary file: $temporary"
            }
        }
        Move-Item -LiteralPath $temporary -Destination $Path -Force | Out-Null
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-AssetIntegrity([string]$Path, [string]$FileName) {
    if (-not $assetHashes.ContainsKey($FileName)) {
        throw "No SHA-256 is pinned for upstream asset: $FileName"
    }
    $actual = Get-FileSha256 $Path
    if ($actual -ne $assetHashes[$FileName]) {
        throw "SHA-256 verification failed for upstream asset '$FileName'. Expected $($assetHashes[$FileName]); received $actual."
    }
}

function Assert-PluginManifest([string]$Path) {
    try {
        $manifest = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "The downloaded plugin manifest is not valid JSON: $Path"
    }
    if ([string]$manifest.id -ne $pluginId -or [string]$manifest.version -ne $localRestApiVersion) {
        throw "The downloaded plugin manifest does not match the pinned plugin $pluginId $localRestApiVersion."
    }
}

function New-ApiKey {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Get-ObsidianConfigPath {
    if ($runningOnWindows) {
        return Join-Path $env:APPDATA 'Obsidian\obsidian.json'
    }
    if ($runningOnMacOS) {
        return [System.IO.Path]::Combine($userProfile, 'Library', 'Application Support', 'obsidian', 'obsidian.json')
    }
    throw 'This bootstrap script supports Windows and macOS only.'
}

function Resolve-Vault {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $resolved = [System.IO.Path]::GetFullPath($RequestedPath)
        if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
            throw "Vault directory does not exist: $resolved"
        }
        return $resolved
    }

    $configPath = Get-ObsidianConfigPath
    $candidates = @()
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        try {
            $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $config.vaults) {
                foreach ($entry in $config.vaults.psobject.Properties) {
                    $candidatePath = [string]$entry.Value.path
                    if (-not [string]::IsNullOrWhiteSpace($candidatePath) -and (Test-Path -LiteralPath $candidatePath -PathType Container)) {
                        $candidates += [PSCustomObject]@{
                            Path = [System.IO.Path]::GetFullPath($candidatePath)
                            Open = [bool]$entry.Value.open
                        }
                    }
                }
            }
        }
        catch {
            Write-Warning "Could not parse Obsidian vault registry: $configPath"
        }
    }

    if ($candidates.Count -eq 1) {
        return $candidates[0].Path
    }

    $openCandidate = @($candidates | Where-Object { $_.Open })
    if ($openCandidate.Count -eq 1) {
        return $openCandidate[0].Path
    }

    if ($candidates.Count -gt 1) {
        Write-Host 'Multiple Obsidian vaults were found:'
        for ($index = 0; $index -lt $candidates.Count; $index++) {
            Write-Host ("[{0}] {1}" -f ($index + 1), $candidates[$index].Path)
        }
        $selection = Read-Host 'Choose a vault number'
        $number = 0
        if (-not [int]::TryParse($selection, [ref]$number) -or $number -lt 1 -or $number -gt $candidates.Count) {
            throw 'Invalid vault selection.'
        }
        return $candidates[$number - 1].Path
    }

    $manual = Read-Host 'Enter the absolute path of the Obsidian vault'
    if ([string]::IsNullOrWhiteSpace($manual)) {
        throw 'An Obsidian vault path is required.'
    }
    $manualResolved = [System.IO.Path]::GetFullPath($manual)
    if (-not (Test-Path -LiteralPath $manualResolved -PathType Container)) {
        throw "Vault directory does not exist: $manualResolved"
    }
    return $manualResolved
}

function Confirm-Bootstrap {
    if ($Approve) {
        return
    }
    $answer = Read-Host "This will download '$pluginId', modify the selected Obsidian vault settings, and update Codex MCP configuration. Continue? (y/N)"
    if ($answer -notmatch '^(?i:y|yes|是|确认)$') {
        throw 'Bootstrap cancelled by user.'
    }
}

function Normalize-NoteRoot([string]$Path) {
    $normalized = ([string]$Path).Trim().Replace('\', '/')
    if ($normalized -eq '.') {
        return ''
    }
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return ''
    }
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
        if ($segment.Length -gt 120) {
            throw 'Each NoteRoot segment must be 120 characters or fewer.'
        }
    }
    $result = ($segments -join '/')
    if ($result.Length -gt 240) {
        throw 'NoteRoot must be 240 characters or fewer.'
    }
    return $result
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
        if ($withoutComment -match '^(?<key>url|bearer_token_env_var|startup_timeout_sec|tool_timeout_sec)\s*=\s*"(?<value>[^"]*)"\s*$') {
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
        bearer_token_env_var = $secretEnvName
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
        "bearer_token_env_var = `"$secretEnvName`""
        'startup_timeout_sec = 20'
        'tool_timeout_sec = 60'
    ) -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($currentConfig)) {
        return $desiredSection + [Environment]::NewLine
    }
    return $currentConfig.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $desiredSection + [Environment]::NewLine
}

function Install-LocalRestApi([string]$Vault, [bool]$EnableInsecureServer, [string]$NoteRoot, [string]$Endpoint) {
    $obsidianDir = Join-Path $Vault '.obsidian'
    $pluginDir = Join-Path $obsidianDir "plugins\$pluginId"
    $communityPluginsPath = Join-Path $obsidianDir 'community-plugins.json'
    $appSettingsPath = Join-Path $obsidianDir 'app.json'
    $settingsPath = Join-Path $Vault '.codex-obsidian-knowledge.json'
    $resolvedConfig = [System.IO.Path]::GetFullPath($CodexConfigPath)
    $temporaryDir = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-obsidian-$([guid]::NewGuid().ToString('N'))")
    $stagingPluginDir = Join-Path $temporaryDir $pluginId
    $backupRoot = Join-Path $temporaryDir 'backup'
    New-Item -ItemType Directory -Path $stagingPluginDir -Force | Out-Null
    try {
        if (Test-Path -LiteralPath $pluginDir -PathType Container) {
            Copy-Item -Path (Join-Path $pluginDir '*') -Destination $stagingPluginDir -Recurse -Force | Out-Null
        }
        foreach ($fileName in @('main.js', 'manifest.json', 'styles.css')) {
            $downloadPath = Join-Path $stagingPluginDir $fileName
            Write-Host "Downloading and verifying Local REST API $fileName..."
            Invoke-WebRequest -Uri "$pluginReleaseBase/$fileName" -OutFile $downloadPath -UseBasicParsing
            Assert-AssetIntegrity $downloadPath $fileName
        }
        Assert-PluginManifest (Join-Path $stagingPluginDir 'manifest.json')

        $stagingDataPath = Join-Path $stagingPluginDir 'data.json'
        $pluginData = [PSCustomObject]@{}
        if (Test-Path -LiteralPath $stagingDataPath -PathType Leaf) {
            try {
                $pluginData = Get-Content -LiteralPath $stagingDataPath -Raw -Encoding UTF8 | ConvertFrom-Json
            }
            catch {
                throw "The existing Local REST API settings file is not valid JSON: $stagingDataPath"
            }
            if ($null -eq $pluginData -or $pluginData -is [System.Array] -or $pluginData -is [string] -or $pluginData -is [System.ValueType]) { throw "The Local REST API settings file must contain a JSON object: $stagingDataPath" }
        }
        $apiKey = [string]$pluginData.apiKey
        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            $apiKey = New-ApiKey
            if ($pluginData.psobject.Properties.Name -contains 'apiKey') { $pluginData.apiKey = $apiKey }
            else { $pluginData | Add-Member -MemberType NoteProperty -Name apiKey -Value $apiKey }
        }
        if ($pluginData.psobject.Properties.Name -contains 'enableInsecureServer') {
            $pluginData.enableInsecureServer = $EnableInsecureServer
        }
        else {
            $pluginData | Add-Member -MemberType NoteProperty -Name enableInsecureServer -Value $EnableInsecureServer
        }
        Write-Utf8Json $stagingDataPath $pluginData

        $enabledPlugins = @()
        if (Test-Path -LiteralPath $communityPluginsPath -PathType Leaf) {
            try {
                $communityText = Get-Content -LiteralPath $communityPluginsPath -Raw -Encoding UTF8
                $communityJson = $communityText.TrimStart([char]0xFEFF).TrimStart()
                if (-not $communityJson.StartsWith('[')) {
                    throw 'The top-level JSON value is not an array.'
                }
                $communityRaw = @($communityText | ConvertFrom-Json)
            }
            catch { throw "The existing community-plugins.json is not valid JSON: $communityPluginsPath" }
            $enabledPlugins = @($communityRaw)
        }
        if ($enabledPlugins -notcontains $pluginId) { $enabledPlugins += $pluginId }
        $stagingCommunityPath = Join-Path $temporaryDir 'community-plugins.json'
        Write-Utf8Json $stagingCommunityPath $enabledPlugins

        $appSettings = [PSCustomObject]@{}
        if (Test-Path -LiteralPath $appSettingsPath -PathType Leaf) {
            try { $appSettings = Get-Content -LiteralPath $appSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json }
            catch { throw "The existing app.json is not valid JSON: $appSettingsPath" }
            if ($null -eq $appSettings -or $appSettings -is [System.Array] -or $appSettings -is [string] -or $appSettings -is [System.ValueType]) { throw "app.json must contain a JSON object: $appSettingsPath" }
        }
        if ($appSettings.psobject.Properties.Name -contains 'communityPlugins') { $appSettings.communityPlugins = $true }
        else { $appSettings | Add-Member -MemberType NoteProperty -Name communityPlugins -Value $true }
        $stagingAppPath = Join-Path $temporaryDir 'app.json'
        Write-Utf8Json $stagingAppPath $appSettings

        $stagingSettingsPath = Join-Path $temporaryDir '.codex-obsidian-knowledge.json'
        Write-Utf8Json $stagingSettingsPath (@{ version = 1; noteRoot = $NoteRoot })
        $stagingConfigPath = Join-Path $temporaryDir 'config.toml'
        Write-Utf8Text $stagingConfigPath (Get-DesiredCodexConfig $Endpoint)

        $commitPlan = @(
            [PSCustomObject]@{ Source = $stagingPluginDir; Target = $pluginDir },
            [PSCustomObject]@{ Source = $stagingCommunityPath; Target = $communityPluginsPath },
            [PSCustomObject]@{ Source = $stagingAppPath; Target = $appSettingsPath },
            [PSCustomObject]@{ Source = $stagingSettingsPath; Target = $settingsPath },
            [PSCustomObject]@{ Source = $stagingConfigPath; Target = $resolvedConfig }
        )
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        $backups = @()
        $committed = @()
        try {
            $backupIndex = 0
            foreach ($item in $commitPlan) {
                if (Test-Path -LiteralPath $item.Target) {
                    $backupPath = Join-Path $backupRoot ("item-{0}" -f $backupIndex)
                    Move-Item -LiteralPath $item.Target -Destination $backupPath -Force | Out-Null
                    $backups += [PSCustomObject]@{ Target = $item.Target; Backup = $backupPath }
                    $backupIndex++
                }
                $targetParent = Split-Path -Parent $item.Target
                New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
                Move-Item -LiteralPath $item.Source -Destination $item.Target -Force | Out-Null
                $committed += $item.Target
            }
        }
        catch {
            for ($index = $committed.Count - 1; $index -ge 0; $index--) {
                if (Test-Path -LiteralPath $committed[$index]) { Remove-Item -LiteralPath $committed[$index] -Recurse -Force }
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
        return $apiKey
    }
    finally {
        if (Test-Path -LiteralPath $temporaryDir) { Remove-Item -LiteralPath $temporaryDir -Recurse -Force }
    }
}

function Set-SecretEnvironment([string]$ApiKey) {
    if ($NoSecretImport) {
        Write-Output "Skipped secret import because -NoSecretImport was supplied. Set $secretEnvName before starting Codex."
        return
    }

    if ($runningOnWindows) {
        [Environment]::SetEnvironmentVariable($secretEnvName, $ApiKey, 'User')
        Set-Item -Path "Env:$secretEnvName" -Value $ApiKey
        Write-Output "Stored the API key in the current user's $secretEnvName environment variable."
        return
    }

    if ($runningOnMacOS) {
        Set-Item -Path "Env:$secretEnvName" -Value $ApiKey
        $launchctl = Get-Command launchctl -ErrorAction SilentlyContinue
        if ($null -ne $launchctl) {
            & $launchctl.Source setenv $secretEnvName $ApiKey
        }

        $zshEnvPath = Join-Path $userProfile '.zshenv'
        $beginMarker = '# BEGIN codex-obsidian-knowledge'
        $endMarker = '# END codex-obsidian-knowledge'
        $existing = if (Test-Path -LiteralPath $zshEnvPath -PathType Leaf) { Get-Content -LiteralPath $zshEnvPath -Raw -Encoding UTF8 } else { '' }
        $block = "$beginMarker`nexport $secretEnvName='$ApiKey'`n$endMarker"
        $pattern = "(?ms)^$([regex]::Escape($beginMarker))\r?\n.*?\r?\n$([regex]::Escape($endMarker))\r?\n?"
        $updated = [regex]::Replace($existing, $pattern, '').TrimEnd()
        if ($updated.Length -gt 0) {
            $updated += "`n`n"
        }
        $updated += $block + "`n"
        Write-Utf8Text $zshEnvPath $updated -OwnerOnly
        Write-Output "Configured $secretEnvName for macOS GUI processes and future zsh sessions."
        return
    }

    throw 'Unsupported operating system.'
}

function Assert-CodexMcpConfig([string]$Endpoint) {
    $null = Get-DesiredCodexConfig $Endpoint
    Write-Host "Codex MCP configuration is compatible with $Endpoint."
}
$resolvedVault = Resolve-Vault $VaultPath
$noteRoot = Normalize-NoteRoot $NoteRoot
$protocol = 'https'
$port = 27124
if ($AllowInsecureHttp) {
    $protocol = 'http'
    $port = 27123
}
$endpoint = "${protocol}://127.0.0.1:${port}/mcp/"

Assert-CodexMcpConfig $endpoint
Confirm-Bootstrap
$apiKey = Install-LocalRestApi $resolvedVault $AllowInsecureHttp.IsPresent $noteRoot $endpoint
Set-SecretEnvironment $apiKey

Write-Output ''
Write-Output "Local REST API was installed and enabled for vault: $resolvedVault"
Write-Output "MCP endpoint: $endpoint"
Write-Output 'Restart Obsidian once so it loads the downloaded plugin, then restart Codex.'
Write-Output 'Run scripts/doctor.ps1 (Windows) or scripts/doctor.sh (macOS) to verify the connection.'
