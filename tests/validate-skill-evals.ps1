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
    'duplicate-evidence-is-noop',
    'expanded-depth-audit',
    'feature-capture-knowledge-first',
    'project-baseline-precedes-feature'
)
foreach ($id in $requiredIds) { if (-not $ids.ContainsKey($id)) { throw "Missing required behavior case: $id" } }
$implementedCase = $cases | Where-Object { $_.id -eq 'implemented-expanded-preview' } | Select-Object -First 1
if ([string]$implementedCase.expected.status -ne 'implemented') {
    throw 'Passing automated validation without runtime user-flow evidence must remain implemented, not verified.'
}
$depthCase = $cases | Where-Object { $_.id -eq 'expanded-depth-audit' } | Select-Object -First 1
if (-not [bool]$depthCase.expected.depth_required) {
    throw 'Expanded depth audit case must require deep exploration.'
}
$knowledgeCase = $cases | Where-Object { $_.id -eq 'feature-capture-knowledge-first' } | Select-Object -First 1
if (-not [bool]$knowledgeCase.expected.knowledge_first -or [string]$knowledgeCase.expected.verification_detail -ne 'minimal' -or [string]$knowledgeCase.expected.raw_test_content -ne 'omit-or-reference') {
    throw 'Knowledge-first feature capture case must require minimal, non-reporting verification content.'
}
$baselineCase = $cases | Where-Object { $_.id -eq 'project-baseline-precedes-feature' } | Select-Object -First 1
if (-not [bool]$baselineCase.expected.project_baseline_required -or [string]$baselineCase.expected.project_scope -ne 'mainline' -or [string]$baselineCase.expected.feature_scope -ne 'branch') {
    throw 'Project baseline case must require separate mainline and feature scopes.'
}
if ($schema.type -ne 'object' -or [bool]$schema.additionalProperties) { throw 'Skill eval output schema must be a closed object.' }
Write-Output 'Skill behavior case validation passed.'
