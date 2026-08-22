[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VaultPath,

    [string]$CodexConfigPath = (Join-Path $env:USERPROFILE '.codex\config.toml')
)

$ErrorActionPreference = 'Stop'
$failures = @()

function Report-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    if ($Passed) {
        Write-Output ("[OK]   {0}: {1}" -f $Name, $Detail)
    }
    else {
        Write-Output ("[FAIL] {0}: {1}" -f $Name, $Detail)
        $script:failures += $Name
    }
}

function Test-TcpPort([string]$HostName, [int]$PortNumber) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $asyncResult = $client.BeginConnect($HostName, $PortNumber, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne(2000, $false)) {
            return $false
        }
        $client.EndConnect($asyncResult)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

$resolvedVault = [System.IO.Path]::GetFullPath($VaultPath)
$resolvedConfig = [System.IO.Path]::GetFullPath($CodexConfigPath)
$pluginDir = Join-Path $resolvedVault '.obsidian\plugins\obsidian-local-rest-api'
$manifestPath = Join-Path $pluginDir 'manifest.json'
$dataPath = Join-Path $pluginDir 'data.json'
$settingsPath = Join-Path $resolvedVault '.codex-obsidian-knowledge.json'
$envName = 'OBSIDIAN_LOCAL_REST_API_KEY'

$vaultExists = Test-Path -LiteralPath $resolvedVault -PathType Container
Report-Check 'Vault' $vaultExists $resolvedVault

$manifestExists = Test-Path -LiteralPath $manifestPath -PathType Leaf
Report-Check 'Local REST API plugin' $manifestExists $manifestPath

$dataExists = Test-Path -LiteralPath $dataPath -PathType Leaf
Report-Check 'Plugin settings' $dataExists $dataPath

$pluginData = $null
if ($dataExists) {
    try {
        $pluginData = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $hasApiKey = -not [string]::IsNullOrWhiteSpace([string]$pluginData.apiKey)
        Report-Check 'Plugin API key' $hasApiKey 'Configured (value hidden)'
    }
    catch {
        Report-Check 'Plugin settings JSON' $false 'Could not parse data.json'
    }
}
else {
    Report-Check 'Plugin API key' $false 'Skipped because data.json is missing'
}

$settingsExists = Test-Path -LiteralPath $settingsPath -PathType Leaf
if ($settingsExists) {
    try {
        $knowledgeSettings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $noteRoot = [string]$knowledgeSettings.noteRoot
        $validNoteRoot = -not ([System.IO.Path]::IsPathRooted($noteRoot) -or $noteRoot.StartsWith('/') -or $noteRoot -match '(^|/)\.\.(/|$)')
        $displayRoot = if ([string]::IsNullOrWhiteSpace($noteRoot)) { 'Vault root' } else { $noteRoot }
        Report-Check 'Knowledge note root' $validNoteRoot $displayRoot
    }
    catch {
        Report-Check 'Knowledge note root' $false 'Could not parse .codex-obsidian-knowledge.json'
    }
}
else {
    Report-Check 'Knowledge note root' $true 'Not configured; Vault root is used'
}

$configExists = Test-Path -LiteralPath $resolvedConfig -PathType Leaf
Report-Check 'Codex config' $configExists $resolvedConfig

