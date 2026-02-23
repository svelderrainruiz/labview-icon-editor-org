#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Run-ViAnalyzer transient retry contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'Tooling\Run-ViAnalyzer.ps1'

        function script:Get-FunctionDefinitionText {
            param(
                [System.Management.Automation.Language.ScriptBlockAst]$Ast,
                [string]$FunctionName
            )

            $fn = @($Ast.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $FunctionName
                    }, $true))

            if ($fn.Count -ne 1) {
                throw ("Function definition '{0}' not found exactly once in {1}" -f $FunctionName, $script:scriptPath)
            }

            return $fn[0].Extent.Text
        }

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:scriptPath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            throw ("Failed to parse {0}: {1}" -f $script:scriptPath, $parseErrors[0].Message)
        }

        $harnessPath = Join-Path $TestDrive 'Run-ViAnalyzer.TransientRetry.Functions.ps1'
        Set-Content -Path $harnessPath -Value @(
                (Get-FunctionDefinitionText -Ast $ast -FunctionName 'Test-IsTransientLabVIEWCliConnectionFailure')
            ) -Encoding utf8

        . $harnessPath
    }

    It 'detects transient LabVIEWCLI startup connection failures' {
        $outputLines = @(
            'Error code : -350000',
            'Error message : LabVIEW CLI: (Hex 0xFFFAA8D0) The CLI for LabVIEW failed to establish a connection with LabVIEW.'
        )

        (Test-IsTransientLabVIEWCliConnectionFailure -ExitCode 1 -OutputLines $outputLines) | Should -BeTrue
    }

    It 'does not mark successful invocations as transient failures' {
        $outputLines = @(
            'RunVIAnalyzer operation succeeded.',
            '303 tests passed.'
        )

        (Test-IsTransientLabVIEWCliConnectionFailure -ExitCode 0 -OutputLines $outputLines) | Should -BeFalse
    }

    It 'does not mark unrelated failures as transient connection failures' {
        $outputLines = @(
            'Error code : -899001',
            'Error message : Invalid project path.'
        )

        (Test-IsTransientLabVIEWCliConnectionFailure -ExitCode 1 -OutputLines $outputLines) | Should -BeFalse
    }
}
