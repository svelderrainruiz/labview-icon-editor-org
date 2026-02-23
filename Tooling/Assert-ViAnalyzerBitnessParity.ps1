#Requires -Version 7.0
<#!
.SYNOPSIS
    Enforces VI Analyzer parity between 32-bit and 64-bit status reports.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$StatusPath32,

    [Parameter(Mandatory = $true)]
    [string]$StatusPath64,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = 'builds/status/vi-analyzer-bitness-parity.json'
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoRootPath {
    param([string]$PathOverride)

    if (-not [string]::IsNullOrWhiteSpace($PathOverride)) {
        return (Resolve-Path -Path $PathOverride -ErrorAction Stop).Path
    }

    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
    try {
        $gitRoot = git -C $scriptRoot rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitRoot)) {
            return (Resolve-Path -Path $gitRoot.Trim() -ErrorAction Stop).Path
        }
    } catch {
        Write-Verbose ("git rev-parse failed: {0}" -f $_.Exception.Message)
    }

    return (Resolve-Path -Path (Join-Path $scriptRoot '..')).Path
}

function Resolve-PathFromRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $Root $Path))
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "File not found: $Path"
    }

    $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "File is empty: $Path"
    }

    return ($raw | ConvertFrom-Json)
}

function New-TaskMap {
    param([Parameter(Mandatory = $true)]$TaskResults)

    $map = @{}
    foreach ($task in @($TaskResults)) {
        if ($null -eq $task) {
            continue
        }
        $id = [string]$task.id
        if ([string]::IsNullOrWhiteSpace($id)) {
            continue
        }
        $map[$id] = $task
    }

    return $map
}

