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
    'scripts\install-plugin.ps1',
    'scripts\scan-sensitive-content.ps1',
    'scripts\validate-note-path.ps1'
)) {
    $path = Join-Path $repoRoot $relativePath
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-True ($errors.Count -eq 0) "$relativePath has PowerShell parse errors."
}

foreach ($relativePath in @(
    '.codex-plugin\plugin.json',
    '.agents\plugins\marketplace.json',
    'scripts\upstream-assets.json'
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
    Assert-True ($content -match 'audience:\s*beginner-programmer') "$templateName is missing the beginner audience."
    Assert-True ($content -match 'detail_level:\s*expanded') "$templateName is missing the expanded detail level."
}
$projectOverview = Get-Content -LiteralPath (Join-Path $repoRoot 'templates\project-overview.md') -Raw -Encoding UTF8
Assert-True ($projectOverview -match 'type:\s*code-project-overview' -and $projectOverview -match 'review:\s*pending') 'project-overview.md is missing project frontmatter.'
Assert-True ($projectOverview -match 'audience:\s*beginner-programmer' -and $projectOverview -match '如何运行、观察和调试' -and $projectOverview -match '功能学习路线') 'project-overview.md is missing beginner onboarding sections.'
$architectureTemplate = Get-Content -LiteralPath (Join-Path $repoRoot 'templates\architecture-and-terms.md') -Raw -Encoding UTF8
Assert-True ($architectureTemplate -match 'type:\s*code-project-architecture') 'architecture-and-terms.md is missing project architecture frontmatter.'
Assert-True ($architectureTemplate -match 'audience:\s*beginner-programmer' -and $architectureTemplate -match '第一层：系统边界' -and $architectureTemplate -match '第二层：组件地图' -and $architectureTemplate -match '第三层：主流程' -and $architectureTemplate -match '关键术语表') 'architecture-and-terms.md is missing the beginner architecture layers or glossary.'
$featureOverview = Get-Content -LiteralPath (Join-Path $repoRoot 'templates\feature-overview.md') -Raw -Encoding UTF8
$implementationDetails = Get-Content -LiteralPath (Join-Path $repoRoot 'templates\implementation-details.md') -Raw -Encoding UTF8
$implementationEffect = Get-Content -LiteralPath (Join-Path $repoRoot 'templates\implementation-effect.md') -Raw -Encoding UTF8
$knowledgeApplication = Get-Content -LiteralPath (Join-Path $repoRoot 'templates\knowledge-application.md') -Raw -Encoding UTF8
$iterationRoadmap = Get-Content -LiteralPath (Join-Path $repoRoot 'templates\iteration-roadmap.md') -Raw -Encoding UTF8
$sourceIndex = Get-Content -LiteralPath (Join-Path $repoRoot 'templates\source-index.md') -Raw -Encoding UTF8
Assert-True ($featureOverview -match '学习目标与前置知识' -and $featureOverview -match '功能心智模型' -and $featureOverview -match '主要决策与权衡') 'feature-overview.md is missing learning goals, a mental model, or decision evidence.'
Assert-True ($implementationDetails -match '端到端代码导读' -and $implementationDetails -match '输入从哪里来' -and $implementationDetails -match '关键语法/API' -and $implementationDetails -match '失败信号') 'implementation-details.md is missing the guided code-reading contract.'
Assert-True ($implementationEffect -match '不同证据能证明什么' -and $implementationEffect -match '已知验证边界' -and $implementationEffect -match '回归、性能与运行影响') 'implementation-effect.md is missing evidence teaching or verification boundaries.'
Assert-True ($knowledgeApplication -match '本功能关键术语' -and $knowledgeApplication -match '用自己的话检验理解' -and $knowledgeApplication -match '动手练习' -and $knowledgeApplication -match '预期观察/答案') 'knowledge-application.md is missing vocabulary, self-checks, or exercises.'
Assert-True ($iterationRoadmap -match '为什么现在做' -and $iterationRoadmap -match '验收标准') 'iteration-roadmap.md is missing prioritization fields.'
Assert-True ($sourceIndex -match '证据台账' -and $sourceIndex -match '它不能证明什么') 'source-index.md is missing evidence boundaries.'

$learningGuidePath = Join-Path $repoRoot 'skills\code-knowledge-capture\references\beginner-learning-guide.md'
Assert-True (Test-Path -LiteralPath $learningGuidePath -PathType Leaf) 'The beginner learning guide is missing.'
$skillContent = Get-Content -LiteralPath (Join-Path $repoRoot 'skills\code-knowledge-capture\SKILL.md') -Raw -Encoding UTF8
$learningGuide = Get-Content -LiteralPath $learningGuidePath -Raw -Encoding UTF8
$skillUiMetadata = Get-Content -LiteralPath (Join-Path $repoRoot 'skills\code-knowledge-capture\agents\openai.yaml') -Raw -Encoding UTF8
Assert-True ($skillContent -match 'beginner-learning-guide\.md' -and $skillContent -match 'audience:\s*beginner-programmer') 'SKILL.md does not route to the beginner learning guide or set the default audience.'
Assert-True ($learningGuide -match 'Two-layer explanations' -and $learningGuide -match 'Architecture for beginners' -and $learningGuide -match 'Self-checks and exercises') 'The beginner learning guide is missing a required teaching layer.'
Assert-True ($skillUiMetadata -match 'short_description:\s*"[^"]*beginner-friendly[^"]*"') 'agents/openai.yaml does not describe the beginner-friendly learning workflow.'
Assert-True ($skillUiMetadata -match 'default_prompt:\s*"Use \$code-knowledge-capture\b') 'agents/openai.yaml default_prompt must explicitly invoke $code-knowledge-capture.'
$shortDescriptionMatch = [regex]::Match($skillUiMetadata, '(?m)^\s*short_description:\s*"([^"]+)"\s*$')
Assert-True ($shortDescriptionMatch.Success -and $shortDescriptionMatch.Groups[1].Value.Length -ge 25 -and $shortDescriptionMatch.Groups[1].Value.Length -le 64) 'agents/openai.yaml short_description must contain 25-64 characters.'
$assetMetadata = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\upstream-assets.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($assetMetadata.pluginId -eq 'obsidian-local-rest-api' -and $assetMetadata.version -eq '5.1.0') 'upstream asset metadata has the wrong pinned plugin identity.'
foreach ($assetName in @('main.js', 'manifest.json', 'styles.css')) {
    $assetHash = [string]$assetMetadata.assets.$assetName
    Assert-True ($assetHash -match '^[0-9a-f]{64}$') "upstream-assets.json has an invalid SHA-256 for $assetName."
}

$scannerScript = Join-Path $repoRoot 'scripts\scan-sensitive-content.ps1'
function Invoke-ScannerStatus([string]$CandidatePath) {
    & $script:scannerScript -Path $CandidatePath 2>&1 | Out-Null
    return $LASTEXITCODE
}

$bootstrapPowerShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\bootstrap.ps1') -Raw -Encoding UTF8
$normalizeIndex = $bootstrapPowerShell.LastIndexOf('$noteRoot = Normalize-NoteRoot $NoteRoot', [System.StringComparison]::Ordinal)
$installIndex = $bootstrapPowerShell.LastIndexOf('$apiKey = Install-LocalRestApi', [System.StringComparison]::Ordinal)
Assert-True ($normalizeIndex -ge 0 -and $installIndex -ge 0 -and $normalizeIndex -lt $installIndex) 'bootstrap.ps1 must validate NoteRoot before installing the plugin.'
Assert-True ($bootstrapPowerShell -match 'enableInsecureServer') 'bootstrap.ps1 must enable the plugin HTTP server for the explicit fallback.'
Assert-True ($bootstrapPowerShell -match 'CODEX_HOME') 'bootstrap.ps1 must respect CODEX_HOME.'
Assert-True ($bootstrapPowerShell -match 'Assert-AssetIntegrity') 'bootstrap.ps1 must verify upstream asset hashes.'
Assert-True ($bootstrapPowerShell -match 'backupRoot') 'bootstrap.ps1 must use a rollback-capable commit.'
Assert-True ($bootstrapPowerShell -match 'ConvertTo-Json -InputObject \$Value') 'bootstrap.ps1 must preserve single-element JSON arrays.'
Assert-True ($bootstrapPowerShell -match 'Write-Utf8Text \$zshEnvPath \$updated -OwnerOnly') 'bootstrap.ps1 must protect the API key stored in .zshenv.'

$bootstrapShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\bootstrap.sh') -Raw -Encoding UTF8
Assert-True ($bootstrapShell -match 'data\.enableInsecureServer = true') 'bootstrap.sh must enable the plugin HTTP server for the explicit fallback.'
Assert-True ($bootstrapShell -match '\[\[ "\$NOTE_ROOT" != /\* \]\]') 'bootstrap.sh must reject absolute NoteRoot values before trimming them.'

$installShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\install-plugin.sh') -Raw -Encoding UTF8
Assert-True ($installShell.Contains('user_codex_root="${CODEX_HOME:-$HOME/.codex}"')) 'install-plugin.sh must treat CODEX_HOME as the Codex root.'

$doctorPowerShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\doctor.ps1') -Raw -Encoding UTF8
Assert-True ($doctorPowerShell -match 'Invoke-WebRequest -Uri \$endpoint -Method Post') 'doctor.ps1 must perform an MCP initialize request.'
Assert-True (-not $doctorPowerShell.Contains('Skipped HTTP handshake')) 'doctor.ps1 must not report a skipped HTTPS handshake as successful.'
Assert-True ($doctorPowerShell -match 'CODEX_HOME') 'doctor.ps1 must respect CODEX_HOME.'
Assert-True ($doctorPowerShell -match 'IsNullOrWhiteSpace\(\$processToken\).*\$processToken.*\$userToken') 'doctor.ps1 must prefer the process credential that a launched Codex process inherits.'
Assert-True ($doctorPowerShell -match 'Invoke-WebRequest.*-TimeoutSec\s+5') 'doctor.ps1 must bound the MCP initialize request.'

$doctorShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\doctor.sh') -Raw -Encoding UTF8
Assert-True ($doctorShell -match 'bearer_token_env_var') 'doctor.sh must read the credential source from Codex config.'
Assert-True ($doctorShell -match 'method.*initialize') 'doctor.sh must perform an MCP initialize request.'
$bootstrapShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\bootstrap.sh') -Raw -Encoding UTF8
Assert-True ($bootstrapShell -match 'upstream-assets\.json' -and $bootstrapShell -match 'shasum -a 256') 'bootstrap.sh must load and verify pinned upstream asset hashes.'
Assert-True ($bootstrapShell -match 'backup_dir' -and $bootstrapShell -match 'original files were restored') 'bootstrap.sh must restore originals after a failed commit.'
$installPowerShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\install.ps1') -Raw -Encoding UTF8
Assert-True ($installPowerShell -match 'CODEX_HOME' -and $installPowerShell -match 'Commit-Files') 'install.ps1 must respect CODEX_HOME and commit changes transactionally.'
$installPluginShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\install-plugin.sh') -Raw -Encoding UTF8
Assert-True ($installPluginShell -match 'json_field' -and $installPluginShell -notmatch "plugin_name='codex-obsidian-knowledge'") 'install-plugin.sh must derive names from manifests.'

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

    $bootstrapConflictVault = Join-Path $fixtureRoot 'bootstrap-conflict-vault'
    New-Item -ItemType Directory -Path $bootstrapConflictVault | Out-Null
    $bootstrapConflictConfig = Join-Path $fixtureRoot 'bootstrap-conflict-config.toml'
    @"
[mcp_servers.obsidian]
url = "https://127.0.0.1:27124/mcp/"
bearer_token_env_var = "OTHER_TOKEN"
startup_timeout_sec = 20
tool_timeout_sec = 60
"@.Trim() | Set-Content -LiteralPath $bootstrapConflictConfig -Encoding UTF8
    $bootstrapConflictRejected = $false
    try {
        & (Join-Path $repoRoot 'scripts\bootstrap.ps1') -VaultPath $bootstrapConflictVault -CodexConfigPath $bootstrapConflictConfig -Approve | Out-Null
    }
    catch { $bootstrapConflictRejected = $true }
    Assert-True $bootstrapConflictRejected 'bootstrap.ps1 did not reject a conflicting MCP section before downloading.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $bootstrapConflictVault '.obsidian'))) 'bootstrap.ps1 mutated the Vault before rejecting a config conflict.'

    $installVault = Join-Path $fixtureRoot 'install-vault'
    $pluginDirectory = Join-Path $installVault '.obsidian\plugins\obsidian-local-rest-api'
    New-Item -ItemType Directory -Path $pluginDirectory -Force | Out-Null
    @{ id = 'obsidian-local-rest-api'; version = '5.1.0' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $pluginDirectory 'manifest.json') -Encoding UTF8
    '/* test fixture */' | Set-Content -LiteralPath (Join-Path $pluginDirectory 'main.js') -Encoding UTF8
    @{ apiKey = 'test-only-key'; enableInsecureServer = $false } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $pluginDirectory 'data.json') -Encoding UTF8
    $fixtureConfig = Join-Path $fixtureRoot 'codex\config.toml'
    & (Join-Path $repoRoot 'scripts\install.ps1') -VaultPath $installVault -CodexConfigPath $fixtureConfig -AllowInsecureHttp -NoSecretImport | Out-Null
    $fixturePluginData = Get-Content -LiteralPath (Join-Path $pluginDirectory 'data.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([bool]$fixturePluginData.enableInsecureServer) 'install.ps1 did not enable the plugin HTTP server.'
    $fixtureConfigText = Get-Content -LiteralPath $fixtureConfig -Raw -Encoding UTF8
    Assert-True ($fixtureConfigText -match 'http://127\.0\.0\.1:27123/mcp/') 'install.ps1 wrote the wrong HTTP fallback URL.'
    $fixtureConfigBytes = [System.IO.File]::ReadAllBytes($fixtureConfig)
    Assert-True (-not ($fixtureConfigBytes.Count -ge 3 -and $fixtureConfigBytes[0] -eq 239 -and $fixtureConfigBytes[1] -eq 187 -and $fixtureConfigBytes[2] -eq 191)) 'install.ps1 wrote a UTF-8 BOM into config.toml.'
    [System.IO.File]::WriteAllText($fixtureConfig, $fixtureConfigText, [System.Text.UTF8Encoding]::new($true))
    & (Join-Path $repoRoot 'scripts\install.ps1') -VaultPath $installVault -CodexConfigPath $fixtureConfig -AllowInsecureHttp -NoSecretImport | Out-Null
    $customCodexHome = Join-Path $fixtureRoot 'custom-codex-home'
    $previousCodexHome = $env:CODEX_HOME
    try {
        $env:CODEX_HOME = $customCodexHome
        & (Join-Path $repoRoot 'scripts\install.ps1') -VaultPath $installVault -AllowInsecureHttp -NoSecretImport | Out-Null
    }
    finally {
        if ($null -eq $previousCodexHome) { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue }
        else { $env:CODEX_HOME = $previousCodexHome }
    }
    Assert-True (Test-Path -LiteralPath (Join-Path $customCodexHome 'config.toml')) 'install.ps1 ignored CODEX_HOME when choosing Codex config.'

    $conflictVault = Join-Path $fixtureRoot 'conflict-vault'
    $conflictPlugin = Join-Path $conflictVault '.obsidian\plugins\obsidian-local-rest-api'
    New-Item -ItemType Directory -Path $conflictPlugin -Force | Out-Null
    @{ id = 'obsidian-local-rest-api'; version = '5.1.0' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $conflictPlugin 'manifest.json') -Encoding UTF8
    '/* test fixture */' | Set-Content -LiteralPath (Join-Path $conflictPlugin 'main.js') -Encoding UTF8
    @{ apiKey = 'conflict-test-key'; enableInsecureServer = $false } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $conflictPlugin 'data.json') -Encoding UTF8
    $conflictConfig = Join-Path $fixtureRoot 'conflict-config.toml'
    @"
