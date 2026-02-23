#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'BuildProjectSpec sync exclusion contract' {
    BeforeAll {
        function Find-RepoRoot {
            param([string]$StartPath)

            $dir = $StartPath
            while ($dir -and (Test-Path -Path $dir)) {
                if ((Test-Path (Join-Path $dir '.git')) -or (Test-Path (Join-Path $dir '.lvversion'))) {
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
        $script:pplBuildScript = Join-Path $script:repoRoot '.github/actions/build-lvlibp/BuildProjectSpec.ps1'
    }

    It 'keeps BuildProjectSpec syntax valid' {
        $null = $tokens = $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:pplBuildScript, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'uses env-driven icon-editor sync exclusions without hardcoded LV2020 fallback paths' {
        $content = Get-Content -Path $script:pplBuildScript -Raw

        $content | Should -Match '\$excludeRaw = \$env:LVIE_ICON_EDITOR_SYNC_EXCLUDE_FILES'
        $content | Should -Not -Match 'NIIconEditor\\Class\\FakedArray\\Misc\\Process Template Graphics\.vi'
        $content | Should -Not -Match 'NIIconEditor\\Class\\Tools\\Fill\.vi'
    }
}
