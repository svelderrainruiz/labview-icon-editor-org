#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Repository = $env:GITHUB_REPOSITORY,
    [string]$Branch = 'develop',
    [string]$WorkflowFile = 'ci.yml',
    [string]$OutputPath = 'builds/status/develop-vip-guarantee.json'
)

$ErrorActionPreference = 'Stop'

function Assert-GhAvailable {
    $command = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw 'GitHub CLI (gh) is required but was not found on PATH.'
    }
}

function Invoke-GhApiJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $raw = gh api $Path
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
        throw "gh api failed for path '$Path'."
    }

    return $raw | ConvertFrom-Json
}

function Write-Report {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Report,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedOutputPath = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    } else {
        Join-Path -Path (Get-Location) -ChildPath $Path
    }

    $outputDir = Split-Path -Path $resolvedOutputPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }

    $Report | ConvertTo-Json -Depth 10 | Out-File -FilePath $resolvedOutputPath -Encoding utf8
}

Assert-GhAvailable

if ([string]::IsNullOrWhiteSpace($Repository)) {
    throw 'Repository must be provided via -Repository or GITHUB_REPOSITORY.'
}

$headInfo = Invoke-GhApiJson -Path ("/repos/{0}/branches/{1}" -f $Repository, $Branch)
$headSha = [string]$headInfo.commit.sha
if ([string]::IsNullOrWhiteSpace($headSha)) {
    throw ("Unable to resolve head SHA for {0}:{1}" -f $Repository, $Branch)
}

$runsResponse = Invoke-GhApiJson -Path ("/repos/{0}/actions/workflows/{1}/runs?branch={2}&event=push&per_page=50" -f $Repository, $WorkflowFile, $Branch)
$workflowRuns = @($runsResponse.workflow_runs)

$headRuns = @($workflowRuns |
    Where-Object { [string]$_.head_sha -eq $headSha -and [string]$_.status -eq 'completed' } |
    Sort-Object { [datetime]$_.created_at } -Descending)

$run = $null
if ($headRuns.Count -gt 0) {
    $run = $headRuns[0]
}

$report = [ordered]@{
    repository = $Repository
    branch = $Branch
    workflow_file = $WorkflowFile
    head_sha = $headSha
    run_id = $null
    run_url = $null
    run_status = $null
    run_conclusion = $null
    attestation_artifact_found = $false
    status = 'failed'
    reason = ''
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
}

if ($null -eq $run) {
    $report.reason = 'no-completed-ci-run-for-latest-develop-head'
    Write-Report -Report ([pscustomobject]$report) -Path $OutputPath
    throw "No completed CI Pipeline push run found for latest head SHA '$headSha' on branch '$Branch'."
}

$report.run_id = [string]$run.id
$report.run_url = [string]$run.html_url
$report.run_status = [string]$run.status
$report.run_conclusion = [string]$run.conclusion

if ([string]$run.conclusion -ne 'success') {
    $report.reason = ("latest-head-ci-run-not-success:{0}" -f [string]$run.conclusion)
    Write-Report -Report ([pscustomobject]$report) -Path $OutputPath
    throw ("Latest head CI run {0} concluded with '{1}'." -f $run.id, $run.conclusion)
}

$artifactsResponse = Invoke-GhApiJson -Path ("/repos/{0}/actions/runs/{1}/artifacts?per_page=100" -f $Repository, $run.id)
$artifacts = @($artifactsResponse.artifacts)
$attestation = $artifacts | Where-Object { [string]$_.name -eq 'vip-production-attestation' } | Select-Object -First 1

if ($null -eq $attestation) {
    $report.reason = 'missing-vip-production-attestation-artifact'
    Write-Report -Report ([pscustomobject]$report) -Path $OutputPath
    throw ("Run {0} for latest head is missing required artifact 'vip-production-attestation'." -f $run.id)
}

$report.attestation_artifact_found = $true
$report.status = 'passed'
$report.reason = 'contract-satisfied'

Write-Report -Report ([pscustomobject]$report) -Path $OutputPath
Write-Host ("Develop VIP guarantee passed for {0} at SHA {1} (run {2})." -f $Repository, $headSha, $run.id)
