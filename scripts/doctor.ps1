[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VaultPath,

    [string]$CodexConfigPath,

    [switch]$AllowInsecureHttp,

    [switch]$Repair,

    [switch]$Approve
)

$ErrorActionPreference = 'Stop'
$failures = @()
$scriptRoot = Split-Path -Parent $PSScriptRoot
$assetMetadataPath = Join-Path $PSScriptRoot 'upstream-assets.json'
$assetMetadata = $null
if (Test-Path -LiteralPath $assetMetadataPath -PathType Leaf) {
    try { $assetMetadata = Get-Content -LiteralPath $assetMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
}
$pluginId = if ($null -ne $assetMetadata) { [string]$assetMetadata.pluginId } else { 'obsidian-local-rest-api' }
$pluginVersion = if ($null -ne $assetMetadata) { [string]$assetMetadata.version } else { '5.1.0' }
$userProfile = [Environment]::GetFolderPath('UserProfile')
if ([string]::IsNullOrWhiteSpace($CodexConfigPath)) {
    $codexRoot = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $userProfile '.codex' } else { [System.IO.Path]::GetFullPath($env:CODEX_HOME) }
    $CodexConfigPath = Join-Path $codexRoot 'config.toml'
}

function Report-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    if ($Passed) { Write-Output ("[OK]   {0}: {1}" -f $Name, $Detail) }
    else { Write-Output ("[FAIL] {0}: {1}" -f $Name, $Detail); $script:failures += $Name }
}

function Test-TcpPort([string]$HostName, [int]$PortNumber) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $asyncResult = $client.BeginConnect($HostName, $PortNumber, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne(2000, $false)) { return $false }
        $client.EndConnect($asyncResult)
        return $true
    }
    catch { return $false }
    finally { $client.Close() }
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
        if ($withoutComment -match '^(?<key>url|bearer_token_env_var)\s*=\s*"(?<value>[^"]*)"\s*$') { $values[$Matches.key] = $Matches.value; continue }
        if ($withoutComment -match '^(?<key>startup_timeout_sec|tool_timeout_sec)\s*=\s*(?<value>[0-9]+)\s*$') { $values[$Matches.key] = $Matches.value }
    }
    return [PSCustomObject]@{ Exists = $sectionExists; Values = $values }
}

function Test-RelativeNoteRoot([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -eq '.') { return $true }
    $normalized = $Path.Replace('\', '/')
    if ([System.IO.Path]::IsPathRooted($normalized) -or $normalized.StartsWith('/') -or $normalized -match '(^|/)\.\.(/|$)') { return $false }
    foreach ($segment in $normalized.Trim('/').Split('/')) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -in @('.', '..')) { return $false }
        if ($segment -match '[\x00-\x1F]' -or $segment -match '[<>:"|?*]' -or $segment -match '[. ]$' -or $segment -match '^\s') { return $false }
        if ($segment -match '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$') { return $false }
        if ($segment.Length -gt 120) { return $false }
    }
    return $normalized.Trim('/').Length -le 240
}

function Get-JsonResponse([string]$Content) {
    $candidate = $Content
    $dataLine = ($Content -split "`r?`n" | Where-Object { $_ -match '^data:\s*' } | Select-Object -First 1)
    if ($null -ne $dataLine) { $candidate = $dataLine -replace '^data:\s*', '' }
    return $candidate | ConvertFrom-Json
}

$resolvedVault = [System.IO.Path]::GetFullPath($VaultPath)
$resolvedConfig = [System.IO.Path]::GetFullPath($CodexConfigPath)
$pluginDir = Join-Path $resolvedVault ".obsidian\plugins\$pluginId"
$manifestPath = Join-Path $pluginDir 'manifest.json'
$dataPath = Join-Path $pluginDir 'data.json'
$settingsPath = Join-Path $resolvedVault '.codex-obsidian-knowledge.json'
$communityPluginsPath = Join-Path $resolvedVault '.obsidian\community-plugins.json'

$vaultExists = Test-Path -LiteralPath $resolvedVault -PathType Container
Report-Check 'Vault' $vaultExists $resolvedVault
if (-not $vaultExists) { Write-Output ''; Write-Output 'Doctor cannot continue without a Vault.'; exit 1 }

