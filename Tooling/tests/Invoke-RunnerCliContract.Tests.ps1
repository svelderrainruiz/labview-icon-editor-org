#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Invoke-RunnerCli contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:invokerPath = Join-Path $script:repoRoot 'Tooling\Invoke-RunnerCli.ps1'
    }

    It 'exists' {
        Test-Path -LiteralPath $script:invokerPath -PathType Leaf | Should -BeTrue
    }

    It 'enforces in-place non-apphost build flags' {
        $content = Get-Content -LiteralPath $script:invokerPath -Raw
        $content | Should -Match '-p:SelfContained=false'
        $content | Should -Match '-p:UseAppHost=false'
    }
}
