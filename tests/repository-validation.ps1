[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

foreach ($path in @(
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts') -Filter '*.ps1' -File
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests') -Filter '*.ps1' -File
)) {
    $relativePath = $path.FullName.Substring($repoRoot.Length + 1)
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-True ($errors.Count -eq 0) "$relativePath has PowerShell parse errors."
}

foreach ($relativePath in @(
    '.codex-plugin\plugin.json',
    '.agents\plugins\marketplace.json',
    'scripts\upstream-assets.json',
    'tests\skill-evals\cases.json',
    'tests\skill-evals\output-schema.json'
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
    Assert-True ($content -match 'schema_version:\s*2' -and $content -match 'capture_mode:\s*expanded') "$templateName is missing schema version 2 or capture mode."
    Assert-True ($content -match 'capture_id:\s*<capture-id>' -and $content -match 'evidence_hash:\s*<sha256>' -and $content -match 'source_commit:\s*unknown') "$templateName is missing capture identity fields."
}
$expectedNoteKinds = @{
    'feature-overview.md' = 'feature-overview'
    'implementation-details.md' = 'implementation-details'
    'implementation-effect.md' = 'implementation-effect'
    'iteration-roadmap.md' = 'iteration-roadmap'
    'knowledge-application.md' = 'knowledge-application'
    'source-index.md' = 'source-index'
}
foreach ($entry in $expectedNoteKinds.GetEnumerator()) {
    $content = Get-Content -LiteralPath (Join-Path $repoRoot "templates\$($entry.Key)") -Raw -Encoding UTF8
    Assert-True ($content -match ("note_kind:\s*" + [regex]::Escape($entry.Value))) "$($entry.Key) has the wrong note_kind."
}
$projectOverview = Get-Content -LiteralPath (Join-Path $repoRoot 'templates\project-overview.md') -Raw -Encoding UTF8
Assert-True ($projectOverview -match 'type:\s*code-project-overview' -and $projectOverview -match 'review:\s*pending') 'project-overview.md is missing project frontmatter.'
Assert-True ($projectOverview -match 'audience:\s*beginner-programmer' -and $projectOverview -match '如何运行、观察和调试' -and $projectOverview -match '功能学习路线') 'project-overview.md is missing beginner onboarding sections.'
Assert-True ($projectOverview -match 'schema_version:\s*2' -and $projectOverview -match 'note_kind:\s*project-overview') 'project-overview.md is missing schema version 2 metadata.'
$architectureTemplate = Get-Content -LiteralPath (Join-Path $repoRoot 'templates\architecture-and-terms.md') -Raw -Encoding UTF8
Assert-True ($architectureTemplate -match 'type:\s*code-project-architecture') 'architecture-and-terms.md is missing project architecture frontmatter.'
Assert-True ($architectureTemplate -match 'schema_version:\s*2' -and $architectureTemplate -match 'note_kind:\s*project-architecture') 'architecture-and-terms.md is missing schema version 2 metadata.'
Assert-True ($architectureTemplate -match 'audience:\s*beginner-programmer' -and $architectureTemplate -match '第一层：系统边界' -and $architectureTemplate -match '第二层：组件地图' -and $architectureTemplate -match '第三层：主流程' -and $architectureTemplate -match '关键术语表') 'architecture-and-terms.md is missing the beginner architecture layers or glossary.'
$featureOverview = Get-Content -LiteralPath (Join-Path $repoRoot 'templates\feature-overview.md') -Raw -Encoding UTF8
$implementationDetails = Get-Content -LiteralPath (Join-Path $repoRoot 'templates\implementation-details.md') -Raw -Encoding UTF8
$implementationEffect = Get-Content -LiteralPath (Join-Path $repoRoot 'templates\implementation-effect.md') -Raw -Encoding UTF8
$knowledgeApplication = Get-Content -LiteralPath (Join-Path $repoRoot 'templates\knowledge-application.md') -Raw -Encoding UTF8
$iterationRoadmap = Get-Content -LiteralPath (Join-Path $repoRoot 'templates\iteration-roadmap.md') -Raw -Encoding UTF8
$sourceIndex = Get-Content -LiteralPath (Join-Path $repoRoot 'templates\source-index.md') -Raw -Encoding UTF8
Assert-True ($featureOverview -match '学习目标与前置知识' -and $featureOverview -match '功能心智模型' -and $featureOverview -match '主要决策与权衡') 'feature-overview.md is missing learning goals, a mental model, or decision evidence.'
Assert-True ($featureOverview -match '深度探究结论' -and $featureOverview -match '关键问题与机制回答' -and $featureOverview -match '深度探究审计') 'feature-overview.md is missing the causal explanation or depth audit.'
Assert-True ($implementationDetails -match '端到端代码导读' -and $implementationDetails -match '输入从哪里来' -and $implementationDetails -match '关键语法/API' -and $implementationDetails -match '失败信号') 'implementation-details.md is missing the guided code-reading contract.'
Assert-True ($implementationDetails -match '机制拆解' -and $implementationDetails -match '反事实、边界与失败路径' -and $implementationDetails -match '反事实/边界') 'implementation-details.md is missing mechanism and counterfactual analysis.'
Assert-True ($implementationEffect -match '不同证据能证明什么' -and $implementationEffect -match '已知验证边界' -and $implementationEffect -match '回归、性能与运行影响') 'implementation-effect.md is missing evidence teaching or verification boundaries.'
Assert-True ($implementationEffect -match '证据如何支持结论' -and $implementationEffect -match '关键假设与反例') 'implementation-effect.md is missing claim-to-evidence or counterexample analysis.'
Assert-True ($knowledgeApplication -match '本功能关键术语' -and $knowledgeApplication -match '用自己的话检验理解' -and $knowledgeApplication -match '动手练习' -and $knowledgeApplication -match '预期观察/答案') 'knowledge-application.md is missing vocabulary, self-checks, or exercises.'
Assert-True ($knowledgeApplication -match '机制推导' -and $knowledgeApplication -match '反例或失败信号' -and $knowledgeApplication -match '深度探究复盘') 'knowledge-application.md is missing reusable mechanism and boundary analysis.'
Assert-True ($iterationRoadmap -match '为什么现在做' -and $iterationRoadmap -match '验收标准') 'iteration-roadmap.md is missing prioritization fields.'
Assert-True ($sourceIndex -match '证据台账' -and $sourceIndex -match '它不能证明什么') 'source-index.md is missing evidence boundaries.'

$learningGuidePath = Join-Path $repoRoot 'skills\code-knowledge-capture\references\beginner-learning-guide.md'
$captureModesPath = Join-Path $repoRoot 'skills\code-knowledge-capture\references\capture-modes.md'
$deepExplorationPath = Join-Path $repoRoot 'skills\code-knowledge-capture\references\deep-exploration-guide.md'
Assert-True (Test-Path -LiteralPath $learningGuidePath -PathType Leaf) 'The beginner learning guide is missing.'
Assert-True (Test-Path -LiteralPath $captureModesPath -PathType Leaf) 'The capture modes reference is missing.'
Assert-True (Test-Path -LiteralPath $deepExplorationPath -PathType Leaf) 'The deep exploration guide is missing.'
$skillContent = Get-Content -LiteralPath (Join-Path $repoRoot 'skills\code-knowledge-capture\SKILL.md') -Raw -Encoding UTF8
$learningGuide = Get-Content -LiteralPath $learningGuidePath -Raw -Encoding UTF8
$deepExplorationGuide = Get-Content -LiteralPath $deepExplorationPath -Raw -Encoding UTF8
$skillUiMetadata = Get-Content -LiteralPath (Join-Path $repoRoot 'skills\code-knowledge-capture\agents\openai.yaml') -Raw -Encoding UTF8
Assert-True ($skillContent -match 'beginner-learning-guide\.md' -and $skillContent -match 'audience:\s*beginner-programmer') 'SKILL.md does not route to the beginner learning guide or set the default audience.'
Assert-True ($skillContent -match 'capture-modes\.md' -and $skillContent -match 'evidence_hash' -and $skillContent -match 'capture_id') 'SKILL.md does not route capture modes or enforce capture identity.'
Assert-True ($learningGuide -match 'Two-layer explanations' -and $learningGuide -match 'Architecture for beginners' -and $learningGuide -match 'Self-checks and exercises') 'The beginner learning guide is missing a required teaching layer.'
Assert-True ($skillContent -match 'deep-exploration-guide\.md' -and $skillContent -match '深度探究审计') 'SKILL.md does not enforce the deep exploration audit.'
Assert-True ($deepExplorationGuide -match '六遍探究流程' -and $deepExplorationGuide -match '反事实' -and $deepExplorationGuide -match '证据不足') 'The deep exploration guide is missing mechanism, counterfactual, or evidence-gap guidance.'
Assert-True ($skillUiMetadata -match 'short_description:\s*"[^"]*beginner-friendly[^"]*"') 'agents/openai.yaml does not describe the beginner-friendly learning workflow.'
Assert-True ($skillUiMetadata -match 'default_prompt:\s*"Use \$code-knowledge-capture\b') 'agents/openai.yaml default_prompt must explicitly invoke $code-knowledge-capture.'
Assert-True ($skillUiMetadata -match 'icon_small:' -and $skillUiMetadata -match 'icon_large:' -and $skillUiMetadata -match 'brand_color:') 'agents/openai.yaml is missing visual metadata.'
$shortDescriptionMatch = [regex]::Match($skillUiMetadata, '(?m)^\s*short_description:\s*"([^"]+)"\s*$')
Assert-True ($shortDescriptionMatch.Success -and $shortDescriptionMatch.Groups[1].Value.Length -ge 25 -and $shortDescriptionMatch.Groups[1].Value.Length -le 64) 'agents/openai.yaml short_description must contain 25-64 characters.'
$assetMetadata = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\upstream-assets.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($assetMetadata.pluginId -eq 'obsidian-local-rest-api' -and $assetMetadata.version -eq '5.1.0') 'upstream asset metadata has the wrong pinned plugin identity.'
foreach ($assetName in @('main.js', 'manifest.json', 'styles.css')) {
    $assetHash = [string]$assetMetadata.assets.$assetName
    Assert-True ($assetHash -match '^[0-9a-f]{64}$') "upstream-assets.json has an invalid SHA-256 for $assetName."
}
$pluginManifest = Get-Content -LiteralPath (Join-Path $repoRoot '.codex-plugin\plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ([string]$pluginManifest.version -eq '0.3.0') 'Plugin manifest version must be 0.3.0.'
Assert-True ([string]$pluginManifest.author.name -eq 'gmaicoson-crypto') 'Plugin manifest must identify the repository maintainer.'
foreach ($assetPath in @($pluginManifest.interface.composerIcon, $pluginManifest.interface.logo, $pluginManifest.interface.logoDark) + @($pluginManifest.interface.screenshots)) {
    $resolvedAsset = Join-Path $repoRoot ([string]$assetPath).TrimStart('./').Replace('/', '\')
    Assert-True (Test-Path -LiteralPath $resolvedAsset -PathType Leaf) "Plugin visual asset is missing: $assetPath"
}
Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'PRIVACY.md') -PathType Leaf) 'PRIVACY.md is missing.'
$marketplaceManifest = Get-Content -LiteralPath (Join-Path $repoRoot '.agents\plugins\marketplace.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ([string]$marketplaceManifest.plugins[0].source.path -eq './plugins/codex-obsidian-knowledge') 'Marketplace source must use the standard generated plugin directory.'
Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'scripts\build-plugin-package.ps1') -PathType Leaf) 'PowerShell plugin package builder is missing.'
Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'scripts\build-plugin-package.sh') -PathType Leaf) 'macOS plugin package builder is missing.'
Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'scripts\new-evidence-identity.ps1') -PathType Leaf) 'PowerShell evidence identity helper is missing.'
Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot 'scripts\new-evidence-identity.sh') -PathType Leaf) 'macOS evidence identity helper is missing.'

