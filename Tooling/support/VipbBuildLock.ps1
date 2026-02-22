Set-StrictMode -Version Latest

function Get-VipbBuildLockRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $lockRootBase = if (-not [string]::IsNullOrWhiteSpace($env:LVIE_LOCK_ROOT)) {
        $env:LVIE_LOCK_ROOT
    } elseif (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
        $env:RUNNER_TEMP
    } elseif (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
        $env:TEMP
    } else {
        Join-Path -Path $RepoRoot -ChildPath 'builds\locks'
    }

    $lockRoot = Join-Path -Path $lockRootBase -ChildPath 'vipb-build-locks'
    New-Item -ItemType Directory -Path $lockRoot -Force | Out-Null
    return [System.IO.Path]::GetFullPath($lockRoot)
}

function Get-VipbBuildLockName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VipbPath
    )

    $normalizedPath = [System.IO.Path]::GetFullPath($VipbPath).ToLowerInvariant()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedPath)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash($bytes)
    }
    finally {
        $sha256.Dispose()
    }

    $hashHex = [BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 16).ToLowerInvariant()
    return "vipb-$hashHex.lock"
}

function Get-VipbBuildLockMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LockPath
    )

    $metaPath = Join-Path -Path $LockPath -ChildPath 'lock.json'
    if (-not (Test-Path -Path $metaPath)) {
        return $null
    }

    try {
        return Get-Content -Path $metaPath -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning ("Failed to parse lock metadata at '{0}': {1}" -f $metaPath, $_.Exception.Message)
        return $null
    }
}

function Acquire-VipbBuildLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LockRoot,
        [Parameter(Mandatory = $true)]
        [string]$VipbPath,
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 7200)]
        [int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 86400)]
        [int]$StaleSeconds,
        [ValidateRange(1, 30)]
        [int]$PollIntervalSeconds = 5
    )

    $lockName = Get-VipbBuildLockName -VipbPath $VipbPath
    $lockPath = Join-Path -Path $LockRoot -ChildPath $lockName
    $metaPath = Join-Path -Path $lockPath -ChildPath 'lock.json'
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $hostName = [Environment]::MachineName
    $pidValue = $PID

    while ((Get-Date) -lt $deadline) {
        try {
            New-Item -Path $lockPath -ItemType Directory -ErrorAction Stop | Out-Null
            $metadata = [PSCustomObject]@{
                acquired_at_utc = [DateTime]::UtcNow.ToString('o')
                machine         = $hostName
                pid             = $pidValue
                vipb_path       = $VipbPath
            }
            $metadata | ConvertTo-Json -Depth 5 | Set-Content -Path $metaPath -Encoding UTF8
            Write-Host ("Acquired VIPB build lock: {0}" -f $lockPath)
            return $lockPath
        }
        catch {
            if (-not (Test-Path -Path $lockPath)) {
                Start-Sleep -Seconds ([Math]::Min(2, $PollIntervalSeconds))
                continue
            }

            $metadata = Get-VipbBuildLockMetadata -LockPath $lockPath
            $isStale = $false
            if ($null -ne $metadata) {
                $acquiredAtUtc = $null
                $acquiredValue = $metadata.acquired_at_utc
                if ($acquiredValue -is [DateTime]) {
                    $acquiredAtUtc = [DateTime]$acquiredValue
                    if ($acquiredAtUtc.Kind -eq [DateTimeKind]::Unspecified) {
                        $acquiredAtUtc = [DateTime]::SpecifyKind($acquiredAtUtc, [DateTimeKind]::Utc)
                    }
                }
                elseif (-not [string]::IsNullOrWhiteSpace([string]$acquiredValue)) {
                    try {
                        $acquiredAtUtc = [DateTimeOffset]::Parse(
                            [string]$acquiredValue,
                            [System.Globalization.CultureInfo]::InvariantCulture,
                            [System.Globalization.DateTimeStyles]::AssumeUniversal
                        ).UtcDateTime
                    }
                    catch {
                        Write-Warning ("Invalid lock timestamp for '{0}': {1}" -f $lockPath, $_.Exception.Message)
                    }
                }

                if ($null -eq $acquiredAtUtc) {
                    # Unparseable timestamps should not block progress forever.
                    $isStale = $true
                }
                else {
                    $ageSeconds = ([DateTime]::UtcNow - $acquiredAtUtc).TotalSeconds
                    if ($ageSeconds -ge $StaleSeconds) {
                        $isStale = $true
                    }
                }
            }

            if ($isStale) {
                Write-Warning ("Removing stale VIPB build lock '{0}'." -f $lockPath)
                try {
                    Remove-Item -Path $lockPath -Recurse -Force -ErrorAction Stop
                    continue
                }
                catch {
                    Write-Warning ("Failed to remove stale VIPB build lock '{0}': {1}" -f $lockPath, $_.Exception.Message)
                }
            }
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }

    $owner = Get-VipbBuildLockMetadata -LockPath $lockPath
    $ownerSummary = if ($null -eq $owner) {
        'unknown owner'
    }
    else {
        "{0} (pid={1}, acquired={2})" -f $owner.machine, $owner.pid, $owner.acquired_at_utc
    }

    throw "Timed out waiting for VIPB build lock '$lockPath' after $TimeoutSeconds seconds. Current owner: $ownerSummary."
}

function Release-VipbBuildLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LockPath
    )

    if (-not (Test-Path -Path $LockPath)) {
        return
    }

    try {
        Remove-Item -Path $LockPath -Recurse -Force -ErrorAction Stop
        Write-Host ("Released VIPB build lock: {0}" -f $LockPath)
    }
    catch {
        Write-Warning ("Failed to release VIPB build lock '{0}': {1}" -f $LockPath, $_.Exception.Message)
    }
}
