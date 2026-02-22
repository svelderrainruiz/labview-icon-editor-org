#Requires -Version 7.0
<#
.SYNOPSIS
    Validates that VIPM target ports match LabVIEW.ini VI Server ports.

.DESCRIPTION
    Reads VIPM target configuration from Settings.ini and compares each target's
    configured VIPM port to server.tcp.port in the matching LabVIEW.ini.
#>

function Get-VipmSettingsPath {
    [CmdletBinding()]
    param(
        [string]$ProgramDataPath = $env:ProgramData
    )

    if ([string]::IsNullOrWhiteSpace($ProgramDataPath)) {
        throw 'ProgramData path is not available.'
    }

    $candidate = Join-Path -Path $ProgramDataPath -ChildPath 'JKI\VIPM\Settings.ini'
    if (-not (Test-Path -Path $candidate)) {
        throw "VIPM Settings.ini not found at '$candidate'."
    }

    return (Resolve-Path -Path $candidate).Path
}

function Convert-VipmPathToWindows {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    if ($Path -match '^[A-Za-z]:\\') {
        return $Path
    }

    if ($Path -match '^/([A-Za-z])/(.*)$') {
        $drive = $matches[1].ToUpperInvariant()
        $rest = $matches[2] -replace '/', '\'
        return ('{0}:\{1}' -f $drive, $rest)
    }

    return ($Path -replace '/', '\')
}

function Get-IndexedIniValues {
    [CmdletBinding()]
    param(
        [string[]]$Lines,
        [string]$KeyPrefix
    )

    $map = @{}
    $pattern = '^\s*{0}\s+(\d+)="(.*)"\s*$' -f [regex]::Escape($KeyPrefix)
    foreach ($line in $Lines) {
        $match = [regex]::Match($line, $pattern)
        if ($match.Success) {
            $index = [int]$match.Groups[1].Value
            $value = $match.Groups[2].Value
            $map[$index] = $value
        }
    }

    return $map
}

function Get-VipmPortsFromSettingsLines {
    [CmdletBinding()]
    param(
        [string[]]$Lines
    )

    $line = $Lines | Where-Object { $_ -match '^\s*Ports="<size\(s\)=\d+>.*"\s*$' } | Select-Object -First 1
    if (-not $line) {
        throw 'Ports entry not found in VIPM Settings.ini.'
    }

    $match = [regex]::Match($line, '^\s*Ports="<size\(s\)=(\d+)>\s*(.*)"\s*$')
    if (-not $match.Success) {
        throw "Unable to parse VIPM Ports entry: $line"
    }

    $declaredSize = [int]$match.Groups[1].Value
    $portsRaw = $match.Groups[2].Value.Trim()
    $ports = @()
    if (-not [string]::IsNullOrWhiteSpace($portsRaw)) {
        $ports = $portsRaw -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    if ($declaredSize -ne $ports.Count) {
        throw "VIPM Ports size mismatch: declared $declaredSize, actual $($ports.Count)."
    }

    return [pscustomobject]@{
        DeclaredSize = $declaredSize
        Ports        = @($ports)
        Line         = $line
    }
}

function Get-LabVIEWYearFromVipmVersion {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Version
    )

    if ([string]::IsNullOrWhiteSpace($Version)) {
        return $null
    }

    $match = [regex]::Match($Version, '^(\d{1,4})')
    if (-not $match.Success) {
        return $null
    }

    $major = [int]$match.Groups[1].Value
    if ($major -ge 2000) {
        return $major
    }

    if ($major -ge 0 -and $major -lt 100) {
        return (2000 + $major)
    }

    return $null
}

function Resolve-VipmTargetBitness {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Version,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Location
    )

    if ($Version -match '\(64-bit\)') { return '64' }
    if ($Version -match '\(32-bit\)') { return '32' }
    if ($Location -match 'Program Files \(x86\)') { return '32' }
    if ($Location -match 'Program Files\\') { return '64' }
    if ($Location -match '/Program Files \(x86\)/') { return '32' }
    if ($Location -match '/Program Files/') { return '64' }
    return 'unknown'
}

function Get-LabVIEWServerPortFromIni {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LabVIEWIniPath
    )

    if (-not (Test-Path -Path $LabVIEWIniPath)) {
        return $null
    }

    $line = Select-String -Path $LabVIEWIniPath -Pattern '^\s*server\.tcp\.port\s*=\s*(\d+)\s*$' -CaseSensitive:$false | Select-Object -First 1
    if (-not $line) {
        return $null
    }

    $match = [regex]::Match($line.Line, '^\s*server\.tcp\.port\s*=\s*(\d+)\s*$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }

    return [int]$match.Groups[1].Value
}