if ($Repair) {
    if (-not $Approve) { throw 'Doctor repair changes plugin settings and the current-user credential. Re-run with -Repair -Approve after confirmation.' }
    if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) { throw 'Use doctor.sh --repair --approve on macOS.' }
    if (-not (Test-Path -LiteralPath $dataPath -PathType Leaf)) { throw "Cannot repair because plugin settings are missing: $dataPath" }
    if (-not (Test-Path -LiteralPath $resolvedConfig -PathType Leaf)) { throw "Cannot repair because Codex config is missing: $resolvedConfig" }
    $repairData = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $repairConfig = Get-Content -LiteralPath $resolvedConfig -Raw -Encoding UTF8
    $repairParsed = Get-McpConfigValues $repairConfig
    $repairEndpoint = if ($repairParsed.Exists) { [string]$repairParsed.Values.url } else { '' }
    $repairEnvName = if ($repairParsed.Exists) { [string]$repairParsed.Values.bearer_token_env_var } else { '' }
    if ($repairEnvName -ne 'OBSIDIAN_LOCAL_REST_API_KEY') {
        throw 'Cannot repair a Codex config that uses a different bearer_token_env_var.'
    }
    $repairUri = [System.Uri]$repairEndpoint
    if ($repairUri.Scheme -notin @('http', 'https') -or $repairUri.Host -ne '127.0.0.1' -or $repairUri.AbsolutePath -ne '/mcp/') {
        throw 'Cannot repair an unsupported or non-loopback endpoint.'
    }
    $repairKey = [string]$repairData.apiKey
    if ([string]::IsNullOrWhiteSpace($repairKey)) { throw 'Cannot repair because the plugin API key is missing.' }
    $userKey = [Environment]::GetEnvironmentVariable('OBSIDIAN_LOCAL_REST_API_KEY', 'User')
    $processKey = [Environment]::GetEnvironmentVariable('OBSIDIAN_LOCAL_REST_API_KEY', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($userKey) -and $userKey -cne $repairKey) {
        throw 'The current-user OBSIDIAN_LOCAL_REST_API_KEY belongs to a different Vault. Refusing to replace it.'
    }
    if (-not [string]::IsNullOrWhiteSpace($processKey) -and $processKey -cne $repairKey) {
        throw 'The process OBSIDIAN_LOCAL_REST_API_KEY belongs to a different Vault. Refusing to replace it.'
    }
    $expectedInsecure = $repairUri.Scheme -eq 'http'
    if ($repairData.psobject.Properties.Name -contains 'enableInsecureServer') { $repairData.enableInsecureServer = $expectedInsecure }
    else { $repairData | Add-Member -MemberType NoteProperty -Name enableInsecureServer -Value $expectedInsecure }
    $repairTemporary = Join-Path $pluginDir ('.data.json.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText($repairTemporary, (ConvertTo-Json -InputObject $repairData -Depth 20) + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $repairTemporary -Destination $dataPath -Force | Out-Null
        [Environment]::SetEnvironmentVariable('OBSIDIAN_LOCAL_REST_API_KEY', $repairKey, 'User')
        Set-Item -Path 'Env:OBSIDIAN_LOCAL_REST_API_KEY' -Value $repairKey
    }
    finally {
        if (Test-Path -LiteralPath $repairTemporary) { Remove-Item -LiteralPath $repairTemporary -Force }
    }
    Write-Output '[REPAIR] Reconciled the plugin protocol mode and current-user credential with Codex config (key hidden).'
}

$mainExists = Test-Path -LiteralPath (Join-Path $pluginDir 'main.js') -PathType Leaf
$manifestExists = Test-Path -LiteralPath $manifestPath -PathType Leaf
Report-Check 'Local REST API plugin files' ($mainExists -and $manifestExists) $pluginDir
$pluginData = $null
if ($manifestExists) {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $manifestOk = [string]$manifest.id -eq $pluginId -and [string]$manifest.version -eq $pluginVersion
        Report-Check 'Plugin identity/version' $manifestOk "$pluginId $pluginVersion"
    }
    catch { Report-Check 'Plugin manifest JSON' $false 'Could not parse manifest.json' }
}
$dataExists = Test-Path -LiteralPath $dataPath -PathType Leaf
Report-Check 'Plugin settings' $dataExists $dataPath
if ($dataExists) {
    try {
        $pluginData = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $hasApiKey = $pluginData -isnot [System.Array] -and -not [string]::IsNullOrWhiteSpace([string]$pluginData.apiKey)
        Report-Check 'Plugin API key' $hasApiKey 'Configured (value hidden)'
    }
    catch { Report-Check 'Plugin settings JSON' $false 'Could not parse data.json' }
}
else { Report-Check 'Plugin API key' $false 'Skipped because data.json is missing' }

