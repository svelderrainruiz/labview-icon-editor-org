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
        $script:runnerBootstrap = Get-Content -Path $script:runnerBootstrapPath -Raw
        $script:jobSetup = Get-Content -Path $script:jobSetupPath -Raw
    }

    It "builds and invokes runner-cli in place via dotnet" {
        $script:runnerBootstrap | Should -Match 'dotnet build \$runnerCliProject --configuration Release /p:SelfContained=false /p:UseAppHost=false'
        $script:runnerBootstrap | Should -Match 'runner-cli\.dll'
        $script:runnerBootstrap | Should -Match '& dotnet \$runnerCliDll init-contract'
        $script:runnerBootstrap | Should -Match '& dotnet \$runnerCliDll emit-env'
        $script:runnerBootstrap | Should -Not -Match 'RUNNER_TEMP.*runner-cli\.exe'
    }

    It "disables runner-cli artifact download by default in job setup" {
        $script:jobSetup | Should -Match '(?ms)download_runner_cli:\s*.*?default:\s*''false'''
    }
}
