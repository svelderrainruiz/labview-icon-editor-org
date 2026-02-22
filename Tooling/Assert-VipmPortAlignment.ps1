#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$SettingsPath,

    [ValidateRange(2000, 2100)]
    [int]$LabVIEWVersion,

    [ValidateSet('32', '64', 'both')]
    [string]$LabVIEWBitness = 'both',

    [switch]$IncludeDisabled,

    [switch]$Fix,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
$supportScript = Join-Path -Path $repoRoot -ChildPath 'Tooling\support\VipmPortAlignment.ps1'
if (-not (Test-Path -Path $supportScript)) {
    throw "Support script not found: $supportScript"
}
. $supportScript

$args = @{
    SettingsPath = $SettingsPath
    Bitness = $LabVIEWBitness
    IncludeDisabled = $IncludeDisabled
}
if ($PSBoundParameters.ContainsKey('LabVIEWVersion')) {
    $args.LabVIEWVersion = $LabVIEWVersion
}

$result = $null
if ($Fix.IsPresent) {
    $repair = Repair-VipmTargetPortAlignment @args
    $result = $repair.after
    if ($repair.changed) {
        Write-Host ("Updated VIPM target ports in '{0}' (backup: {1})." -f $result.settings_path, $repair.backup_path)
    } else {
        Write-Host 'No VIPM port changes were needed.'
    }
} else {
    $result = Test-VipmTargetPortAlignment @args
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputDir = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding ascii
}

if ($result.passed) {
    Write-Host ("VIPM port alignment check passed. targets={0}" -f $result.evaluated_target_count)
    exit 0
}

Write-Error ('VIPM port alignment check failed. mismatches={0}' -f $result.mismatch_count)
$result.mismatches | ConvertTo-Json -Depth 8 | Write-Host
exit 1

