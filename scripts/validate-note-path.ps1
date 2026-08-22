[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VaultPath,

    [string]$NoteRoot = 'Codex知识库',

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FeatureId
)

$ErrorActionPreference = 'Stop'
$reservedNames = '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$'

function Test-SafeSegment([string]$Segment, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Segment) -or $Segment -in @('.', '..')) { throw "$Label cannot be empty or a navigation segment." }
    if ($Segment -match '[\x00-\x1F]' -or $Segment -match '[<>:"|?*\\/]' -or $Segment -match '[. ]$' -or $Segment -match '^\s') { throw "$Label contains an invalid filesystem character." }
    if ($Segment -match $reservedNames) { throw "$Label is a reserved Windows filename." }
    if ($Segment.Length -gt 120) { throw "$Label must be 120 characters or fewer." }
}

function Normalize-RelativePath([string]$Path, [string]$Label) {
    $normalized = ([string]$Path).Trim().Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($normalized) -or $normalized -eq '.') { return '' }
    if ([System.IO.Path]::IsPathRooted($normalized) -or $normalized.StartsWith('/') -or $normalized -match '(^|/)\.\.(/|$)') { throw "$Label must be relative to the Vault." }
    $segments = $normalized.Trim('/').Split('/')
    foreach ($segment in $segments) { Test-SafeSegment $segment $Label }
    $result = $segments -join '/'
    if ($result.Length -gt 240) { throw "$Label must be 240 characters or fewer." }
    return $result
}

$resolvedVault = [System.IO.Path]::GetFullPath($VaultPath)
if (-not (Test-Path -LiteralPath $resolvedVault -PathType Container)) { throw "Vault directory does not exist: $resolvedVault" }
$normalizedRoot = Normalize-RelativePath $NoteRoot 'NoteRoot'
Test-SafeSegment $ProjectId 'ProjectId'
Test-SafeSegment $FeatureId 'FeatureId'
$relativeProjectRoot = @($normalizedRoot, $ProjectId) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$relativeProjectRoot = $relativeProjectRoot -join '/'
$relativeFeatureRoot = "$relativeProjectRoot/features/$FeatureId"
$canonicalNotePaths = @(
    "$relativeProjectRoot/00-项目总览.md",
    "$relativeProjectRoot/01-架构与术语.md",
    "$relativeFeatureRoot/00-功能总览.md",
    "$relativeFeatureRoot/01-实现细节.md",
    "$relativeFeatureRoot/02-实施效果.md",
    "$relativeFeatureRoot/03-知识应用总结.md",
    "$relativeFeatureRoot/04-后续迭代方向.md",
    "$relativeFeatureRoot/99-相关对话与文件.md"
)
foreach ($relativeNotePath in $canonicalNotePaths) {
    if ($relativeNotePath.Length -gt 240) {
        throw "Generated note path exceeds 240 characters: $relativeNotePath"
    }
}
$projectRoot = if ([string]::IsNullOrWhiteSpace($normalizedRoot)) { Join-Path $resolvedVault $ProjectId } else { Join-Path (Join-Path $resolvedVault ($normalizedRoot -replace '/', '\')) $ProjectId }
$featureRoot = Join-Path (Join-Path $projectRoot 'features') $FeatureId
$resolvedFeatureRoot = [System.IO.Path]::GetFullPath($featureRoot)
$vaultPrefix = $resolvedVault.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if (-not $resolvedFeatureRoot.StartsWith($vaultPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Generated feature path escapes the Vault.' }
Write-Output "Validated note path: $resolvedFeatureRoot"