$scannerScript = Join-Path $repoRoot 'scripts\scan-sensitive-content.ps1'
function Invoke-ScannerStatus([string]$CandidatePath) {
    & $script:scannerScript -Path $CandidatePath 2>&1 | Out-Null
    return $LASTEXITCODE
}

$bootstrapPowerShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\bootstrap.ps1') -Raw -Encoding UTF8
$normalizeIndex = $bootstrapPowerShell.LastIndexOf('$noteRoot = Normalize-NoteRoot $NoteRoot', [System.StringComparison]::Ordinal)
$installIndex = $bootstrapPowerShell.LastIndexOf('$apiKey = Install-LocalRestApi', [System.StringComparison]::Ordinal)
Assert-True ($normalizeIndex -ge 0 -and $installIndex -ge 0 -and $normalizeIndex -lt $installIndex) 'bootstrap.ps1 must validate NoteRoot before installing the plugin.'
Assert-True ($bootstrapPowerShell -match 'pluginData\.enableInsecureServer\s*=\s*\$EnableInsecureServer') 'bootstrap.ps1 must reconcile the plugin HTTP server in both directions.'
Assert-True ($bootstrapPowerShell -match 'CODEX_HOME') 'bootstrap.ps1 must respect CODEX_HOME.'
Assert-True ($bootstrapPowerShell -match 'Assert-AssetIntegrity') 'bootstrap.ps1 must verify upstream asset hashes.'
Assert-True ($bootstrapPowerShell -match 'backupRoot') 'bootstrap.ps1 must use a rollback-capable commit.'
Assert-True ($bootstrapPowerShell -match 'ConvertTo-Json -InputObject \$Value') 'bootstrap.ps1 must preserve single-element JSON arrays.'
Assert-True ($bootstrapPowerShell -match 'Write-Utf8Text \$zshEnvPath \$updated -OwnerOnly') 'bootstrap.ps1 must protect the API key stored in .zshenv.'

$bootstrapShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\bootstrap.sh') -Raw -Encoding UTF8
Assert-True ($bootstrapShell -match 'data\.enableInsecureServer = enableInsecureServer') 'bootstrap.sh must reconcile the plugin HTTP server in both directions.'
Assert-True ($bootstrapShell -match '\[\[ "\$NOTE_ROOT" != /\* \]\]') 'bootstrap.sh must reject absolute NoteRoot values before trimming them.'

$unsupportedJxaGetenv = '$.' + 'getenv('
$unsupportedJxaConsole = 'console.' + 'log('
foreach ($shellPath in @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts') -Filter '*.sh' -File) + @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests') -Filter '*.sh' -File)) {
    $shellSource = Get-Content -LiteralPath $shellPath.FullName -Raw -Encoding UTF8
    Assert-True (-not $shellSource.Contains($unsupportedJxaGetenv)) "$($shellPath.Name) must use NSProcessInfo.environment instead of the unavailable JXA getenv helper."
    Assert-True (-not $shellSource.Contains($unsupportedJxaConsole)) "$($shellPath.Name) must return JXA values to osascript stdout instead of logging them."
}

$installShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\install-plugin.sh') -Raw -Encoding UTF8
Assert-True ($installShell.Contains('user_codex_root="${CODEX_HOME:-$HOME/.codex}"')) 'install-plugin.sh must treat CODEX_HOME as the Codex root.'

$doctorPowerShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\doctor.ps1') -Raw -Encoding UTF8
Assert-True ($doctorPowerShell -match 'Invoke-WebRequest -Uri \$endpoint -Method Post') 'doctor.ps1 must perform an MCP initialize request.'
Assert-True (-not $doctorPowerShell.Contains('Skipped HTTP handshake')) 'doctor.ps1 must not report a skipped HTTPS handshake as successful.'
Assert-True ($doctorPowerShell -match 'CODEX_HOME') 'doctor.ps1 must respect CODEX_HOME.'
Assert-True ($doctorPowerShell -match 'IsNullOrWhiteSpace\(\$processToken\).*\$processToken.*\$userToken') 'doctor.ps1 must prefer the process credential that a launched Codex process inherits.'
Assert-True ($doctorPowerShell -match 'Invoke-WebRequest.*-TimeoutSec\s+5') 'doctor.ps1 must bound the MCP initialize request.'
Assert-True ($doctorPowerShell -match 'Plugin protocol mode' -and $doctorPowerShell -match '\$Repair') 'doctor.ps1 must verify protocol state and support explicit repair.'

$doctorShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\doctor.sh') -Raw -Encoding UTF8
Assert-True ($doctorShell -match 'bearer_token_env_var') 'doctor.sh must read the credential source from Codex config.'
Assert-True ($doctorShell -match 'method.*initialize') 'doctor.sh must perform an MCP initialize request.'
Assert-True ($doctorShell -match 'Plugin protocol mode' -and $doctorShell -match 'REPAIR=0') 'doctor.sh must verify protocol state and support explicit repair.'
$bootstrapShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\bootstrap.sh') -Raw -Encoding UTF8
Assert-True ($bootstrapShell -match 'upstream-assets\.json' -and $bootstrapShell -match 'shasum -a 256') 'bootstrap.sh must load and verify pinned upstream asset hashes.'
Assert-True ($bootstrapShell -match 'backup_dir' -and $bootstrapShell -match 'original files were restored') 'bootstrap.sh must restore originals after a failed commit.'
$installPowerShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\install.ps1') -Raw -Encoding UTF8
Assert-True ($installPowerShell -match 'CODEX_HOME' -and $installPowerShell -match 'Commit-Files') 'install.ps1 must respect CODEX_HOME and commit changes transactionally.'
$installPluginShell = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\install-plugin.sh') -Raw -Encoding UTF8
Assert-True ($installPluginShell -match 'json_field' -and $installPluginShell -notmatch "plugin_name='codex-obsidian-knowledge'") 'install-plugin.sh must derive names from manifests.'
Assert-True ($installPluginShell -match 'marketplace_added_by_this_run' -and $installPluginShell -match 'marketplace remove') 'install-plugin.sh must roll back a marketplace added by a failed install.'

