Describe "VIPC remediation summary contract" {
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
        $script:ciWorkflowPath = Join-Path $script:repoRoot ".github/workflows/ci.yml"
    }

    It "keeps ci.yml present for VIPC remediation contract checks" {
        Test-Path -Path $script:ciWorkflowPath | Should -BeTrue
    }

    It "writes step summary only for remediation paths in both bitness lanes" {
        $content = Get-Content -Path $script:ciWorkflowPath -Raw

        $content | Should -Match "name:\s+VIPC remediation summary \(LV x64\)"
        $content | Should -Match "name:\s+VIPC remediation summary \(LV x86\)"
        $content | Should -Match "if:\s+\$\{\{\s*steps\.vipc_audit\.outputs\.vipc_mismatch_count != '0'\s*\}\}"
        $content | Should -Match "### VIPC Remediation \(LV x64\)"
        $content | Should -Match "### VIPC Remediation \(LV x86\)"
        $content | Should -Match '\$env:GITHUB_STEP_SUMMARY'
    }

    It "enforces re-audit after remediation and audit-first mismatch capture" {
        $content = Get-Content -Path $script:ciWorkflowPath -Raw

        $content | Should -Match "name:\s+Re-audit VIPC apply \(LV x64\)"
        $content | Should -Match "name:\s+Re-audit VIPC apply \(LV x86\)"
        $content | Should -Match "'--fail-on-mismatch', 'false'"
        $content | Should -Match "vipc-audit-post-64\.json"
        $content | Should -Match "vipc-audit-post-32\.json"
    }
}
