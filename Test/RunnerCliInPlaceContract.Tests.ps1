Describe "Runner CLI in-place contract" {
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
        $script:runnerBootstrapPath = Join-Path $script:repoRoot '.github\actions\runner-bootstrap\action.yml'
        $script:jobSetupPath = Join-Path $script:repoRoot '.github\actions\lvie-job-setup\action.yml'
        $script:ciWorkflowPath = Join-Path $script:repoRoot '.github\workflows\ci.yml'
        $script:runnerBootstrap = Get-Content -Path $script:runnerBootstrapPath -Raw
        $script:jobSetup = Get-Content -Path $script:jobSetupPath -Raw
        $script:ciWorkflow = Get-Content -Path $script:ciWorkflowPath -Raw
    }

    It "builds and invokes runner-cli in place via dotnet" {
        $script:runnerBootstrap | Should -Match 'dotnet build \$runnerCliProject --configuration Release /p:SelfContained=false /p:UseAppHost=false'
        $script:runnerBootstrap | Should -Match '\$runnerLabel = if \(\[string\]::IsNullOrWhiteSpace\(\$env:LVIE_EXPECTED_RUNNER_LABEL\)\)'
        $script:runnerBootstrap | Should -Match '\$canonicalLabel = if \(\[string\]::IsNullOrWhiteSpace\(\$env:LVIE_CANONICAL_RUNNER_LABEL\)\)'
        $script:runnerBootstrap | Should -Match 'runner-cli\.dll'
        $script:runnerBootstrap | Should -Match '& dotnet \$runnerCliDll init-contract'
        $script:runnerBootstrap | Should -Match '--runner-label\s+\$runnerLabel'
        $script:runnerBootstrap | Should -Match '--canonical-label\s+\$canonicalLabel'
        $script:runnerBootstrap | Should -Match '& dotnet \$runnerCliDll emit-env'
        $script:runnerBootstrap | Should -Not -Match 'RUNNER_TEMP.*runner-cli\.exe'
    }

    It "disables runner-cli artifact download by default in job setup" {
        $script:jobSetup | Should -Match '(?ms)download_runner_cli:\s*.*?default:\s*''false'''
    }

    It "builds runner-cli in place for Build VI Package workflow step" {
        $script:ciWorkflow | Should -Match 'Build VI Package \(LV \${{\s*needs\.version-gate\.outputs\.raw\s*}}\s+x64\)'
        $script:ciWorkflow | Should -Match 'Using in-place runner-cli project at'
        $script:ciWorkflow | Should -Match '& dotnet run --project \$runnerCliProject --configuration Release -- @runnerCliArgs'
        $script:ciWorkflow | Should -Not -Match 'Using prebuilt runner-cli at'
    }

    It "names source-test jobs with .lvversion raw value and x64/x86 lane labels" {
        $script:ciWorkflow | Should -Match 'name:\s*Test Source Using LV \${{\s*needs\.version-gate\.outputs\.raw\s*}}\s+\${{\s*matrix\.bitness_label\s*}}'
        $script:ciWorkflow | Should -Match "bitness_label:\s*x64"
        $script:ciWorkflow | Should -Match "bitness_label:\s*x86"
        $script:ciWorkflow | Should -Match 'Test Source Using LV \${{\s*needs\.version-gate\.outputs\.raw\s*}}\s+\${{\s*matrix\.bitness_label\s*}}'
    }

    It "names packed-library jobs with .lvversion raw value and x64/x86 labels" {
        $script:ciWorkflow | Should -Match 'name:\s*Build Packed Library \(LV \${{\s*needs\.version-gate\.outputs\.raw\s*}}\s+x86\)'
        $script:ciWorkflow | Should -Match 'name:\s*Build Packed Library \(LV \${{\s*needs\.version-gate\.outputs\.raw\s*}}\s+x64\)'
        $script:ciWorkflow | Should -Match 'Build PPL \(LV \${{\s*needs\.version-gate\.outputs\.raw\s*}}\s+x86\)'
        $script:ciWorkflow | Should -Match 'Build PPL \(LV \${{\s*needs\.version-gate\.outputs\.raw\s*}}\s+x64\)'
    }
}
