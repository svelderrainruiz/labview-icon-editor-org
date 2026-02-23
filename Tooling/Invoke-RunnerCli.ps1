#Requires -Version 7.0
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)]
    [string]$RunnerCliProject,

    [string]$Configuration = 'Release',

    [switch]$SkipBuild,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RunnerCliArgs
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'dotnet is required to run runner-cli in-place.'
}

$projectPath = (Resolve-Path -Path $RunnerCliProject -ErrorAction Stop).Path
$projectDir = Split-Path -Path $projectPath -Parent

if (-not $SkipBuild.IsPresent) {
    $buildArgs = @(
        'build',
        $projectPath,
        '--configuration', $Configuration,
        '-p:SelfContained=false',
        '-p:UseAppHost=false'
    )
    & dotnet @buildArgs | Out-Host
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
        throw ("runner-cli build failed with exit code {0}." -f $LASTEXITCODE)
    }
}

$runnerCliDll = Join-Path $projectDir ("bin/{0}/net8.0/runner-cli.dll" -f $Configuration)
if (-not (Test-Path -Path $runnerCliDll -PathType Leaf)) {
    throw "runner-cli assembly was not found at $runnerCliDll"
}

& dotnet $runnerCliDll @RunnerCliArgs
$exitCode = $LASTEXITCODE
if ($null -ne $exitCode) {
    exit $exitCode
}

