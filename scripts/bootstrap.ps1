[CmdletBinding()]
param(
    [string]$VaultPath,

    [string]$CodexConfigPath = ([System.IO.Path]::Combine([Environment]::GetFolderPath('UserProfile'), '.codex', 'config.toml')),

    [string]$NoteRoot = 'Codex知识库',

    [switch]$Approve,

    [switch]$AllowInsecureHttp,

    [switch]$NoSecretImport
)

$ErrorActionPreference = 'Stop'

$pluginId = 'obsidian-local-rest-api'
$localRestApiVersion = '5.1.0'
$pluginReleaseBase = "https://github.com/coddingtonbear/obsidian-local-rest-api/releases/download/$localRestApiVersion"
$secretEnvName = 'OBSIDIAN_LOCAL_REST_API_KEY'
$userProfile = [Environment]::GetFolderPath('UserProfile')
$runningOnWindows = $env:OS -eq 'Windows_NT' -or [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$runningOnMacOS = -not $runningOnWindows -and ($IsMacOS -or [Environment]::OSVersion.Platform -eq [PlatformID]::MacOSX)

function Write-Utf8Json([string]$Path, [object]$Value) {
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
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
        Write-Output 'Multiple Obsidian vaults were found:'
        for ($index = 0; $index -lt $candidates.Count; $index++) {
            Write-Output ("[{0}] {1}" -f ($index + 1), $candidates[$index].Path)
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
    $normalized = $Path.Trim().Replace('\', '/')
    if ($normalized -eq '.') {
        return ''
    }
    if ([System.IO.Path]::IsPathRooted($normalized) -or $normalized.StartsWith('/') -or $normalized -match '(^|/)\.\.(/|$)') {
        throw 'NoteRoot must be a relative path inside the Obsidian Vault and cannot contain .. segments.'
    }
    return $normalized.Trim('/')
}

function Install-LocalRestApi([string]$Vault) {
    $obsidianDir = Join-Path $Vault '.obsidian'
    $pluginDir = Join-Path $obsidianDir "plugins\$pluginId"
    New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null

    $temporaryDir = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-obsidian-$([guid]::NewGuid().ToString('N'))")
    New-Item -ItemType Directory -Path $temporaryDir -Force | Out-Null
    try {
        foreach ($fileName in @('main.js', 'manifest.json', 'styles.css')) {
            $downloadPath = Join-Path $temporaryDir $fileName
            Write-Output "Downloading Local REST API $fileName..."
            Invoke-WebRequest -Uri "$pluginReleaseBase/$fileName" -OutFile $downloadPath -UseBasicParsing
            Move-Item -LiteralPath $downloadPath -Destination (Join-Path $pluginDir $fileName) -Force
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryDir) {
            Remove-Item -LiteralPath $temporaryDir -Recurse -Force
        }
    }

    $dataPath = Join-Path $pluginDir 'data.json'
    $pluginData = [PSCustomObject]@{}
    if (Test-Path -LiteralPath $dataPath -PathType Leaf) {
        try {
            $pluginData = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            throw "The existing Local REST API settings file is not valid JSON: $dataPath"
        }
    }

    $apiKey = [string]$pluginData.apiKey
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        $apiKey = New-ApiKey
        if ($pluginData.psobject.Properties.Name -contains 'apiKey') {
            $pluginData.apiKey = $apiKey
        }
        else {
            $pluginData | Add-Member -MemberType NoteProperty -Name apiKey -Value $apiKey
        }
        Write-Utf8Json $dataPath $pluginData
    }

    New-Item -ItemType Directory -Path $obsidianDir -Force | Out-Null
    $communityPluginsPath = Join-Path $obsidianDir 'community-plugins.json'
    $enabledPlugins = @()
    if (Test-Path -LiteralPath $communityPluginsPath -PathType Leaf) {
        try {
            $enabledPlugins = @(Get-Content -LiteralPath $communityPluginsPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        }
        catch {
            throw "The existing community-plugins.json is not valid JSON: $communityPluginsPath"
        }
    }
    if ($enabledPlugins -notcontains $pluginId) {
        $enabledPlugins += $pluginId
        Write-Utf8Json $communityPluginsPath $enabledPlugins
    }

    $appSettingsPath = Join-Path $obsidianDir 'app.json'
    $appSettings = [PSCustomObject]@{}
    if (Test-Path -LiteralPath $appSettingsPath -PathType Leaf) {
        try {
            $appSettings = Get-Content -LiteralPath $appSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            throw "The existing app.json is not valid JSON: $appSettingsPath"
        }
    }
    if ($appSettings.psobject.Properties.Name -contains 'communityPlugins') {
        $appSettings.communityPlugins = $true
    }
    else {
        $appSettings | Add-Member -MemberType NoteProperty -Name communityPlugins -Value $true
    }
    Write-Utf8Json $appSettingsPath $appSettings

    return $apiKey
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
        Set-Content -LiteralPath $zshEnvPath -Value $updated -Encoding UTF8
        Write-Output "Configured $secretEnvName for macOS GUI processes and future zsh sessions."
        return
    }

    throw 'Unsupported operating system.'
}

function Set-CodexMcp([string]$Endpoint) {
    $resolvedConfig = [System.IO.Path]::GetFullPath($CodexConfigPath)
    $configDirectory = Split-Path -Parent $resolvedConfig
    if (-not (Test-Path -LiteralPath $configDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
    }

    $currentConfig = if (Test-Path -LiteralPath $resolvedConfig -PathType Leaf) { Get-Content -LiteralPath $resolvedConfig -Raw -Encoding UTF8 } else { '' }
    $desiredSection = @"
[mcp_servers.obsidian]
url = "$Endpoint"
bearer_token_env_var = "$secretEnvName"
startup_timeout_sec = 20
tool_timeout_sec = 60
"@.Trim()

    $sectionMatch = [regex]::Match($currentConfig, '(?ms)^\[mcp_servers\.obsidian\]\s*$.*?(?=^\[|\z)')
    if ($sectionMatch.Success) {
        $existingSection = $sectionMatch.Value
        $expectedLines = @(
            "url = ""$Endpoint""",
            "bearer_token_env_var = ""$secretEnvName""",
            'startup_timeout_sec = 20',
            'tool_timeout_sec = 60'
        )
        foreach ($line in $expectedLines) {
            if ($existingSection -notmatch [regex]::Escape($line)) {
                throw "An existing [mcp_servers.obsidian] section differs from the requested endpoint. Review $resolvedConfig manually; no config was changed."
            }
        }
        Write-Output "Codex MCP section already matches $Endpoint."
        return
    }

    if ([string]::IsNullOrWhiteSpace($currentConfig)) {
        $newConfig = $desiredSection + [Environment]::NewLine
    }
    else {
        $newConfig = $currentConfig.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $desiredSection + [Environment]::NewLine
    }
    Set-Content -LiteralPath $resolvedConfig -Value $newConfig -Encoding UTF8
    Write-Output "Added the Obsidian MCP section to $resolvedConfig."
}

$resolvedVault = Resolve-Vault $VaultPath
Confirm-Bootstrap
$apiKey = Install-LocalRestApi $resolvedVault
$noteRoot = Normalize-NoteRoot $NoteRoot
$settingsPath = Join-Path $resolvedVault '.codex-obsidian-knowledge.json'
Write-Utf8Json $settingsPath (@{ version = 1; noteRoot = $noteRoot })

$protocol = 'https'
$port = 27124
if ($AllowInsecureHttp) {
    $protocol = 'http'
    $port = 27123
}
$endpoint = "${protocol}://127.0.0.1:${port}/mcp/"

Set-SecretEnvironment $apiKey
Set-CodexMcp $endpoint

Write-Output ''
Write-Output "Local REST API was installed and enabled for vault: $resolvedVault"
Write-Output "MCP endpoint: $endpoint"
Write-Output 'Restart Obsidian once so it loads the downloaded plugin, then restart Codex.'
Write-Output 'Run scripts/doctor.ps1 (Windows) or scripts/doctor.sh (macOS) to verify the connection.'