function Get-VipmTargetsFromSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SettingsPath
    )

    $resolvedSettingsPath = (Resolve-Path -Path $SettingsPath -ErrorAction Stop).Path
    $lines = Get-Content -Path $resolvedSettingsPath

    $versions = Get-IndexedIniValues -Lines $lines -KeyPrefix 'Versions'
    $locations = Get-IndexedIniValues -Lines $lines -KeyPrefix 'Locations'
    $disabledMap = Get-IndexedIniValues -Lines $lines -KeyPrefix 'Disabled'
    $portsInfo = Get-VipmPortsFromSettingsLines -Lines $lines

    $allIndexes = @()
    $allIndexes += $versions.Keys
    $allIndexes += $locations.Keys
    $ports = @($portsInfo.Ports)
    if ($ports.Count -gt 0) {
        $allIndexes += (0..($ports.Count - 1))
    }
    $allIndexes = $allIndexes | Sort-Object -Unique

    $targets = @()
    foreach ($index in $allIndexes) {
        $version = if ($versions.ContainsKey($index)) { $versions[$index] } else { $null }
        $locationRaw = if ($locations.ContainsKey($index)) { $locations[$index] } else { $null }
        $location = Convert-VipmPathToWindows -Path $locationRaw
        $vipmPort = $null
        if ($index -lt $ports.Count) {
            $portValue = $ports[$index]
            if ($portValue -match '^\d+$') {
                $vipmPort = [int]$portValue
            }
        }

        $labviewExePath = if ([string]::IsNullOrWhiteSpace($location)) { $null } else { $location }
        $labviewIniPath = if ([string]::IsNullOrWhiteSpace($labviewExePath)) { $null } else { Join-Path -Path (Split-Path -Path $labviewExePath -Parent) -ChildPath 'LabVIEW.ini' }
        $disabledRaw = if ($disabledMap.ContainsKey($index)) { $disabledMap[$index] } else { 'FALSE' }
        $isDisabled = $disabledRaw.Trim().ToUpperInvariant() -eq 'TRUE'

        $targets += [pscustomobject]@{
            Index          = $index
            Version        = $version
            Year           = Get-LabVIEWYearFromVipmVersion -Version $version
            Bitness        = Resolve-VipmTargetBitness -Version $version -Location $location
            Location       = $location
            LabVIEWExePath = $labviewExePath
            LabVIEWIniPath = $labviewIniPath
            VipmPort       = $vipmPort
            Disabled       = $isDisabled
        }
    }

    return $targets
}

function Test-VipmTargetPortAlignment {
    [CmdletBinding()]
    param(
        [string]$SettingsPath,

        [ValidateRange(2000, 2100)]
        [int]$LabVIEWVersion,

        [ValidateSet('32', '64', 'both')]
        [string]$Bitness = 'both',

        [switch]$IncludeDisabled
    )

    $resolvedSettingsPath = if ([string]::IsNullOrWhiteSpace($SettingsPath)) {
        Get-VipmSettingsPath
    } else {
        (Resolve-Path -Path $SettingsPath -ErrorAction Stop).Path
    }

    $targets = Get-VipmTargetsFromSettings -SettingsPath $resolvedSettingsPath

    if ($PSBoundParameters.ContainsKey('LabVIEWVersion')) {
        $targets = $targets | Where-Object { $_.Year -eq $LabVIEWVersion }
    }

    if ($Bitness -ne 'both') {
        $targets = $targets | Where-Object { $_.Bitness -eq $Bitness }
    }

    if (-not $IncludeDisabled.IsPresent) {
        $targets = $targets | Where-Object { -not $_.Disabled }
    }

    $warnings = @()
    $mismatches = @()

    foreach ($target in $targets) {
        if ([string]::IsNullOrWhiteSpace($target.LabVIEWIniPath)) {
            $warnings += [pscustomobject]@{
                reason = 'missing_labview_ini_path'
                index = $target.Index
                version = $target.Version
                bitness = $target.Bitness
            }
            continue
        }

        if (-not (Test-Path -Path $target.LabVIEWIniPath)) {
            $warnings += [pscustomobject]@{
                reason = 'labview_ini_not_found'
                index = $target.Index
                version = $target.Version
                bitness = $target.Bitness
                labview_ini_path = $target.LabVIEWIniPath
            }
            continue
        }

        $labviewPort = Get-LabVIEWServerPortFromIni -LabVIEWIniPath $target.LabVIEWIniPath
        if ($null -eq $labviewPort) {
            $mismatches += [pscustomobject]@{
                reason = 'labview_ini_missing_server_port'
                index = $target.Index
                version = $target.Version
                bitness = $target.Bitness
                vipm_port = $target.VipmPort
                labview_port = $null
                labview_ini_path = $target.LabVIEWIniPath
            }
            continue
        }

        if ($null -eq $target.VipmPort) {
            $mismatches += [pscustomobject]@{
                reason = 'vipm_missing_port'
                index = $target.Index
                version = $target.Version
                bitness = $target.Bitness
                vipm_port = $null
                labview_port = $labviewPort
                labview_ini_path = $target.LabVIEWIniPath
            }
            continue
        }

        if ($target.VipmPort -ne $labviewPort) {
            $mismatches += [pscustomobject]@{
                reason = 'port_mismatch'
                index = $target.Index
                version = $target.Version
                bitness = $target.Bitness
                vipm_port = $target.VipmPort
                labview_port = $labviewPort
                labview_ini_path = $target.LabVIEWIniPath
            }
        }
    }

    return [pscustomobject]@{
        checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        settings_path = $resolvedSettingsPath
        evaluated_target_count = @($targets).Count
        mismatch_count = @($mismatches).Count
        warning_count = @($warnings).Count
        passed = (@($mismatches).Count -eq 0)
        mismatches = @($mismatches)
        warnings = @($warnings)
    }
}