& (Join-Path $repoRoot 'tests\validate-skill-evals.ps1') | Out-Null
& (Join-Path $repoRoot 'tests\release-validation.ps1') | Out-Null

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

    $fakeBin = Join-Path $fixtureRoot 'fake-codex-bin'
    $fakeCodexHome = Join-Path $fixtureRoot 'fake-codex-home'
    $fakeCodexLog = Join-Path $fixtureRoot 'fake-codex.log'
    New-Item -ItemType Directory -Path $fakeBin, $fakeCodexHome -Force | Out-Null
    @'
@echo off
if "%1 %2 %3"=="plugin marketplace list" exit /b 0
if "%1 %2"=="plugin list" exit /b 0
if "%1 %2 %3"=="plugin marketplace add" exit /b 0
if "%1 %2 %3"=="plugin marketplace remove" (
  echo rollback>>"%FAKE_CODEX_LOG%"
  exit /b 0
)
if "%1 %2"=="plugin add" exit /b 1
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $fakeBin 'codex.cmd') -Encoding Ascii
    $previousPath = $env:PATH
    $previousFakeLog = $env:FAKE_CODEX_LOG
    $previousCodexHomeForRollback = $env:CODEX_HOME
    $rollbackTriggered = $false
    try {
        $env:PATH = $fakeBin + [System.IO.Path]::PathSeparator + $previousPath
        $env:FAKE_CODEX_LOG = $fakeCodexLog
        $env:CODEX_HOME = $fakeCodexHome
        try { & (Join-Path $repoRoot 'scripts\install-plugin.ps1') -Approve | Out-Null }
        catch { $rollbackTriggered = $true }
    }
    finally {
        $env:PATH = $previousPath
        if ($null -eq $previousFakeLog) { Remove-Item Env:FAKE_CODEX_LOG -ErrorAction SilentlyContinue } else { $env:FAKE_CODEX_LOG = $previousFakeLog }
        if ($null -eq $previousCodexHomeForRollback) { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue } else { $env:CODEX_HOME = $previousCodexHomeForRollback }
    }
    Assert-True $rollbackTriggered 'install-plugin.ps1 did not surface a simulated plugin installation failure.'
    Assert-True ((Get-Content -LiteralPath $fakeCodexLog -Raw -Encoding UTF8) -match 'rollback') 'install-plugin.ps1 did not roll back the marketplace added by the failed install.'

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

    $knowledgeNote = Join-Path $installVault 'Codex知识库\demo-project\00-项目总览.md'
    New-Item -ItemType Directory -Path (Split-Path -Parent $knowledgeNote) -Force | Out-Null
    '# Preserve this knowledge note' | Set-Content -LiteralPath $knowledgeNote -Encoding UTF8
    Add-Content -LiteralPath $fixtureConfig -Value "`n[ui]`ntheme = `"dark`"" -Encoding UTF8
    & (Join-Path $repoRoot 'scripts\disconnect.ps1') -VaultPath $installVault -CodexConfigPath $fixtureConfig -Approve | Out-Null
    $disconnectedData = Get-Content -LiteralPath (Join-Path $pluginDirectory 'data.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (-not [bool]$disconnectedData.enableInsecureServer) 'disconnect.ps1 did not disable the HTTP fallback.'
    Assert-True (Test-Path -LiteralPath $pluginDirectory -PathType Container) 'disconnect.ps1 removed plugin files.'
    Assert-True (Test-Path -LiteralPath (Join-Path $installVault '.codex-obsidian-knowledge.json') -PathType Leaf) 'disconnect.ps1 removed integration settings.'
    $disconnectedConfig = Get-Content -LiteralPath $fixtureConfig -Raw -Encoding UTF8
    Assert-True ($disconnectedConfig -notmatch '\[mcp_servers\.obsidian\]' -and $disconnectedConfig -match '\[ui\]') 'disconnect.ps1 did not remove only the managed MCP section.'
    Assert-True (Test-Path -LiteralPath $knowledgeNote -PathType Leaf) 'disconnect.ps1 removed a knowledge note.'

    & (Join-Path $repoRoot 'scripts\install.ps1') -VaultPath $installVault -CodexConfigPath $fixtureConfig -NoSecretImport | Out-Null
    $httpsData = Get-Content -LiteralPath (Join-Path $pluginDirectory 'data.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (-not [bool]$httpsData.enableInsecureServer) 'install.ps1 did not keep the HTTP fallback disabled after returning to HTTPS.'
    Assert-True ((Get-Content -LiteralPath $fixtureConfig -Raw -Encoding UTF8) -match 'https://127\.0\.0\.1:27124/mcp/') 'install.ps1 did not restore the HTTPS endpoint after disconnect.'

    $previousProcessSecret = [Environment]::GetEnvironmentVariable('OBSIDIAN_LOCAL_REST_API_KEY', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('OBSIDIAN_LOCAL_REST_API_KEY', [string]$httpsData.apiKey, 'Process')
        & (Join-Path $repoRoot 'scripts\rotate-key.ps1') -VaultPath $installVault -CodexConfigPath $fixtureConfig -SecretScope Process -Approve | Out-Null
        $rotatedData = Get-Content -LiteralPath (Join-Path $pluginDirectory 'data.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $rotatedProcessSecret = [Environment]::GetEnvironmentVariable('OBSIDIAN_LOCAL_REST_API_KEY', 'Process')
        Assert-True ([string]$rotatedData.apiKey -ne [string]$httpsData.apiKey) 'rotate-key.ps1 did not change the plugin key.'
        Assert-True ([string]$rotatedData.apiKey -ceq $rotatedProcessSecret) 'rotate-key.ps1 did not update the selected credential scope.'
    }
    finally {
        [Environment]::SetEnvironmentVariable('OBSIDIAN_LOCAL_REST_API_KEY', $previousProcessSecret, 'Process')
    }

    @('obsidian-local-rest-api', 'other-plugin') | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $installVault '.obsidian\community-plugins.json') -Encoding UTF8
    & (Join-Path $repoRoot 'scripts\uninstall.ps1') -VaultPath $installVault -CodexConfigPath $fixtureConfig -Approve | Out-Null
    Assert-True (-not (Test-Path -LiteralPath $pluginDirectory)) 'uninstall.ps1 did not remove the selected third-party plugin files.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $installVault '.codex-obsidian-knowledge.json'))) 'uninstall.ps1 did not remove integration settings.'
    Assert-True (Test-Path -LiteralPath $knowledgeNote -PathType Leaf) 'uninstall.ps1 removed a knowledge note.'
    $remainingPlugins = @((Get-Content -LiteralPath (Join-Path $installVault '.obsidian\community-plugins.json') -Raw -Encoding UTF8 | ConvertFrom-Json))
    Assert-True ($remainingPlugins.Count -eq 1 -and $remainingPlugins[0] -eq 'other-plugin') 'uninstall.ps1 changed unrelated community plugins.'
    $uninstalledConfig = Get-Content -LiteralPath $fixtureConfig -Raw -Encoding UTF8
    Assert-True ($uninstalledConfig -notmatch '\[mcp_servers\.obsidian\]' -and $uninstalledConfig -match '\[ui\]') 'uninstall.ps1 did not preserve unrelated Codex config.'

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

    $conflictDataBeforeRepair = Get-Content -LiteralPath (Join-Path $conflictPlugin 'data.json') -Raw -Encoding UTF8
    $foreignVariableRepairRejected = $false
    try { & (Join-Path $repoRoot 'scripts\doctor.ps1') -VaultPath $conflictVault -CodexConfigPath $conflictConfig -Repair -Approve | Out-Null }
    catch { $foreignVariableRepairRejected = $true }
    Assert-True $foreignVariableRepairRejected 'doctor.ps1 repaired a config that uses a foreign bearer_token_env_var.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $conflictPlugin 'data.json') -Raw -Encoding UTF8) -ceq $conflictDataBeforeRepair) 'doctor.ps1 changed plugin settings before rejecting a foreign bearer_token_env_var.'

    $repairProcessConfig = Join-Path $fixtureRoot 'repair-process-config.toml'
    @"
[mcp_servers.obsidian]
url = "https://127.0.0.1:27124/mcp/"
bearer_token_env_var = "OBSIDIAN_LOCAL_REST_API_KEY"
startup_timeout_sec = 20
tool_timeout_sec = 60
"@.Trim() | Set-Content -LiteralPath $repairProcessConfig -Encoding UTF8
    $previousRepairProcessSecret = [Environment]::GetEnvironmentVariable('OBSIDIAN_LOCAL_REST_API_KEY', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('OBSIDIAN_LOCAL_REST_API_KEY', 'foreign-process-key', 'Process')
        $foreignProcessRepairRejected = $false
        try { & (Join-Path $repoRoot 'scripts\doctor.ps1') -VaultPath $conflictVault -CodexConfigPath $repairProcessConfig -Repair -Approve | Out-Null }
        catch { $foreignProcessRepairRejected = $true }
        Assert-True $foreignProcessRepairRejected 'doctor.ps1 replaced a process credential owned by another Vault.'
    }
    finally {
        [Environment]::SetEnvironmentVariable('OBSIDIAN_LOCAL_REST_API_KEY', $previousRepairProcessSecret, 'Process')
    }

    $cleanCandidate = Join-Path $fixtureRoot 'clean.md'
    'Authorization: Bearer [REDACTED]' | Set-Content -LiteralPath $cleanCandidate -Encoding UTF8
    Assert-True ((Invoke-ScannerStatus $cleanCandidate) -eq 0) 'Sensitive-content scanner rejected a redacted bearer token.'
    $sourcePathCandidate = Join-Path $fixtureRoot 'source-path.md'
    'Source: skills/code-knowledge-capture/SKILL.md' | Set-Content -LiteralPath $sourcePathCandidate -Encoding UTF8
    Assert-True ((Invoke-ScannerStatus $sourcePathCandidate) -eq 0) 'Sensitive-content scanner rejected a repository source path.'
    $repositoryUrlCandidate = Join-Path $fixtureRoot 'repository-url.md'
    'Security: https://github.com/gmaicoson-crypto/codex-obsidian-knowledge/security/advisories/new' | Set-Content -LiteralPath $repositoryUrlCandidate -Encoding UTF8
    Assert-True ((Invoke-ScannerStatus $repositoryUrlCandidate) -eq 0) 'Sensitive-content scanner rejected a repository URL.'
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
    $pathLikeEntropyCandidate = Join-Path $fixtureRoot 'path-like-high-entropy.md'
    'segment/p9K2mQ7vR4xT8nL3cW6yH1sF5jD0uB9eG2aZ7qX4' | Set-Content -LiteralPath $pathLikeEntropyCandidate -Encoding UTF8
    Assert-True ((Invoke-ScannerStatus $pathLikeEntropyCandidate) -ne 0) 'Sensitive-content scanner exempted an unlabeled high-entropy value merely because it contained a slash.'

    $identityManifestA = Join-Path $fixtureRoot 'evidence-a.json'
    $identityManifestB = Join-Path $fixtureRoot 'evidence-b.json'
    '{"files":[{"path":"src/中文.ts","lines":[1,2]},{"path":"src/a.ts","lines":[3]}],"tests":["unit","integration"],"note":"line1\r\nline2"}' | Set-Content -LiteralPath $identityManifestA -Encoding UTF8
    '{"note":"line1\nline2","tests":["integration","unit"],"files":[{"lines":[3],"path":"src/a.ts"},{"lines":[1,2],"path":"src/中文.ts"}]}' | Set-Content -LiteralPath $identityManifestB -Encoding UTF8
    $identityA = & (Join-Path $repoRoot 'scripts\new-evidence-identity.ps1') -ManifestPath $identityManifestA -ProjectId 'demo-project' -FeatureId 'feature-1' -ThreadId 'thread/42' -SourceCommit 'ABCDEF1' | ConvertFrom-Json
    $identityB = & (Join-Path $repoRoot 'scripts\new-evidence-identity.ps1') -ManifestPath $identityManifestB -ProjectId 'demo-project' -FeatureId 'feature-1' -ThreadId 'thread/42' -SourceCommit 'abcdef1' | ConvertFrom-Json
    Assert-True ($identityA.evidence_hash -eq $identityB.evidence_hash) 'Evidence hashing is not stable across object order, unordered evidence arrays, or line endings.'
    Assert-True ($identityA.evidence_hash -eq 'ae050bd1978f16b0a3a8d464d373bbdda6125d3d0e345ef2694bec052f1ed414') "Evidence canonicalization changed unexpectedly: $($identityA.evidence_hash)"
    Assert-True ($identityA.capture_id -eq $identityB.capture_id -and $identityA.capture_id -match '^codex:thread-42:demo-project:feature-1:[0-9a-f]{16}$') 'Evidence capture ID is not stable or safely normalized.'
    Assert-True ($identityA.source_commit -eq 'abcdef1') 'Evidence identity did not normalize the source commit.'
    $sensitiveIdentityManifest = Join-Path $fixtureRoot 'evidence-sensitive.json'
    '{"request":"Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456"}' | Set-Content -LiteralPath $sensitiveIdentityManifest -Encoding UTF8
    $sensitiveIdentityRejected = $false
    try { & (Join-Path $repoRoot 'scripts\new-evidence-identity.ps1') -ManifestPath $sensitiveIdentityManifest -ProjectId 'demo-project' -FeatureId 'feature-1' | Out-Null }
    catch { $sensitiveIdentityRejected = $true }
    Assert-True $sensitiveIdentityRejected 'Evidence identity helper hashed a sensitive manifest.'

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
exit 0
