Describe "VipbBuildLock support module" {
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
        $script:supportPath = Join-Path $script:repoRoot "Tooling/support/VipbBuildLock.ps1"
        $script:tempRoot = Join-Path $script:repoRoot "Test/tmp/vipb-lock-tests"
        New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
        . $script:supportPath
    }

    AfterAll {
        if (Test-Path $script:tempRoot) {
            Remove-Item -Path $script:tempRoot -Recurse -Force
        }
    }

    It "parses without syntax errors" {
        $null = $tokens = $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:supportPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It "resolves lock root with LVIE_LOCK_ROOT precedence" {
        $originalLvieLock = $env:LVIE_LOCK_ROOT
        $originalRunnerTemp = $env:RUNNER_TEMP
        $originalTemp = $env:TEMP
        try {
            $lvieRoot = Join-Path $script:tempRoot "lvie-lock-root"
            $runnerTemp = Join-Path $script:tempRoot "runner-temp-root"
            $tempRoot = Join-Path $script:tempRoot "temp-root"
            New-Item -ItemType Directory -Path $lvieRoot -Force | Out-Null
            New-Item -ItemType Directory -Path $runnerTemp -Force | Out-Null
            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

            $env:LVIE_LOCK_ROOT = $lvieRoot
            $env:RUNNER_TEMP = $runnerTemp
            $env:TEMP = $tempRoot

            $resolved = Get-VipbBuildLockRoot -RepoRoot $script:repoRoot
            $expected = Join-Path $lvieRoot "vipb-build-locks"
            [System.IO.Path]::GetFullPath($resolved) | Should -Be ([System.IO.Path]::GetFullPath($expected))
        }
        finally {
            $env:LVIE_LOCK_ROOT = $originalLvieLock
            $env:RUNNER_TEMP = $originalRunnerTemp
            $env:TEMP = $originalTemp
        }
    }

    It "acquires and releases a per-vipb lock" {
        $lockRoot = Join-Path $script:tempRoot "acquire-release"
        New-Item -ItemType Directory -Path $lockRoot -Force | Out-Null
        $vipbPath = Join-Path $script:tempRoot "fixture.vipb"
        Set-Content -Path $vipbPath -Value "<vipb/>" -NoNewline

        $lockPath = New-VipbBuildLockLease -LockRoot $lockRoot -VipbPath $vipbPath -TimeoutSeconds 5 -StaleSeconds 60 -PollIntervalSeconds 1
        try {
            Test-Path $lockPath | Should -BeTrue
            Test-Path (Join-Path $lockPath "lock.json") | Should -BeTrue
        }
        finally {
            Remove-VipbBuildLockLease -LockPath $lockPath
        }

        Test-Path $lockPath | Should -BeFalse
    }

    It "recovers stale lock folders" {
        $lockRoot = Join-Path $script:tempRoot "stale-recovery"
        New-Item -ItemType Directory -Path $lockRoot -Force | Out-Null
        $vipbPath = Join-Path $script:tempRoot "stale.vipb"
        Set-Content -Path $vipbPath -Value "<vipb/>" -NoNewline

        $lockName = Get-VipbBuildLockName -VipbPath $vipbPath
        $lockPath = Join-Path $lockRoot $lockName
        New-Item -ItemType Directory -Path $lockPath -Force | Out-Null

        $staleMeta = [PSCustomObject]@{
            acquired_at_utc = ([DateTime]::UtcNow.AddHours(-2)).ToString('o')
            machine         = 'stale-owner'
            pid             = 1
            vipb_path       = $vipbPath
        }
        $staleMeta | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $lockPath "lock.json") -Encoding UTF8

        $acquiredPath = New-VipbBuildLockLease -LockRoot $lockRoot -VipbPath $vipbPath -TimeoutSeconds 5 -StaleSeconds 10 -PollIntervalSeconds 1
        try {
            $acquiredPath | Should -Be $lockPath
            Test-Path (Join-Path $lockPath "lock.json") | Should -BeTrue
        }
        finally {
            Remove-VipbBuildLockLease -LockPath $acquiredPath
        }
    }

    It "fails fast on non-stale contention timeout" {
        $lockRoot = Join-Path $script:tempRoot "timeout-contention"
        New-Item -ItemType Directory -Path $lockRoot -Force | Out-Null
        $vipbPath = Join-Path $script:tempRoot "timeout.vipb"
        Set-Content -Path $vipbPath -Value "<vipb/>" -NoNewline

        $lockName = Get-VipbBuildLockName -VipbPath $vipbPath
        $lockPath = Join-Path $lockRoot $lockName
        New-Item -ItemType Directory -Path $lockPath -Force | Out-Null
        $activeMeta = [PSCustomObject]@{
            acquired_at_utc = ([DateTime]::UtcNow).ToString('o')
            machine         = 'active-owner'
            pid             = 999
            vipb_path       = $vipbPath
        }
        $activeMeta | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $lockPath "lock.json") -Encoding UTF8

        {
            New-VipbBuildLockLease -LockRoot $lockRoot -VipbPath $vipbPath -TimeoutSeconds 2 -StaleSeconds 3600 -PollIntervalSeconds 1
        } | Should -Throw "*Timed out waiting for VIPB build lock*"

        Remove-Item -Path $lockPath -Recurse -Force
    }
}