function Add-Mismatch {
    param(
        [Parameter(Mandatory = $true)]
        [ref]$List,

        [Parameter(Mandatory = $true)]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [string]$Field,

        [Parameter(Mandatory = $false)]
        $Value32,

        [Parameter(Mandatory = $false)]
        $Value64,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $List.Value.Add([pscustomobject]@{
            scope   = $Scope
            field   = $Field
            value_32 = $Value32
            value_64 = $Value64
            message = $Message
        }) | Out-Null
}

function Get-NormalizedStringArray {
    param([Parameter(Mandatory = $false)]$Value)

    if ($null -eq $Value) {
        return @()
    }

    return @($Value | ForEach-Object { [string]$_ } | Sort-Object -Unique)
}

$repoRootResolved = Resolve-RepoRootPath -PathOverride $RepoRoot
$statusPath32Resolved = Resolve-PathFromRoot -Root $repoRootResolved -Path $StatusPath32
$statusPath64Resolved = Resolve-PathFromRoot -Root $repoRootResolved -Path $StatusPath64
$outputPathResolved = Resolve-PathFromRoot -Root $repoRootResolved -Path $OutputPath

$status32 = Read-JsonFile -Path $statusPath32Resolved
$status64 = Read-JsonFile -Path $statusPath64Resolved

$mismatches = New-Object System.Collections.Generic.List[object]

$taskMap32 = New-TaskMap -TaskResults $status32.task_results
$taskMap64 = New-TaskMap -TaskResults $status64.task_results

$taskIds32 = @($taskMap32.Keys | Sort-Object)
$taskIds64 = @($taskMap64.Keys | Sort-Object)
$allTaskIds = @($taskIds32 + $taskIds64 | Sort-Object -Unique)

$missingIn32 = @($taskIds64 | Where-Object { $_ -notin $taskIds32 })
$missingIn64 = @($taskIds32 | Where-Object { $_ -notin $taskIds64 })

if ($missingIn32.Count -gt 0) {
    Add-Mismatch -List ([ref]$mismatches) -Scope 'tasks' -Field 'missing_in_32' -Value32 $null -Value64 $missingIn32 -Message 'Task IDs present in 64-bit status but missing in 32-bit status.'
}
if ($missingIn64.Count -gt 0) {
    Add-Mismatch -List ([ref]$mismatches) -Scope 'tasks' -Field 'missing_in_64' -Value32 $missingIn64 -Value64 $null -Message 'Task IDs present in 32-bit status but missing in 64-bit status.'
}

$countKeys = @(
    'analyzed_total',
    'passed',
    'failed',
    'skipped',
    'vi_unloadable',
    'test_unloadable',
    'test_unrunnable',
    'test_error'
)

foreach ($taskId in $allTaskIds) {
    if (-not $taskMap32.ContainsKey($taskId) -or -not $taskMap64.ContainsKey($taskId)) {
        continue
    }

    $task32 = $taskMap32[$taskId]
    $task64 = $taskMap64[$taskId]

    if ([bool]$task32.succeeded -ne [bool]$task64.succeeded) {
        Add-Mismatch -List ([ref]$mismatches) -Scope $taskId -Field 'succeeded' -Value32 $task32.succeeded -Value64 $task64.succeeded -Message 'Task success state differs by bitness.'
    }

    foreach ($key in $countKeys) {
        $value32 = if ($null -ne $task32.counts) { $task32.counts.$key } else { $null }
        $value64 = if ($null -ne $task64.counts) { $task64.counts.$key } else { $null }
        if ($value32 -ne $value64) {
            Add-Mismatch -List ([ref]$mismatches) -Scope $taskId -Field ("counts.{0}" -f $key) -Value32 $value32 -Value64 $value64 -Message 'Task count differs by bitness.'
        }
    }

    $effective32 = $task32.effective_test_error_count
    $effective64 = $task64.effective_test_error_count
    if ($effective32 -ne $effective64) {
        Add-Mismatch -List ([ref]$mismatches) -Scope $taskId -Field 'effective_test_error_count' -Value32 $effective32 -Value64 $effective64 -Message 'Effective test-error count differs by bitness.'
    }

    $allowlisted32 = $task32.allowlisted_test_error_count
    $allowlisted64 = $task64.allowlisted_test_error_count
    if ($allowlisted32 -ne $allowlisted64) {
        Add-Mismatch -List ([ref]$mismatches) -Scope $taskId -Field 'allowlisted_test_error_count' -Value32 $allowlisted32 -Value64 $allowlisted64 -Message 'Allowlisted test-error count differs by bitness.'
    }

    $failurePaths32 = Get-NormalizedStringArray -Value $task32.failure_file_paths
    $failurePaths64 = Get-NormalizedStringArray -Value $task64.failure_file_paths
    if (-not [System.Linq.Enumerable]::SequenceEqual($failurePaths32, $failurePaths64)) {
        Add-Mismatch -List ([ref]$mismatches) -Scope $taskId -Field 'failure_file_paths' -Value32 $failurePaths32 -Value64 $failurePaths64 -Message 'Failure file paths differ by bitness.'
    }
}

$overallSuccess32 = [bool]$status32.overall_success
$overallSuccess64 = [bool]$status64.overall_success
if ($overallSuccess32 -ne $overallSuccess64) {
    Add-Mismatch -List ([ref]$mismatches) -Scope 'overall' -Field 'overall_success' -Value32 $overallSuccess32 -Value64 $overallSuccess64 -Message 'Overall success differs by bitness.'
}

$parityStatus = if ($mismatches.Count -eq 0) { 'success' } else { 'failed' }

$report = [ordered]@{
    generated_utc   = (Get-Date).ToUniversalTime().ToString('o')
    status          = $parityStatus
    status_paths    = [ordered]@{
        x86 = $statusPath32Resolved
        x64 = $statusPath64Resolved
    }
    task_ids        = $allTaskIds
    mismatch_count  = $mismatches.Count
    mismatches      = @($mismatches)
}

$outputDir = Split-Path -Path $outputPathResolved -Parent
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

$report | ConvertTo-Json -Depth 8 | Set-Content -Path $outputPathResolved -Encoding utf8

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    if ($parityStatus -eq 'success') {
        "VI Analyzer bitness parity passed (`$mismatches=0)." | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append
    } else {
        "VI Analyzer bitness parity failed (`$mismatches=$($mismatches.Count))." | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append
        foreach ($mismatch in @($mismatches)) {
            "- [$($mismatch.scope)] $($mismatch.field): x86='$($mismatch.value_32)' x64='$($mismatch.value_64)'" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append
        }
    }
    "Parity report: $outputPathResolved" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append
}

Write-Host ("VI Analyzer bitness parity report written to {0}" -f $outputPathResolved)

if ($parityStatus -ne 'success') {
    throw ("VI Analyzer bitness parity failed with {0} mismatch(es)." -f $mismatches.Count)
}
