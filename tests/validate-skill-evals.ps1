[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$casesPath = Join-Path $PSScriptRoot 'skill-evals\cases.json'
$schemaPath = Join-Path $PSScriptRoot 'skill-evals\output-schema.json'
$cases = @(Get-Content -LiteralPath $casesPath -Raw -Encoding UTF8 | ConvertFrom-Json)
$schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ($cases.Count -lt 6) { throw 'Skill behavior suite must contain at least six representative cases.' }
$ids = @{}
foreach ($case in $cases) {
    if ([string]::IsNullOrWhiteSpace([string]$case.id)) { throw 'Skill behavior case is missing id.' }
    if ($ids.ContainsKey([string]$case.id)) { throw "Duplicate skill behavior case id: $($case.id)" }
    $ids[[string]$case.id] = $true
    if ([string]::IsNullOrWhiteSpace([string]$case.request) -or [string]::IsNullOrWhiteSpace([string]$case.context)) {
        throw "Skill behavior case '$($case.id)' must contain a realistic request and context."
    }
    if ($null -eq $case.expected -or @($case.expected.psobject.Properties).Count -lt 2) {
        throw "Skill behavior case '$($case.id)' needs observable expectations."
    }
}

$requiredIds = @(
    'ordinary-explanation-does-not-capture',
    'design-compact-preview',
    'implemented-expanded-preview',
    'sensitive-evidence-is-redacted',
    'update-only-missing-target-blocks',
    'duplicate-evidence-is-noop'
)
foreach ($id in $requiredIds) { if (-not $ids.ContainsKey($id)) { throw "Missing required behavior case: $id" } }
$implementedCase = $cases | Where-Object { $_.id -eq 'implemented-expanded-preview' } | Select-Object -First 1
if ([string]$implementedCase.expected.status -ne 'implemented') {
    throw 'Passing automated validation without runtime user-flow evidence must remain implemented, not verified.'
}
if ($schema.type -ne 'object' -or [bool]$schema.additionalProperties) { throw 'Skill eval output schema must be a closed object.' }
Write-Output 'Skill behavior case validation passed.'
