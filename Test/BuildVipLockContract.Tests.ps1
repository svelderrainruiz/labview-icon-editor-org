Describe "Build VIP lock contract" {
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
        $script:buildVipScript = Join-Path $script:repoRoot ".github/actions/build-vip/build_vip.ps1"
        $script:buildVipAction = Join-Path $script:repoRoot ".github/actions/build-vip/action.yml"
    }

    It "keeps build_vip syntax valid" {
        $null = $tokens = $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:buildVipScript, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It "sources the shared VIPB lock support script" {
        $content = Get-Content -Path $script:buildVipScript -Raw
        $content | Should -Match "Tooling\\support\\VipbBuildLock\.ps1"
        $content | Should -Match "New-VipbBuildLockLease"
        $content | Should -Match "Remove-VipbBuildLockLease"

        $sourceIndex = $content.IndexOf(". `$vipbLockSupportScript")
        $acquireIndex = $content.IndexOf("New-VipbBuildLockLease")
        $sourceIndex | Should -BeGreaterThan -1
        $acquireIndex | Should -BeGreaterThan -1
        $sourceIndex | Should -BeLessThan $acquireIndex
    }

    It "exposes lock controls in the composite action inputs and invocation" {
        $actionContent = Get-Content -Path $script:buildVipAction -Raw
        $actionContent | Should -Match "vipb_build_lock_timeout_seconds"
        $actionContent | Should -Match "vipb_build_lock_stale_seconds"
        $actionContent | Should -Match "-VipbBuildLockTimeoutSeconds"
        $actionContent | Should -Match "-VipbBuildLockStaleSeconds"
    }
}
