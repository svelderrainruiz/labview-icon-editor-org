#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'CI VIP production contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:ciWorkflowPath = Join-Path $script:repoRoot '.github\workflows\ci.yml'
        $script:parityWorkflowPath = Join-Path $script:repoRoot '.github\workflows\labview-parity.yml'
        $script:watchdogWorkflowPath = Join-Path $script:repoRoot '.github\workflows\vip-production-watchdog.yml'
        $script:watchdogScriptPath = Join-Path $script:repoRoot 'Tooling\Assert-DevelopVipGuarantee.ps1'
        $script:ciContent = Get-Content -Path $script:ciWorkflowPath -Raw
        $script:parityContent = Get-Content -Path $script:parityWorkflowPath -Raw
        $script:watchdogContent = Get-Content -Path $script:watchdogWorkflowPath -Raw
        $script:watchdogScriptContent = Get-Content -Path $script:watchdogScriptPath -Raw
    }

    It 'keeps ci.yml concurrency cancellation enabled for superseded develop pushes' {
        $script:ciContent | Should -Match '(?ms)^concurrency:\s*.*?cancel-in-progress:\s*\$\{\{\s*github\.event_name == ''pull_request'' \|\| \(github\.event_name == ''push'' && github\.ref == ''refs/heads/develop''\)\s*\}\}'
    }

    It 'requires auto publish intent for upstream develop pushes' {
        $script:ciContent | Should -Match 'isCanonicalRepo = context\.repo\.owner === ''LabVIEW-Community-CI-CD'' && context\.repo\.repo === ''labview-icon-editor'''
        $script:ciContent | Should -Match 'auto-required-upstream-develop-push-merged-pr-merge-commit'
        $script:ciContent | Should -Match 'auto-required-upstream-develop-push-non-merge-commit'
    }

    It 'enforces VIPM port remediation before VIPC apply on both bitness lanes' {
        $script:ciContent | Should -Match 'Audit VIPM port alignment \(LV x64\)'
        $script:ciContent | Should -Match 'Audit VIPM port alignment \(LV x86\)'
        $script:ciContent | Should -Match 'Tooling\\Assert-VipmPortAlignment\.ps1'
        $script:ciContent | Should -Match '-LabVIEWBitness 64'
        $script:ciContent | Should -Match '-LabVIEWBitness 32'
        $script:ciContent | Should -Match 'VIPM remediation summary \(LV x64\)'
        $script:ciContent | Should -Match 'VIPM remediation summary \(LV x86\)'
    }

    It 'defines VIP Production Contract job and attestation artifact on upstream develop pushes' {
        $script:ciContent | Should -Match '(?ms)^  vip-production-contract:\s*$'
        $script:ciContent | Should -Match 'name:\s*VIP Production Contract'
        $script:ciContent | Should -Match 'github\.repository == ''LabVIEW-Community-CI-CD/labview-icon-editor'''
        $script:ciContent | Should -Match 'needs:\s*\[\s*run-metadata,\s*prerelease-context,\s*build-vip,\s*publish-prerelease,\s*pipeline-contract,\s*version\s*\]'
        $script:ciContent | Should -Match 'vip-production-attestation'
        $script:ciContent | Should -Match 'prerelease-publish-status'
    }

    It 'wires VIP Production Contract into required-context for canonical develop pushes' {
        $script:ciContent | Should -Match '(?ms)^  required-context:\s*.*?\n\s*-\s*vip-production-contract\s*$'
        $script:ciContent | Should -Match 'isCanonicalDevelopPush'
        $script:ciContent | Should -Match 'vip-production-contract:\$vipProductionResult'
    }

    It 'adds labview-parity concurrency with develop push cancellation' {
        $script:parityContent | Should -Match '(?ms)^concurrency:\s*.*?labview-parity-\$\{\{\s*github\.repository\s*\}\}'
        $script:parityContent | Should -Match 'cancel-in-progress:\s*\$\{\{\s*github\.event_name == ''push'' && github\.ref == ''refs/heads/develop''\s*\}\}'
    }

    It 'defines scheduled and manual VIP production watchdog workflow' {
        $script:watchdogContent | Should -Match '(?ms)^on:\s*.*?schedule:'
        $script:watchdogContent | Should -Match '(?ms)^on:\s*.*?workflow_dispatch:'
        $script:watchdogContent | Should -Match 'Assert-DevelopVipGuarantee\.ps1'
        $script:watchdogContent | Should -Match 'Open or update watchdog tracking issue'
    }

    It 'keeps watchdog script syntax valid and attestation artifact contract check' {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script:watchdogScriptPath, [ref]$tokens, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            throw ("Assert-DevelopVipGuarantee.ps1 parse failed: {0}" -f $errors[0].Message)
        }

        $script:watchdogScriptContent | Should -Match 'vip-production-attestation'
        $script:watchdogScriptContent | Should -Match 'actions/workflows/.*/runs\?branch='
    }
}
