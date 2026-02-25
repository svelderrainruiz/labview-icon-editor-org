#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [switch]$WriteSummary
)

$ErrorActionPreference = 'Stop'

$repoRootPath = (Resolve-Path -Path $RepoRoot -ErrorAction Stop).Path
$ciWorkflowPath = Join-Path $repoRootPath '.github\workflows\ci.yml'
$lvcontainerPath = Join-Path $repoRootPath '.lvcontainer'

$violations = New-Object System.Collections.Generic.List[object]

function Add-ContractViolation {
    param(
        [string]$Type,
        [string]$Message
    )

    $violations.Add([pscustomobject]@{
            Type    = $Type
            Message = $Message
        }) | Out-Null
}

if (-not (Test-Path -LiteralPath $ciWorkflowPath -PathType Leaf)) {
    Add-ContractViolation -Type 'missing-workflow' -Message "Required workflow file not found: .github/workflows/ci.yml"
}

if (-not (Test-Path -LiteralPath $lvcontainerPath -PathType Leaf)) {
    Add-ContractViolation -Type 'missing-lvcontainer' -Message 'Required container contract file not found: .lvcontainer'
}

$ciContent = if (Test-Path -LiteralPath $ciWorkflowPath -PathType Leaf) {
    Get-Content -LiteralPath $ciWorkflowPath -Raw
} else {
    ''
}

if ($ciContent) {
    if ($ciContent -match '(?ms)^\s*container-contract:\s*$') {
        Add-ContractViolation -Type 'duplicate-container-contract-job' -Message 'ci.yml must not define a container-contract job after parity ownership cutover.'
    }

    if ($ciContent -notmatch '(?ms)^  vi-analyzer:\s*$') {
        Add-ContractViolation -Type 'missing-vi-analyzer-job' -Message 'ci.yml must define a vi-analyzer job for self-hosted Windows lanes.'
    }
    $viAnalyzerBlockMatch = [regex]::Match(
        $ciContent,
        '(?ms)^\s{2}vi-analyzer:\s*$.*?(?=^\s{2}[A-Za-z0-9_-]+:\s*$|\z)'
    )
    if (-not $viAnalyzerBlockMatch.Success) {
        Add-ContractViolation -Type 'missing-vi-analyzer-block' -Message 'ci.yml must include a resolvable vi-analyzer job block.'
    } else {
        $viAnalyzerBlock = $viAnalyzerBlockMatch.Value
        if ($viAnalyzerBlock -notmatch 'name:\s*VI Analyzer Gate \(LV \${{\s*needs\.version-gate\.outputs\.raw\s*}} \${{\s*matrix\.bitness_label\s*}}\)') {
            Add-ContractViolation -Type 'missing-vi-analyzer-lane-name' -Message 'ci.yml vi-analyzer job name must use the descriptive contract VI Analyzer Gate (LV ${{ needs.version-gate.outputs.raw }} ${{ matrix.bitness_label }}).'
        }
        if ($viAnalyzerBlock -notmatch 'needs:\s*\[\s*run-metadata,\s*prerelease-context,\s*version-gate,\s*apply-deps-64,\s*apply-deps-32\s*\]') {
            Add-ContractViolation -Type 'missing-vi-analyzer-needs' -Message 'ci.yml vi-analyzer job must depend on run-metadata, prerelease-context, version-gate, apply-deps-64, and apply-deps-32.'
        }
        if ($viAnalyzerBlock -notmatch 'LVIE_REMEDIATE_LABVIEWCLI_PORT_CONTRACT:\s*\${{\s*vars\.LVIE_REMEDIATE_LABVIEWCLI_PORT_CONTRACT\s*\|\|\s*''1''\s*}}') {
            Add-ContractViolation -Type 'missing-vi-analyzer-port-remediation-env' -Message 'ci.yml vi-analyzer job must set LVIE_REMEDIATE_LABVIEWCLI_PORT_CONTRACT with default ''1''.'
        }
        if ($viAnalyzerBlock -notmatch 'Tooling/Run-ViAnalyzer\.ps1') {
            Add-ContractViolation -Type 'missing-vi-analyzer-runner' -Message 'ci.yml vi-analyzer job must run Tooling/Run-ViAnalyzer.ps1.'
        }
        if ($viAnalyzerBlock -match "(?m)^\s*if:\s*\$\{\{\s*needs\.prerelease-context\.outputs\.ci_profile != 'release-priority'\s*\}\}") {
            Add-ContractViolation -Type 'vi-analyzer-release-priority-gated' -Message 'ci.yml vi-analyzer job must remain enabled for release-priority; do not gate it out by ci_profile.'
        }
    }
    if ($ciContent -notmatch '(?ms)^  publish-gate:\s*.*?\n\s*-\s*vi-analyzer\s*$') {
        Add-ContractViolation -Type 'missing-vi-analyzer-publish-gate' -Message 'publish-gate needs list must include vi-analyzer.'
    }
    if ($ciContent -notmatch '(?ms)^  pipeline-contract:\s*.*?\n\s*-\s*vi-analyzer\s*$') {
        Add-ContractViolation -Type 'missing-vi-analyzer-pipeline-contract' -Message 'pipeline-contract needs list must include vi-analyzer.'
    }
    if ($ciContent -notmatch '(?ms)\$requiredFullValidation\s*=\s*@\(\s*.*?''vi-analyzer''') {
        Add-ContractViolation -Type 'missing-vi-analyzer-required-full' -Message 'profile requiredFullValidation list in ci.yml must include vi-analyzer.'
    }
    $releasePriorityViAnalyzerRequiredCount = [regex]::Matches(
        $ciContent,
        '(?ms)''release-priority''\s*=\s*@\(\$requiredCommon\s*\+\s*@\(''vi-analyzer''\)\)'
    ).Count
    if ($releasePriorityViAnalyzerRequiredCount -lt 2) {
        Add-ContractViolation -Type 'missing-vi-analyzer-required-release-priority' -Message 'profile requiredByProfile release-priority list in ci.yml must include vi-analyzer for both publish-gate and pipeline-contract checks.'
    }
}

if ($WriteSummary -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    if ($violations.Count -eq 0) {
        @(
            '### VI Analyzer Container Contract Guard'
            '- Status: pass'
            '- Result: Self-hosted CI vi-analyzer and parity merged container vi-analyzer wiring are valid for both Linux and Windows lanes.'
        ) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
    } else {
        @(
            '### VI Analyzer Container Contract Guard'
            '- Status: fail'
            ("- Violations: {0}" -f $violations.Count)
        ) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
    }
}

if ($violations.Count -gt 0) {
    $formatted = $violations | ForEach-Object {
        "[{0}] {1}" -f $_.Type, $_.Message
    }
    throw ("VI Analyzer container contract violations detected:{0}{1}" -f [Environment]::NewLine, ($formatted -join [Environment]::NewLine))
}

Write-Host 'VI Analyzer container contract guard passed with no violations.'
