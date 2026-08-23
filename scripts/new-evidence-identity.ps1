[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$ProjectId,
    [Parameter(Mandatory = $true)][string]$FeatureId,
    [string]$ThreadId = 'unknown',
    [string]$SourceCommit = 'unknown'
)

$ErrorActionPreference = 'Stop'
foreach ($entry in @(@('ProjectId', $ProjectId), @('FeatureId', $FeatureId))) {
    if ([string]$entry[1] -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { throw "$($entry[0]) must be a lowercase safe slug." }
}
if ($SourceCommit -ne 'unknown' -and $SourceCommit -notmatch '^[0-9a-fA-F]{7,64}$') { throw 'SourceCommit must be a Git object ID or unknown.' }
$resolvedManifest = [System.IO.Path]::GetFullPath($ManifestPath)
if (-not (Test-Path -LiteralPath $resolvedManifest -PathType Leaf)) { throw "Evidence manifest not found: $resolvedManifest" }

$scanner = Join-Path $PSScriptRoot 'scan-sensitive-content.ps1'
& $scanner -Path $resolvedManifest 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Evidence manifest contains sensitive-looking content and cannot be hashed until redacted.' }

try { $manifest = Get-Content -LiteralPath $resolvedManifest -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw 'Evidence manifest must be valid JSON.' }

function ConvertTo-CanonicalValue([object]$Value, [string]$PropertyName = '') {
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return $Value.Replace("`r`n", "`n").Replace("`r", "`n") }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $ordered = [ordered]@{}
        $propertyNames = [string[]]@($Value.psobject.Properties.Name)
        [Array]::Sort($propertyNames, [System.StringComparer]::Ordinal)
        foreach ($propertyName in $propertyNames) {
            $ordered[$propertyName] = ConvertTo-CanonicalValue $Value.psobject.Properties[$propertyName].Value $propertyName
        }
        return $ordered
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        $keyNames = [string[]]@($Value.Keys | ForEach-Object { [string]$_ })
        [Array]::Sort($keyNames, [System.StringComparer]::Ordinal)
        foreach ($keyName in $keyNames) { $ordered[$keyName] = ConvertTo-CanonicalValue $Value[$keyName] $keyName }
        return $ordered
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @($Value | ForEach-Object { ConvertTo-CanonicalValue $_ })
        if ($PropertyName -in @('files', 'tests')) {
            $sortable = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $items) { $sortable.Add($item) }
            $sortable.Sort([System.Comparison[object]]{
                param($left, $right)
                $leftKey = ConvertTo-Json -InputObject $left -Depth 50 -Compress
                $rightKey = ConvertTo-Json -InputObject $right -Depth 50 -Compress
                return [System.StringComparer]::Ordinal.Compare($leftKey, $rightKey)
            })
            $items = @($sortable)
        }
        # The unary comma prevents PowerShell from unrolling a one-item JSON array.
        return ,$items
    }
    return $Value
}

$canonical = ConvertTo-Json -InputObject (ConvertTo-CanonicalValue $manifest) -Depth 50 -Compress
$bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($canonical)
$sha = [System.Security.Cryptography.SHA256]::Create()
try { $hash = (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
finally { $sha.Dispose() }
$prefix = $hash.Substring(0, 16)
$safeThread = ([string]$ThreadId -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
if ([string]::IsNullOrWhiteSpace($safeThread)) { $safeThread = 'unknown' }
$captureId = if ($safeThread -ne 'unknown') { "codex:$safeThread`:$ProjectId`:$FeatureId`:$prefix" }
elseif ($SourceCommit -ne 'unknown') { "$ProjectId`:$FeatureId`:$($SourceCommit.ToLowerInvariant())`:$prefix" }
else { "$ProjectId`:$FeatureId`:$prefix" }

[PSCustomObject]@{
    capture_id = $captureId
    evidence_hash = $hash
    source_commit = $SourceCommit.ToLowerInvariant()
} | ConvertTo-Json
