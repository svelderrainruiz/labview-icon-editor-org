#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [switch]$WriteSummary
)

$ErrorActionPreference = 'Stop'

$repoRootPath = (Resolve-Path -Path $RepoRoot -ErrorAction Stop).Path
$testPath = Join-Path -Path $repoRootPath -ChildPath 'Tooling\tests\CiVipProductionContract.Tests.ps1'

if (-not (Test-Path -Path $testPath -PathType Leaf)) {
    throw "CI VIP production contract test file not found: $testPath"
}

if (-not (Get-Module -ListAvailable -Name Pester)) {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module Pester -Scope CurrentUser -Force -AllowClobber
}

$configuration = New-PesterConfiguration
$configuration.Run.Path = @($testPath)
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'

$result = Invoke-Pester -Configuration $configuration
$status = if ($result.FailedCount -eq 0) { 'pass' } else { 'fail' }

if ($WriteSummary -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    $summary = @(
        '### CI VIP Production Contract'
        ("- Status: {0}" -f $status)
        ("- Passed: {0}" -f $result.PassedCount)
        ("- Failed: {0}" -f $result.FailedCount)
        ("- Skipped: {0}" -f $result.SkippedCount)
    )
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value ($summary -join [Environment]::NewLine)
}

if ($result.FailedCount -gt 0) {
    throw ("CI VIP production contract failed with {0} failing test(s)." -f $result.FailedCount)
}

Write-Host ("CI VIP production contract passed with {0} test(s)." -f $result.TotalCount)