[mcp_servers.obsidian]
url = "https://127.0.0.1:27124/mcp/"
bearer_token_env_var = "OTHER_TOKEN"
startup_timeout_sec = 20
tool_timeout_sec = 60
"@.Trim() | Set-Content -LiteralPath $conflictConfig -Encoding UTF8
    $conflictRejected = $false
    try {
        & (Join-Path $repoRoot 'scripts\install.ps1') -VaultPath $conflictVault -CodexConfigPath $conflictConfig -AllowInsecureHttp -NoSecretImport | Out-Null
    }
    catch { $conflictRejected = $true }
    Assert-True $conflictRejected 'install.ps1 did not reject a conflicting MCP section.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $conflictVault '.codex-obsidian-knowledge.json'))) 'install.ps1 changed Vault settings before rejecting a config conflict.'
    $conflictData = Get-Content -LiteralPath (Join-Path $conflictPlugin 'data.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (-not [bool]$conflictData.enableInsecureServer) 'install.ps1 changed plugin settings before rejecting a config conflict.'
    Assert-True ((Get-Content -LiteralPath $conflictConfig -Raw -Encoding UTF8) -match 'OTHER_TOKEN') 'install.ps1 changed the conflicting Codex config.'

    $cleanCandidate = Join-Path $fixtureRoot 'clean.md'
    'Authorization: Bearer [REDACTED]' | Set-Content -LiteralPath $cleanCandidate -Encoding UTF8
    Assert-True ((Invoke-ScannerStatus $cleanCandidate) -eq 0) 'Sensitive-content scanner rejected a redacted bearer token.'
    $sourcePathCandidate = Join-Path $fixtureRoot 'source-path.md'
    'Source: skills/code-knowledge-capture/SKILL.md' | Set-Content -LiteralPath $sourcePathCandidate -Encoding UTF8
    Assert-True ((Invoke-ScannerStatus $sourcePathCandidate) -eq 0) 'Sensitive-content scanner rejected a repository source path.'
    $secretCandidate = Join-Path $fixtureRoot 'secret.md'
    'Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456' | Set-Content -LiteralPath $secretCandidate -Encoding UTF8
    $scanRejected = (Invoke-ScannerStatus $secretCandidate) -ne 0
    Assert-True $scanRejected 'Sensitive-content scanner did not reject a bearer token.'
    $providerKeyCandidate = Join-Path $fixtureRoot 'provider-key.md'
    'sk-proj-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789' | Set-Content -LiteralPath $providerKeyCandidate -Encoding UTF8
    Assert-True ((Invoke-ScannerStatus $providerKeyCandidate) -ne 0) 'Sensitive-content scanner did not reject a standalone provider key.'
    $entropyCandidate = Join-Path $fixtureRoot 'high-entropy.md'
    'p9K2mQ7vR4xT8nL3cW6yH1sF5jD0uB9eG2aZ7qX4' | Set-Content -LiteralPath $entropyCandidate -Encoding UTF8
    Assert-True ((Invoke-ScannerStatus $entropyCandidate) -ne 0) 'Sensitive-content scanner did not reject an unreviewed high-entropy token.'

    $validatedPathOutput = & (Join-Path $repoRoot 'scripts\validate-note-path.ps1') -VaultPath $installVault -ProjectId 'demo-project' -FeatureId 'feature-1'
    Assert-True ($validatedPathOutput -match 'Validated note path:') 'validate-note-path.ps1 did not validate a safe feature path.'
    $invalidPathRejected = $false
    try { & (Join-Path $repoRoot 'scripts\validate-note-path.ps1') -VaultPath $installVault -ProjectId '..' -FeatureId 'feature-1' | Out-Null }
    catch { $invalidPathRejected = $true }
    Assert-True $invalidPathRejected 'validate-note-path.ps1 accepted a traversal project ID.'
    $longPathRejected = $false
    try {
        & (Join-Path $repoRoot 'scripts\validate-note-path.ps1') -VaultPath $installVault -NoteRoot '' -ProjectId ('a' * 120) -FeatureId ('b' * 120) | Out-Null
    }
    catch { $longPathRejected = $true }
    Assert-True $longPathRejected 'validate-note-path.ps1 accepted a complete note path longer than 240 characters.'
}
finally {
    $resolvedFixtureRoot = [System.IO.Path]::GetFullPath($fixtureRoot)
    $expectedPrefix = $testsRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar + '.tmp-'
    if ($resolvedFixtureRoot.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedFixtureRoot)) {
        Remove-Item -LiteralPath $resolvedFixtureRoot -Recurse -Force
    }
}

Write-Output 'Repository validation passed.'