function Repair-VipmTargetPortAlignment {
    [CmdletBinding()]
    param(
        [string]$SettingsPath,

        [ValidateRange(2000, 2100)]
        [int]$LabVIEWVersion,

        [ValidateSet('32', '64', 'both')]
        [string]$Bitness = 'both',

        [switch]$IncludeDisabled
    )

    $resolvedSettingsPath = if ([string]::IsNullOrWhiteSpace($SettingsPath)) {
        Get-VipmSettingsPath
    } else {
        (Resolve-Path -Path $SettingsPath -ErrorAction Stop).Path
    }

    $before = Test-VipmTargetPortAlignment -SettingsPath $resolvedSettingsPath -Bitness $Bitness -IncludeDisabled:$IncludeDisabled
    if ($PSBoundParameters.ContainsKey('LabVIEWVersion')) {
        $before = Test-VipmTargetPortAlignment -SettingsPath $resolvedSettingsPath -LabVIEWVersion $LabVIEWVersion -Bitness $Bitness -IncludeDisabled:$IncludeDisabled
    }

    if ($before.mismatch_count -eq 0) {
        return [pscustomobject]@{
            changed = $false
            backup_path = $null
            before = $before
            after = $before
        }
    }

    $lines = Get-Content -Path $resolvedSettingsPath
    $portsInfo = Get-VipmPortsFromSettingsLines -Lines $lines
    $ports = @($portsInfo.Ports)

    $changedIndexes = @()
    foreach ($item in $before.mismatches) {
        if ($item.reason -ne 'port_mismatch') {
            continue
        }
        $idx = [int]$item.index
        if ($idx -lt 0 -or $idx -ge $ports.Count) {
            continue
        }
        $ports[$idx] = [string]$item.labview_port
        $changedIndexes += $idx
    }

    if (@($changedIndexes).Count -eq 0) {
        return [pscustomobject]@{
            changed = $false
            backup_path = $null
            before = $before
            after = $before
        }
    }

    $backupPath = '{0}.bak-{1}' -f $resolvedSettingsPath, (Get-Date -Format 'yyyyMMdd-HHmmss')
    Copy-Item -Path $resolvedSettingsPath -Destination $backupPath -Force

    $newPortsLine = 'Ports="<size(s)={0}> {1}"' -f $ports.Count, ($ports -join ' ')
    $portsLinePattern = '^\s*Ports="<size\(s\)=\d+>.*"\s*$'
    $updatedLines = @()
    $updated = $false
    foreach ($line in $lines) {
        if (-not $updated -and $line -match $portsLinePattern) {
            $updatedLines += $newPortsLine
            $updated = $true
        } else {
            $updatedLines += $line
        }
    }

    if (-not $updated) {
        throw 'Failed to update Ports entry in VIPM Settings.ini.'
    }

    Set-Content -Path $resolvedSettingsPath -Value $updatedLines -Encoding ascii

    $afterArgs = @{
        SettingsPath = $resolvedSettingsPath
        Bitness = $Bitness
        IncludeDisabled = $IncludeDisabled
    }
    if ($PSBoundParameters.ContainsKey('LabVIEWVersion')) {
        $afterArgs.LabVIEWVersion = $LabVIEWVersion
    }
    $after = Test-VipmTargetPortAlignment @afterArgs

    return [pscustomobject]@{
        changed = $true
        backup_path = $backupPath
        changed_indexes = @($changedIndexes | Sort-Object -Unique)
        before = $before
        after = $after
    }
}

function Assert-VipmTargetPortAlignment {
    [CmdletBinding()]
    param(
        [string]$SettingsPath,

        [ValidateRange(2000, 2100)]
        [int]$LabVIEWVersion,

        [ValidateSet('32', '64', 'both')]
        [string]$Bitness = 'both',

        [switch]$IncludeDisabled
    )

    $args = @{
        SettingsPath = $SettingsPath
        Bitness = $Bitness
        IncludeDisabled = $IncludeDisabled
    }
    if ($PSBoundParameters.ContainsKey('LabVIEWVersion')) {
        $args.LabVIEWVersion = $LabVIEWVersion
    }

    $result = Test-VipmTargetPortAlignment @args
    if (-not $result.passed) {
        $payload = $result | ConvertTo-Json -Depth 8
        throw "VIPM target port alignment check failed: $payload"
    }

    return $result
}