$enabled = $false
if (Test-Path -LiteralPath $communityPluginsPath -PathType Leaf) {
    try {
        $enabledText = Get-Content -LiteralPath $communityPluginsPath -Raw -Encoding UTF8
        $enabledJson = $enabledText.TrimStart([char]0xFEFF).TrimStart()
        if (-not $enabledJson.StartsWith('[')) { throw 'community-plugins.json must contain an array.' }
        $enabledList = @($enabledText | ConvertFrom-Json)
        $enabled = $enabledList -contains $pluginId
    }
    catch { }
}
Report-Check 'Plugin enabled' $enabled $communityPluginsPath

if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
    try {
        $knowledgeSettings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $noteRoot = [string]$knowledgeSettings.noteRoot
        $noteRootDisplay = if ([string]::IsNullOrWhiteSpace($noteRoot)) { 'Vault root' } else { $noteRoot }
        Report-Check 'Knowledge note root' (Test-RelativeNoteRoot $noteRoot) $noteRootDisplay
    }
    catch { Report-Check 'Knowledge note root' $false 'Could not parse .codex-obsidian-knowledge.json' }
}
else { Report-Check 'Knowledge note root' $true 'Not configured; Vault root is used' }

$configExists = Test-Path -LiteralPath $resolvedConfig -PathType Leaf
Report-Check 'Codex config' $configExists $resolvedConfig
$endpoint = $null
$configuredToken = $null
if ($configExists) {
    $config = Get-Content -LiteralPath $resolvedConfig -Raw -Encoding UTF8
    $parsed = Get-McpConfigValues $config
    Report-Check 'MCP section' $parsed.Exists '[mcp_servers.obsidian]'
    if ($parsed.Exists) {
        $endpoint = [string]$parsed.Values.url
        $configuredEnvName = [string]$parsed.Values.bearer_token_env_var
        $hasEndpoint = -not [string]::IsNullOrWhiteSpace($endpoint)
        $endpointDisplay = if ([string]::IsNullOrWhiteSpace($endpoint)) { 'missing url entry' } else { $endpoint }
        Report-Check 'MCP endpoint' $hasEndpoint $endpointDisplay
        $envNameOk = $configuredEnvName -eq 'OBSIDIAN_LOCAL_REST_API_KEY'
        $configuredEnvDisplay = if ([string]::IsNullOrWhiteSpace($configuredEnvName)) { 'missing bearer_token_env_var entry' } else { $configuredEnvName }
        Report-Check 'Codex API key variable name' $envNameOk $configuredEnvDisplay
        if ($envNameOk) {
            $userToken = [Environment]::GetEnvironmentVariable($configuredEnvName, 'User')
            $processToken = [Environment]::GetEnvironmentVariable($configuredEnvName, 'Process')
            $configuredToken = if (-not [string]::IsNullOrWhiteSpace($processToken)) { $processToken } else { $userToken }
            Report-Check 'Codex API key variable' (-not [string]::IsNullOrWhiteSpace($configuredToken)) 'Value hidden'
            if ($null -ne $pluginData -and -not [string]::IsNullOrWhiteSpace([string]$pluginData.apiKey) -and -not [string]::IsNullOrWhiteSpace($configuredToken)) {
                Report-Check 'API key match' ([string]$pluginData.apiKey -ceq $configuredToken) 'Plugin and Codex credential sources agree (values hidden)'
            }
        }
        $startupTimeoutOk = [string]$parsed.Values.startup_timeout_sec -eq '20'
        $toolTimeoutOk = [string]$parsed.Values.tool_timeout_sec -eq '60'
        Report-Check 'MCP startup timeout' $startupTimeoutOk '20 seconds'
        Report-Check 'MCP tool timeout' $toolTimeoutOk '60 seconds'
    }
}
else {
    Report-Check 'MCP section' $false 'Skipped because config.toml is missing'
    Report-Check 'MCP endpoint' $false 'Skipped because config.toml is missing'
    Report-Check 'Codex API key variable' $false 'Skipped because config.toml is missing'
}

