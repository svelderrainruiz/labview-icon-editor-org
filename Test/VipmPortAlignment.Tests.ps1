Describe "VIPM port alignment guard" {
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

        function New-VipmFixture {
            param(
                [int]$VipmPort,
                [int]$IniPort
            )

            $lvRoot = Join-Path -Path $TestDrive -ChildPath 'Program Files (x86)\National Instruments\LabVIEW 2020'
            New-Item -Path $lvRoot -ItemType Directory -Force | Out-Null

            $labviewExePath = Join-Path -Path $lvRoot -ChildPath 'LabVIEW.exe'
            New-Item -Path $labviewExePath -ItemType File -Force | Out-Null

            $labviewIniPath = Join-Path -Path $lvRoot -ChildPath 'LabVIEW.ini'
            @(
                "server.tcp.port=$IniPort"
                'server.tcp.enabled=True'
            ) | Set-Content -Path $labviewIniPath -Encoding ascii

            $settingsPath = Join-Path -Path $TestDrive -ChildPath 'VIPM.Settings.ini'
            @(
                '[Targets]'
                'Versions.<size(s)>="1"'
                'Versions 0="20.0"'
                'Locations.<size(s)>="1"'
                ("Locations 0=""{0}""" -f $labviewExePath)
                ("Ports=""<size(s)=1> {0}""" -f $VipmPort)
                'Disabled.<size(s)>="1"'
                'Disabled 0="FALSE"'
            ) | Set-Content -Path $settingsPath -Encoding ascii

            return [pscustomobject]@{
                SettingsPath = $settingsPath
                LabVIEWExePath = $labviewExePath
                LabVIEWIniPath = $labviewIniPath
            }
        }

        $script:repoRoot = Find-RepoRoot -StartPath $PSScriptRoot
        $script:guardScript = Join-Path $script:repoRoot 'Tooling\support\VipmPortAlignment.ps1'
        $script:assertScript = Join-Path $script:repoRoot 'Tooling\Assert-VipmPortAlignment.ps1'
        $script:buildVipScript = Join-Path $script:repoRoot '.github\actions\build-vip\build_vip.ps1'

        . $script:guardScript
    }

    It "keeps guard script syntax valid" {
        $null = $tokens = $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:guardScript, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It "keeps assert wrapper syntax valid" {
        $null = $tokens = $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:assertScript, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It "enforces VIPM port guard in build_vip.ps1" {
        $content = Get-Content -Path $script:buildVipScript -Raw
        $content | Should -Match 'Tooling\\support\\VipmPortAlignment\.ps1'
        $content | Should -Match 'Test-VipmTargetPortAlignment'
        $content | Should -Match 'VIPM target port mismatch detected'
    }

    It "detects mismatched VIPM and LabVIEW ports" {
        $fixture = New-VipmFixture -VipmPort 3371 -IniPort 3365
        $result = Test-VipmTargetPortAlignment -SettingsPath $fixture.SettingsPath -LabVIEWVersion 2020 -Bitness 32

        $result.passed | Should -BeFalse
        $result.mismatch_count | Should -Be 1
        $result.mismatches[0].reason | Should -Be 'port_mismatch'
        $result.mismatches[0].vipm_port | Should -Be 3371
        $result.mismatches[0].labview_port | Should -Be 3365
    }

    It "repairs mismatched VIPM ports and passes re-check" {
        $fixture = New-VipmFixture -VipmPort 3371 -IniPort 3365
        $repair = Repair-VipmTargetPortAlignment -SettingsPath $fixture.SettingsPath -LabVIEWVersion 2020 -Bitness 32

        $repair.changed | Should -BeTrue
        $repair.after.passed | Should -BeTrue
        Test-Path -Path $repair.backup_path | Should -BeTrue

        $updatedSettings = Get-Content -Path $fixture.SettingsPath -Raw
        $updatedSettings | Should -Match 'Ports="<size\(s\)=1> 3365"'
    }

    It "passes when ports are already aligned" {
        $fixture = New-VipmFixture -VipmPort 3365 -IniPort 3365
        $result = Test-VipmTargetPortAlignment -SettingsPath $fixture.SettingsPath -LabVIEWVersion 2020 -Bitness 32

        $result.passed | Should -BeTrue
        $result.mismatch_count | Should -Be 0
    }
}

