<#
.SYNOPSIS
    Helper for invoking g-cli while capturing stdout and stderr separately.
#>

function ConvertTo-NativeProcessArgumentString {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Arguments
    )

    if ($Arguments.Count -eq 0) {
        return ''
    }

    $formatted = foreach ($argument in $Arguments) {
        if ($null -eq $argument) {
            '""'
            continue
        }

        $value = [string]$argument
        if ($value.Length -eq 0) {
            '""'
            continue
        }

        if ($value -notmatch '[\s"]') {
            $value
            continue
        }

        # Match CreateProcess argument parsing rules for quoted values.
        $builder = [System.Text.StringBuilder]::new()
        $null = $builder.Append('"')
        $backslashCount = 0

        foreach ($character in $value.ToCharArray()) {
            if ($character -eq '\') {
                $backslashCount++
                continue
            }

            if ($character -eq '"') {
                $null = $builder.Append('\', ($backslashCount * 2) + 1)
                $null = $builder.Append('"')
                $backslashCount = 0
                continue
            }

            if ($backslashCount -gt 0) {
                $null = $builder.Append('\', $backslashCount)
                $backslashCount = 0
            }

            $null = $builder.Append($character)
        }

        if ($backslashCount -gt 0) {
            $null = $builder.Append('\', $backslashCount * 2)
        }

        $null = $builder.Append('"')
        $builder.ToString()
    }

    return ($formatted -join ' ')
}

function Invoke-GCliCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 86400000)]
        [int]$TimeoutMs = 0
    )

    $stdoutLines = New-Object System.Collections.Generic.List[string]
    $stderrLines = New-Object System.Collections.Generic.List[string]

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $ExecutablePath
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true

    $hasArgumentList = $startInfo.PSObject.Properties.Match('ArgumentList').Count -gt 0
    if ($hasArgumentList) {
        foreach ($arg in $Arguments) {
            $null = $startInfo.ArgumentList.Add($arg)
        }
    } else {
        $startInfo.Arguments = ConvertTo-NativeProcessArgumentString -Arguments $Arguments
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo

    $null = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    $timedOut = $false
    if ($TimeoutMs -gt 0) {
        if (-not $process.WaitForExit($TimeoutMs)) {
            $timedOut = $true
            try {
                $killWithChildren = $process.GetType().GetMethod('Kill', [Type[]]@([bool]))
                if ($null -ne $killWithChildren) {
                    $process.Kill($true)
                } else {
                    $process.Kill()
                }
            } catch {
                Write-Verbose ("Failed to terminate g-cli process after timeout. {0}" -f $_.Exception.Message)
            }
        }
        $process.WaitForExit() | Out-Null
    } else {
        $process.WaitForExit() | Out-Null
    }

    $process.WaitForExit(2000) | Out-Null

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()

    if (-not [string]::IsNullOrEmpty($stdout)) {
        foreach ($line in ($stdout -split "`r?`n")) {
            if ($line -ne '') {
                $null = $stdoutLines.Add($line)
            }
        }
    }

    if (-not [string]::IsNullOrEmpty($stderr)) {
        foreach ($line in ($stderr -split "`r?`n")) {
            if ($line -ne '') {
                $null = $stderrLines.Add($line)
            }
        }
    }

    foreach ($line in $stdoutLines) {
        Write-Host $line
    }
    foreach ($line in $stderrLines) {
        Write-Host $line
    }

    return [pscustomobject]@{
        ExitCode    = $process.ExitCode
        OutputLines = $stdoutLines.ToArray()
        ErrorLines  = $stderrLines.ToArray()
        TimedOut    = $timedOut
    }
}
