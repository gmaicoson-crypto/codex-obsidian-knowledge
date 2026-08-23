[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Path
)

$ErrorActionPreference = 'Stop'
$textExtensions = @('.md', '.markdown', '.txt', '.json', '.yaml', '.yml', '.toml')
$rules = @(
    @{ Name = 'private-key'; Pattern = '-----BEGIN [A-Z0-9 ]+ PRIVATE KEY-----' },
    @{ Name = 'authorization-header'; Pattern = '(?im)\bAuthorization\s*:\s*Bearer\s+(?!\[REDACTED\]|<[^>]+>|\$[A-Za-z_][A-Za-z0-9_]*|\{[^}]+\})\S+' },
    @{ Name = 'credential-assignment'; Pattern = '(?im)\b(api[_-]?key|access[_-]?key|secret|password|passwd|token|cookie|private[_-]?key)\s*[:=]\s*["''`]?(?!\[REDACTED\])([A-Za-z0-9_./+=-]{12,})' },
    @{ Name = 'cloud-key-prefix'; Pattern = '\b(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,})\b' },
    @{ Name = 'model-provider-key-prefix'; Pattern = '\bsk-(?:(?:proj|ant)-)?[A-Za-z0-9_-]{20,}\b' },
    @{ Name = 'embedded-url-credential'; Pattern = '(?i)https?://[^\s/@:]+:[^\s/@]+@' }
)

function Get-ShannonEntropy([string]$Value) {
    if ([string]::IsNullOrEmpty($Value)) { return 0.0 }
    $entropy = 0.0
    foreach ($group in ($Value.ToCharArray() | Group-Object)) {
        $probability = [double]$group.Count / [double]$Value.Length
        $entropy -= $probability * [Math]::Log($probability, 2)
    }
    return $entropy
}

function Test-UnreviewedHighEntropyToken([string]$Line) {
    if ($Line -match '(?i)\b(sha-?256|checksum|digest|commit|content[-_ ]?hash)\b') { return $false }
    foreach ($match in [regex]::Matches($Line, '(?<![A-Za-z0-9+/=_-])[A-Za-z0-9+/=_-]{32,}(?![A-Za-z0-9+/=_-])')) {
        $candidate = $match.Value
        if ($candidate -match '^(?i:REDACTED|YOUR[_-]|EXAMPLE[_-]|PLACEHOLDER[_-])') { continue }
        $followingText = $Line.Substring($match.Index + $match.Length)
        $looksLikeRelativeFilePath =
            $candidate -match '^(?:[A-Za-z0-9_-]+/)+[A-Za-z0-9_-]+$' -and
            $followingText -match '^\.[A-Za-z0-9]{1,10}(?:\b|$)'
        $looksLikeUrlPath = $false
        foreach ($urlMatch in [regex]::Matches($Line, '(?i)https?://\S+')) {
            if ($match.Index -ge $urlMatch.Index -and ($match.Index + $match.Length) -le ($urlMatch.Index + $urlMatch.Length)) {
                $looksLikeUrlPath = $true
                break
            }
        }
        if ($looksLikeRelativeFilePath -or $looksLikeUrlPath) { continue }
        if ((Get-ShannonEntropy $candidate) -ge 4.2) { return $true }
    }
    return $false
}

function Get-ScanFiles([string]$InputPath) {
    $resolved = Resolve-Path -LiteralPath $InputPath -ErrorAction Stop
    foreach ($item in $resolved) {
        if ((Get-Item -LiteralPath $item.Path).PSIsContainer) {
            Get-ChildItem -LiteralPath $item.Path -Recurse -File | Where-Object { $textExtensions -contains $_.Extension.ToLowerInvariant() }
        }
        elseif ($textExtensions -contains ([System.IO.Path]::GetExtension($item.Path).ToLowerInvariant())) {
            Get-Item -LiteralPath $item.Path
        }
    }
}

$findings = @()
foreach ($file in ($Path | ForEach-Object { Get-ScanFiles $_ })) {
    $lines = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8)
    for ($lineNumber = 0; $lineNumber -lt $lines.Count; $lineNumber++) {
        $line = [string]$lines[$lineNumber]
        foreach ($rule in $rules) {
            if ($line -match $rule.Pattern) {
                $findings += [PSCustomObject]@{ Path = $file.FullName; Line = $lineNumber + 1; Rule = $rule.Name }
            }
        }
        if (Test-UnreviewedHighEntropyToken $line) {
            $findings += [PSCustomObject]@{ Path = $file.FullName; Line = $lineNumber + 1; Rule = 'unreviewed-high-entropy-token' }
        }
    }
}

if ($findings.Count -gt 0) {
    Write-Output 'Sensitive-content scan failed. Values are intentionally omitted.'
    $findings | Sort-Object Path, Line, Rule | ForEach-Object { Write-Output ("[FAIL] {0}:{1} ({2})" -f $_.Path, $_.Line, $_.Rule) }
    exit 1
}
Write-Output 'Sensitive-content scan passed.'
exit 0
