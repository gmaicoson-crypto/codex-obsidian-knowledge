[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('RotateKey', 'Disconnect', 'Uninstall')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VaultPath,

    [string]$CodexConfigPath,

    [ValidateSet('User', 'Process')]
    [string]$SecretScope = 'User',

    [switch]$Approve
)

$ErrorActionPreference = 'Stop'
$secretEnvName = 'OBSIDIAN_LOCAL_REST_API_KEY'

if (-not $Approve) {
    throw "$Action changes the selected Vault and current-user Codex connection. Re-run with -Approve after the user confirms."
}
if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
    throw 'Use connection-maintenance.sh on macOS.'
}

$metadataPath = Join-Path $PSScriptRoot 'upstream-assets.json'
$metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
$pluginId = [string]$metadata.pluginId
$resolvedVault = [System.IO.Path]::GetFullPath($VaultPath)
if (-not (Test-Path -LiteralPath $resolvedVault -PathType Container)) {
    throw "Vault directory does not exist: $resolvedVault"
}

$userProfile = [Environment]::GetFolderPath('UserProfile')
if ([string]::IsNullOrWhiteSpace($CodexConfigPath)) {
    $codexRoot = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $userProfile '.codex' } else { [System.IO.Path]::GetFullPath($env:CODEX_HOME) }
    $CodexConfigPath = Join-Path $codexRoot 'config.toml'
}
$resolvedConfig = [System.IO.Path]::GetFullPath($CodexConfigPath)
$obsidianDir = Join-Path $resolvedVault '.obsidian'
$pluginDir = Join-Path $obsidianDir "plugins\$pluginId"
$dataPath = Join-Path $pluginDir 'data.json'
$communityPath = Join-Path $obsidianDir 'community-plugins.json'
$settingsPath = Join-Path $resolvedVault '.codex-obsidian-knowledge.json'

function Write-Utf8Text([string]$Path, [string]$Value) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Value, [System.Text.UTF8Encoding]::new($false))
}

function Write-Utf8Json([string]$Path, [object]$Value) {
    Write-Utf8Text $Path ((ConvertTo-Json -InputObject $Value -Depth 20) + [Environment]::NewLine)
}

function Read-JsonObject([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required JSON file is missing: $Path" }
    try { $value = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Could not parse JSON file: $Path" }
    if ($null -eq $value -or $value -is [System.Array] -or $value -is [string] -or $value -is [System.ValueType]) {
        throw "JSON file must contain an object: $Path"
    }
    return $value
}

function Remove-McpSection([string]$Text) {
    $lines = @($Text -split "`r?`n")
    $output = New-Object System.Collections.Generic.List[string]
    $insideTarget = $false
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[(?<section>[^\]]+)\]\s*(?:#.*)?$') {
            $insideTarget = $Matches.section -eq 'mcp_servers.obsidian'
            if ($insideTarget) { continue }
        }
        if (-not $insideTarget) { $output.Add($line) }
    }
    $result = ($output -join [Environment]::NewLine).TrimEnd()
    if ($result.Length -eq 0) { return '' }
    return $result + [Environment]::NewLine
}

function New-ApiKey {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) }
    finally { $rng.Dispose() }
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Commit-Plan([object[]]$Items) {
    $transactionRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-obsidian-maintenance-$([guid]::NewGuid().ToString('N'))")
    $backupRoot = Join-Path $transactionRoot 'backup'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $backups = @()
    $committed = @()
    try {
        $index = 0
        foreach ($item in $Items) {
            if (Test-Path -LiteralPath $item.Target) {
                $backupPath = Join-Path $backupRoot ("item-$index")
                Move-Item -LiteralPath $item.Target -Destination $backupPath -Force | Out-Null
                $backups += [PSCustomObject]@{ Target = $item.Target; Backup = $backupPath }
            }
            if ($null -ne $item.Source) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $item.Target) -Force | Out-Null
                Move-Item -LiteralPath $item.Source -Destination $item.Target -Force | Out-Null
                $committed += $item.Target
            }
            $index++
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
    finally {
        if (Test-Path -LiteralPath $transactionRoot) { Remove-Item -LiteralPath $transactionRoot -Recurse -Force }
    }
}

function Assert-SecretOwned([string]$CurrentValue, [string]$ExpectedValue, [string]$Scope) {
    if (-not [string]::IsNullOrWhiteSpace($CurrentValue) -and $CurrentValue -cne $ExpectedValue) {
        throw "$secretEnvName in $Scope does not match this Vault. Refusing to replace it."
    }
}

