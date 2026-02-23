#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Invoke-RunnerCli contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:invokerPath = Join-Path $script:repoRoot 'Tooling\Invoke-RunnerCli.ps1'
        $script:missingInProjectActionPath = Join-Path $script:repoRoot '.github\actions\missing-in-project\action.yml'
        $script:pylaviValidateActionPath = Join-Path $script:repoRoot '.github\actions\pylavi-validate\action.yml'
    }

    It 'exists' {
        Test-Path -LiteralPath $script:invokerPath -PathType Leaf | Should -BeTrue
    }

    It 'enforces in-place non-apphost build flags' {
        $content = Get-Content -LiteralPath $script:invokerPath -Raw
        $content | Should -Match '-p:SelfContained=false'
        $content | Should -Match '-p:UseAppHost=false'
    }

    It 'missing-in-project action routes runner-cli args through -RunnerCliArgs' {
        $content = Get-Content -LiteralPath $script:missingInProjectActionPath -Raw
        $content | Should -Match '-RunnerCliArgs \$runnerCliArgs'
        $content | Should -Not -Match '--\s+@runnerCliArgs'
    }

    It 'pylavi-validate action routes runner-cli args through -RunnerCliArgs' {
        $content = Get-Content -LiteralPath $script:pylaviValidateActionPath -Raw
        $content | Should -Match '-RunnerCliArgs \$scanArgs'
        $content | Should -Match '-RunnerCliArgs \$summaryArgs'
        $content | Should -Not -Match '--\s+@scanArgs'
        $content | Should -Not -Match '--\s+@summaryArgs'
    }
}