if ($null -ne $endpoint -and -not [string]::IsNullOrWhiteSpace($configuredToken)) {
    try {
        $endpointUri = [System.Uri]$endpoint
        $validScheme = $endpointUri.Scheme -in @('http', 'https')
        $loopbackOnly = $endpointUri.Host -eq '127.0.0.1'
        $validPath = $endpointUri.AbsolutePath -eq '/mcp/'
        $httpIntentOk = $endpointUri.Scheme -ne 'http' -or $AllowInsecureHttp
        Report-Check 'Endpoint scheme/path' ($validScheme -and $validPath) ("{0}{1}" -f $endpointUri.Scheme, $endpointUri.AbsolutePath)
        Report-Check 'Endpoint boundary' $loopbackOnly $endpointUri.Host
        $httpIntentDisplay = if ($endpointUri.Scheme -eq 'http') { 'Pass -AllowInsecureHttp explicitly when using HTTP' } else { 'HTTPS' }
        Report-Check 'HTTP fallback selection' $httpIntentOk $httpIntentDisplay
        if ($pluginData -ne $null) {
            $expectedInsecureServer = $endpointUri.Scheme -eq 'http'
            $actualInsecureServer = [bool]$pluginData.enableInsecureServer
            $protocolModeDetail = if ($expectedInsecureServer) { 'HTTP endpoint requires enableInsecureServer=true' } else { 'HTTPS endpoint requires enableInsecureServer=false' }
            Report-Check 'Plugin protocol mode' ($actualInsecureServer -eq $expectedInsecureServer) $protocolModeDetail
        }
        if (-not $validScheme -or -not $validPath -or -not $loopbackOnly -or -not $httpIntentOk) { throw 'Unsupported endpoint URL.' }
        $tcpReachable = Test-TcpPort $endpointUri.Host $endpointUri.Port
        Report-Check 'Endpoint TCP' $tcpReachable ("{0}:{1}" -f $endpointUri.Host, $endpointUri.Port)
        if ($tcpReachable) {
            $headers = @{ Authorization = 'Bearer ' + $configuredToken; Accept = 'application/json, text/event-stream' }
            $body = @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ protocolVersion = '2024-11-05'; capabilities = @{}; clientInfo = @{ name = 'codex-obsidian-knowledge-doctor'; version = '0.3.0' } } } | ConvertTo-Json -Depth 8
            try {
                $response = Invoke-WebRequest -Uri $endpoint -Method Post -Headers $headers -ContentType 'application/json' -Body $body -UseBasicParsing -TimeoutSec 5
                $responseJson = Get-JsonResponse $response.Content
                $handshakeOk = $response.StatusCode -eq 200 -and $null -eq $responseJson.error -and $null -ne $responseJson.result -and -not [string]::IsNullOrWhiteSpace([string]$responseJson.result.serverInfo.name)
                if ($handshakeOk) { Report-Check 'MCP initialize' $true ([string]$responseJson.result.serverInfo.name) }
                else { Report-Check 'MCP initialize' $false 'Response was not a valid authenticated JSON-RPC initialize result' }
            }
            catch {
                $detail = if ($endpointUri.Scheme -eq 'https') { 'Request failed; check Obsidian, API key, and trust for the Local REST API certificate' } else { 'Request failed; check Obsidian, port, API key, and insecure-server setting' }
                Report-Check 'MCP initialize' $false $detail
            }
        }
    }
    catch { Report-Check 'Endpoint URL' $false 'The configured url is not a supported loopback MCP URI' }
}

if ($failures.Count -gt 0) {
    Write-Output ''
    Write-Output ("Doctor found {0} issue(s): {1}" -f $failures.Count, ($failures -join ', '))
    exit 1
}
Write-Output ''
Write-Output 'Doctor checks passed.'
