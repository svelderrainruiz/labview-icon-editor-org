Describe "Workflow lane naming parity contract" {
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
        $script:ciWorkflowPath = Join-Path $script:repoRoot '.github\workflows\ci.yml'
        $script:ciWorkflow = Get-Content -Path $script:ciWorkflowPath -Raw
    }

    It "names Apply VIPC lanes with lvversion raw and x64/x86 labels" {
        $script:ciWorkflow | Should -Match 'name:\s*Apply VIPC \(LV \${{\s*needs\.version-gate\.outputs\.raw\s*}}\s+x64\)'
        $script:ciWorkflow | Should -Match 'name:\s*Apply VIPC \(LV \${{\s*needs\.version-gate\.outputs\.raw\s*}}\s+x86\)'
    }

    It "names source-test lanes with lvversion raw and x64/x86 labels" {
        $script:ciWorkflow | Should -Match 'name:\s*Test Source Using LV \${{\s*needs\.version-gate\.outputs\.raw\s*}}\s+\${{\s*matrix\.bitness_label\s*}}'
        $script:ciWorkflow | Should -Match "bitness_label:\s*x64"
        $script:ciWorkflow | Should -Match "bitness_label:\s*x86"
    }

    It "names packed-library lanes with lvversion raw and x64/x86 labels" {
        $script:ciWorkflow | Should -Match 'name:\s*Build Packed Library \(LV \${{\s*needs\.version-gate\.outputs\.raw\s*}}\s+x86\)'
        $script:ciWorkflow | Should -Match 'name:\s*Build Packed Library \(LV \${{\s*needs\.version-gate\.outputs\.raw\s*}}\s+x64\)'
    }

    It "names VI Package lane with lvversion raw and x64 label" {
        $script:ciWorkflow | Should -Match 'name:\s*Build VI Package \(LV \${{\s*needs\.version-gate\.outputs\.raw\s*}}\s+x64\)'
        $script:ciWorkflow | Should -Match 'Build VI Package \(LV \${{\s*needs\.version-gate\.outputs\.raw\s*}}\s+x64\)'
    }
}