$config = ''
$endpoint = $null
$configEnvName = $null
$configuredToken = $null
if ($configExists) {
    $config = Get-Content -LiteralPath $resolvedConfig -Raw -Encoding UTF8
    $sectionMatch = [regex]::Match($config, '(?ms)^\[mcp_servers\.obsidian\]\s*$.*?(?=^\[|\z)')
    $sectionExists = $sectionMatch.Success
    Report-Check 'MCP section' $sectionExists '[mcp_servers.obsidian]'
    if ($sectionExists) {
        $urlMatch = [regex]::Match($sectionMatch.Value, '(?m)^\s*url\s*=\s*"(?<url>[^"]+)"')
        if ($urlMatch.Success) {
            $endpoint = $urlMatch.Groups['url'].Value
            Report-Check 'MCP endpoint' $true $endpoint
        }
        else {
            Report-Check 'MCP endpoint' $false 'The section has no url entry'
        }
        $tokenMatch = [regex]::Match($sectionMatch.Value, '(?m)^\s*bearer_token_env_var\s*=\s*"(?<name>[^"]+)"')
        if ($tokenMatch.Success) {
            $configEnvName = $tokenMatch.Groups['name'].Value
            $userToken = [Environment]::GetEnvironmentVariable($configEnvName, 'User')
            $processToken = [Environment]::GetEnvironmentVariable($configEnvName, 'Process')
            $configuredToken = if (-not [string]::IsNullOrWhiteSpace($userToken)) { $userToken } else { $processToken }
            Report-Check 'Codex API key variable' (-not [string]::IsNullOrWhiteSpace($configuredToken)) "$configEnvName is available (value hidden)"
            if ($null -ne $pluginData -and -not [string]::IsNullOrWhiteSpace([string]$pluginData.apiKey) -and -not [string]::IsNullOrWhiteSpace($configuredToken)) {
                Report-Check 'API key match' ([string]$pluginData.apiKey -ceq $configuredToken) 'Plugin and Codex credential sources agree (values hidden)'
            }
        }
        else {
            Report-Check 'Codex API key variable' $false 'The MCP section has no bearer_token_env_var entry'
        }
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
        Report-Check 'Endpoint scheme' $validScheme $endpointUri.Scheme
        $loopbackOnly = $endpointUri.Host -eq '127.0.0.1'
        Report-Check 'Endpoint boundary' $loopbackOnly $endpointUri.Host
        if (-not $validScheme -or -not $loopbackOnly) { throw 'Unsupported endpoint URL.' }
        $tcpReachable = Test-TcpPort $endpointUri.Host $endpointUri.Port
        Report-Check 'Endpoint TCP' $tcpReachable ("{0}:{1}" -f $endpointUri.Host, $endpointUri.Port)

        if ($tcpReachable) {
            $headers = @{
                Authorization = 'Bearer ' + $configuredToken
                Accept = 'application/json, text/event-stream'
            }
            $body = @{
                jsonrpc = '2.0'
                id = 1
                method = 'initialize'
                params = @{
                    protocolVersion = '2024-11-05'
                    capabilities = @{}
                    clientInfo = @{ name = 'codex-obsidian-knowledge-doctor'; version = '0.1.0' }
                }
            } | ConvertTo-Json -Depth 8
            try {
                $response = Invoke-WebRequest -Uri $endpoint -Method Post -Headers $headers -ContentType 'application/json' -Body $body -UseBasicParsing
                $handshakeOk = ($response.StatusCode -eq 200)
                if ($handshakeOk) {
                    try {
                        $jsonContent = $response.Content
                        $dataMatch = [regex]::Match($jsonContent, '(?ms)^data:\s*(\{.*\})\s*$')
                        if ($dataMatch.Success) {
                            $jsonContent = $dataMatch.Groups[1].Value
                        }
                        $responseJson = $jsonContent | ConvertFrom-Json
                        if ($null -ne $responseJson.error -or $null -eq $responseJson.result) {
                            throw 'The server returned a JSON-RPC error or omitted result.'
                        }
                        $serverName = [string]$responseJson.result.serverInfo.name
                        if ([string]::IsNullOrWhiteSpace($serverName)) { $serverName = 'MCP server responded' }
                        Report-Check 'MCP initialize' $true $serverName
                    }
                    catch {
                        Report-Check 'MCP initialize' $false 'HTTP 200 but response was not valid JSON-RPC'
                    }
                }
                else {
                    Report-Check 'MCP initialize' $false ("HTTP status {0}" -f $response.StatusCode)
                }
            }
            catch {
                $detail = if ($endpointUri.Scheme -eq 'https') {
                    'Request failed; check the plugin, API key, and trust for the Local REST API certificate'
                }
                else {
                    'Request failed; check the plugin, port, API key, and insecure-server setting'
                }
                Report-Check 'MCP initialize' $false $detail
            }
        }
    }
    catch {
        Report-Check 'Endpoint URL' $false 'The configured url is not a valid URI'
    }
}

if ($failures.Count -gt 0) {
    Write-Output ''
    Write-Output ("Doctor found {0} issue(s): {1}" -f $failures.Count, ($failures -join ', '))
    exit 1
}

Write-Output ''
Write-Output 'Doctor checks passed.'
