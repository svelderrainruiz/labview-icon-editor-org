#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [ValidateSet('all', 'ci-only')]
    [string]$Scope = 'all',
    [switch]$WriteSummary
)

$ErrorActionPreference = 'Stop'

$repoRootPath = (Resolve-Path -Path $RepoRoot -ErrorAction Stop).Path

$allTargetFiles = @(
    '.github/workflows/ci.yml'
)

$targetFiles = switch ($Scope) {
    'ci-only' {
        @(
            '.github/workflows/ci.yml'
        )
    }
    default {
        $allTargetFiles
    }
}

$ruleList = @(
    [pscustomobject]@{
        Type    = 'workflow-devmode-script'
        Pattern = 'Set_Development_Mode\.ps1|RevertDevelopmentMode\.ps1'
        Message = 'Automation workflows must not invoke dev-mode toggle scripts.'
        Files   = @(
            '.github/workflows/ci.yml'
        )
    },
    [pscustomobject]@{
        Type    = 'workflow-revert-devmode-input'
        Pattern = 'revert_dev_mode'
        Message = 'CI workflows must not pass revert_dev_mode teardown inputs.'
        Files   = @(
            '.github/workflows/ci.yml'
        )
    },
    [pscustomobject]@{
        Type    = 'workflow-devmode-smoke-job'
        Pattern = 'devmode-no-labview-smoke|DevMode\.NoLabVIEW Smoke'
        Message = 'ci.yml must not include the devmode-no-labview-smoke job or dependencies.'
        Files   = @(
            '.github/workflows/ci.yml'
        )
    }
)

$violationList = New-Object System.Collections.Generic.List[object]

foreach ($relativePathRaw in $targetFiles) {
    $relativePath = $relativePathRaw -replace '\\', '/'
    $fullPath = Join-Path -Path $repoRootPath -ChildPath ($relativePathRaw -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $violationList.Add([pscustomobject]@{
                Type    = 'missing-target-file'
                File    = $relativePath
                Line    = 0
                Pattern = '<file-exists>'
                Message = 'Required CI contract file is missing.'
            }) | Out-Null
        continue
    }

    $lineItems = Get-Content -LiteralPath $fullPath -ErrorAction Stop
    $lineNumber = 0
    foreach ($lineText in $lineItems) {
        $lineNumber++
        foreach ($rule in $ruleList) {
            if ($rule.Files -notcontains $relativePath) {
                continue
            }

            if ($lineText -match $rule.Pattern) {
                $violationList.Add([pscustomobject]@{
                        Type    = $rule.Type
                        File    = $relativePath
                        Line    = $lineNumber
                        Pattern = $rule.Pattern
                        Message = $rule.Message
                    }) | Out-Null
            }
        }
    }
}

if ($WriteSummary -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    if ($violationList.Count -eq 0) {
        @(
            '### CI Selector/DevMode Contract Guard'
            '- Status: pass'
            '- Result: no CI selector/dev-mode contract violations detected.'
        ) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
    } else {
        @(
            '### CI Selector/DevMode Contract Guard'
            '- Status: fail'
            ("- Violations: {0}" -f $violationList.Count)
        ) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
    }
}

if ($violationList.Count -gt 0) {
    $formatted = $violationList | ForEach-Object {
        "{0}:{1} [{2}] {3}" -f $_.File, $_.Line, $_.Type, $_.Message
    }
    throw ("CI selector/dev-mode contract violations detected:{0}{1}" -f [Environment]::NewLine, ($formatted -join [Environment]::NewLine))
}

Write-Host 'CI selector/dev-mode contract guard passed with no violations.'
