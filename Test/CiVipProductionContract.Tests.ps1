Describe "CI VIP production contract" {
    BeforeAll {
        function Find-RepoRoot {
            param([string]$StartPath)

            $dir = $StartPath
            while ($dir -and (Test-Path -Path $dir)) {
                if ((Test-Path (Join-Path $dir ".git")) -or (Test-Path (Join-Path $dir ".lvversion"))) {
                    return (Resolve-Path -Path $dir).Path
                }

                $parent = Split-Path -Parent $dir
                if ($parent -eq $dir) {
                    break
                }
                $dir = $parent
            }

            throw "Unable to locate repository root from '$StartPath'."
        }

        $script:repoRoot = Find-RepoRoot -StartPath $PSScriptRoot
        $ciCandidates = @(
            (Join-Path $script:repoRoot '.github\workflows\ci.yml'),
            (Join-Path $script:repoRoot '.github\workflows\ci-composite.yml')
        )
        $script:ciWorkflowPath = @($ciCandidates | Where-Object { Test-Path -Path $_ } | Select-Object -First 1)[0]
        if ([string]::IsNullOrWhiteSpace($script:ciWorkflowPath)) {
            throw 'Unable to locate CI workflow file (ci.yml or ci-composite.yml).'
        }
        $script:watchdogWorkflowPath = Join-Path $script:repoRoot '.github\workflows\vip-production-watchdog.yml'
        $script:guaranteeScriptPath = Join-Path $script:repoRoot 'Tooling\Assert-DevelopVipGuarantee.ps1'
        $script:viAnalyzerParityScriptPath = Join-Path $script:repoRoot 'Tooling\Assert-ViAnalyzerBitnessParity.ps1'

        $script:ciWorkflow = Get-Content -Path $script:ciWorkflowPath -Raw
        $script:watchdogWorkflow = Get-Content -Path $script:watchdogWorkflowPath -Raw
    }

    It "keeps guarantee script syntax valid" {
        $null = $tokens = $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:guaranteeScriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It "uses CI Pipeline workflow name and cancellation contract" {
        $script:ciWorkflow | Should -Match '(?m)^name:\s*CI Pipeline\s*$'
        $script:ciWorkflow | Should -Match '(?m)^\s*cancel-in-progress:\s*\$\{\{.*\}\}\s*$'
    }

    It "defines prerelease publish and pipeline contract jobs" {
        $script:ciWorkflow | Should -Match '(?m)^  publish-prerelease:\s*$'
        $script:ciWorkflow | Should -Match '(?m)^  pipeline-contract:\s*$'
    }

    It "enforces VI Analyzer bitness parity gate before source tests" {
        $script:ciWorkflow | Should -Match '(?m)^  vi-analyzer:\s*$'
        $script:ciWorkflow | Should -Match '(?m)^  vi-analyzer-bitness-parity:\s*$'
        $script:ciWorkflow | Should -Match 'name:\s*VI Analyzer Bitness Parity'
        $script:ciWorkflow | Should -Match 'Tooling/Assert-ViAnalyzerBitnessParity\.ps1'
        $script:ciWorkflow | Should -Match 'vi-analyzer-status-Windows-64-bit'
        $script:ciWorkflow | Should -Match 'vi-analyzer-status-Windows-32-bit'
        $script:ciWorkflow | Should -Match 'vi-analyzer-bitness-parity-status'
        $script:ciWorkflow | Should -Match '(?m)^\s*needs:\s*\[run-metadata,\s*prerelease-context,\s*version-gate,\s*apply-deps-64,\s*apply-deps-32,\s*vi-analyzer,\s*vi-analyzer-bitness-parity\]\s*$'
        $script:ciWorkflow | Should -Match '(?ms)\$requiredFullValidation\s*=\s*@\(\s*.*?''vi-analyzer''\s*,\s*''vi-analyzer-bitness-parity'''
        $script:ciWorkflow | Should -Match '(?ms)''release-priority''\s*=\s*@\(\$requiredCommon\s*\+\s*@\(''vi-analyzer'',\s*''vi-analyzer-bitness-parity''\)\)'
    }

    It "keeps VI Analyzer parity assertion script syntax valid" {
        (Test-Path -Path $script:viAnalyzerParityScriptPath) | Should -BeTrue
        $null = $tokens = $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:viAnalyzerParityScriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It "defines watchdog workflow contract with schedule, dispatch, and issue escalation" {
        $script:watchdogWorkflow | Should -Match '(?m)^name:\s*VIP Production Watchdog\s*$'
        $script:watchdogWorkflow | Should -Match '(?m)^\s*schedule:\s*$'
        $script:watchdogWorkflow | Should -Match "(?m)^\s*workflow_dispatch:\s*$"
        $script:watchdogWorkflow | Should -Match 'Tooling/Assert-DevelopVipGuarantee\.ps1'
        $script:watchdogWorkflow | Should -Match 'Open or update watchdog issue'
        $script:watchdogWorkflow | Should -Match 'vip-production-watchdog-report'
    }
}
