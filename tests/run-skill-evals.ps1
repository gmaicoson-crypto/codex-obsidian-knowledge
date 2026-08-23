[CmdletBinding()]
param(
    [string]$CaseId,
    [switch]$ApproveCost
)

$ErrorActionPreference = 'Stop'
if (-not $ApproveCost) {
    throw 'Live skill evals invoke Codex and may consume model quota. Re-run with -ApproveCost.'
}
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { throw 'Codex CLI was not found on PATH.' }

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$skillPath = Join-Path $repoRoot 'skills\code-knowledge-capture\SKILL.md'
$cases = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'skill-evals\cases.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
if (-not [string]::IsNullOrWhiteSpace($CaseId)) { $cases = @($cases | Where-Object { $_.id -eq $CaseId }) }
if ($cases.Count -eq 0) { throw 'No matching skill eval case was found.' }

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-obsidian-skill-evals-$([guid]::NewGuid().ToString('N'))")
New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
try {
    foreach ($case in $cases) {
        $outputPath = Join-Path $temporaryRoot ("$($case.id).json")
        $prompt = @"
Read and apply the Codex skill at: $skillPath

Evaluate whether and how the skill should handle this request. This is an isolated read-only evaluation: do not configure Obsidian, do not call write tools, and do not modify files. Return only the requested JSON decision.

Case id: $($case.id)
User request: $($case.request)
Evidence context: $($case.context)
"@
        $prompt | codex exec - --ephemeral --ignore-user-config --ignore-rules --skip-git-repo-check --sandbox read-only --output-schema (Join-Path $PSScriptRoot 'skill-evals\output-schema.json') --output-last-message $outputPath --color never | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Codex eval failed for case '$($case.id)'." }
        $actual = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$actual.case_id -ne [string]$case.id) {
            throw "Case '$($case.id)' returned a mismatched case_id: $($actual.case_id)."
        }
        foreach ($property in $case.expected.psobject.Properties) {
            if ($actual.($property.Name) -ne $property.Value) {
                throw "Case '$($case.id)' failed: expected $($property.Name)=$($property.Value), received $($actual.($property.Name))."
            }
        }
        Write-Output "[PASS] $($case.id)"
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
}