$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-obsidian-maintenance-stage-$([guid]::NewGuid().ToString('N'))")
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
try {
    $pluginData = if (Test-Path -LiteralPath $dataPath -PathType Leaf) { Read-JsonObject $dataPath } else { $null }
    $oldKey = if ($null -ne $pluginData) { [string]$pluginData.apiKey } else { '' }

    if ($Action -eq 'RotateKey') {
        if ([string]::IsNullOrWhiteSpace($oldKey)) { throw 'The selected Vault has no Local REST API key to rotate.' }
        Assert-SecretOwned ([Environment]::GetEnvironmentVariable($secretEnvName, $SecretScope)) $oldKey "the $SecretScope environment"
        $newKey = New-ApiKey
        $pluginData.apiKey = $newKey
        $stagedData = Join-Path $stageRoot 'data.json'
        Write-Utf8Json $stagedData $pluginData
        Commit-Plan @([PSCustomObject]@{ Source = $stagedData; Target = $dataPath })
        try {
            [Environment]::SetEnvironmentVariable($secretEnvName, $newKey, $SecretScope)
            if ($SecretScope -eq 'User') { Set-Item -Path "Env:$secretEnvName" -Value $newKey }
        }
        catch {
            $pluginData.apiKey = $oldKey
            $restoreData = Join-Path $stageRoot 'restore-data.json'
            Write-Utf8Json $restoreData $pluginData
            Commit-Plan @([PSCustomObject]@{ Source = $restoreData; Target = $dataPath })
            throw 'API key rotation failed while updating the environment; plugin settings were restored.'
        }
        Write-Output "Rotated the Local REST API key and updated the $SecretScope Codex credential (value hidden)."
        Write-Output 'Restart Obsidian and Codex, then run doctor.'
        return
    }

    $plan = @()
    if ($null -ne $pluginData) {
        if ($pluginData.psobject.Properties.Name -contains 'enableInsecureServer') { $pluginData.enableInsecureServer = $false }
        else { $pluginData | Add-Member -MemberType NoteProperty -Name enableInsecureServer -Value $false }
        $stagedData = Join-Path $stageRoot 'data.json'
        Write-Utf8Json $stagedData $pluginData
        $plan += [PSCustomObject]@{ Source = $stagedData; Target = $dataPath }
    }
    if (Test-Path -LiteralPath $resolvedConfig -PathType Leaf) {
        $stagedConfig = Join-Path $stageRoot 'config.toml'
        Write-Utf8Text $stagedConfig (Remove-McpSection (Get-Content -LiteralPath $resolvedConfig -Raw -Encoding UTF8))
        $plan += [PSCustomObject]@{ Source = $stagedConfig; Target = $resolvedConfig }
    }

    if ($Action -eq 'Uninstall') {
        if (Test-Path -LiteralPath $communityPath -PathType Leaf) {
            try { $plugins = @((Get-Content -LiteralPath $communityPath -Raw -Encoding UTF8 | ConvertFrom-Json)) }
            catch { throw "Could not parse community-plugins.json: $communityPath" }
            $remaining = @($plugins | Where-Object { [string]$_ -ne $pluginId })
            $stagedCommunity = Join-Path $stageRoot 'community-plugins.json'
            Write-Utf8Json $stagedCommunity $remaining
            $plan += [PSCustomObject]@{ Source = $stagedCommunity; Target = $communityPath }
        }
        if (Test-Path -LiteralPath $pluginDir) { $plan += [PSCustomObject]@{ Source = $null; Target = $pluginDir } }
        if (Test-Path -LiteralPath $settingsPath) { $plan += [PSCustomObject]@{ Source = $null; Target = $settingsPath } }
    }

    if ($plan.Count -gt 0) { Commit-Plan $plan }
    $userValue = [Environment]::GetEnvironmentVariable($secretEnvName, 'User')
    if (-not [string]::IsNullOrWhiteSpace($oldKey) -and $userValue -ceq $oldKey) { [Environment]::SetEnvironmentVariable($secretEnvName, $null, 'User') }
    $processValue = [Environment]::GetEnvironmentVariable($secretEnvName, 'Process')
    if (-not [string]::IsNullOrWhiteSpace($oldKey) -and $processValue -ceq $oldKey) { Remove-Item "Env:$secretEnvName" -ErrorAction SilentlyContinue }

    if ($Action -eq 'Disconnect') {
        Write-Output 'Disconnected Codex from the selected Vault and disabled the HTTP fallback. Obsidian plugin files and knowledge notes were preserved.'
    }
    else {
        Write-Output 'Removed the Local REST API plugin files and Codex integration settings for the selected Vault. Knowledge notes were preserved.'
    }
}
finally {
    if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
}
