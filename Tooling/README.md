# Tooling

This folder contains PowerShell scripts invoked by `ci.yml` or its composite actions.

## Common entrypoints (CI-oriented)

- `Assert-LabVIEWVersion.ps1` — resolves `.lvversion` and enforces version contract.
- `Check-Runner.ps1` — runner sanity checks and safe.directory setup.
- `Ensure-RunnerCli.ps1` — resolves or builds runner-cli when required.
- `Run-ViAnalyzer.ps1` — runs VI Analyzer tasks via LabVIEWCLI.
- `Inspect-VipPackage.ps1` — validates VIP contents by zip path.
- `Invoke-MarkdownLint.ps1` — markdown lint for docs.
- `Invoke-PSScriptAnalyzer.ps1` — PowerShell lint.

## Worktree helpers

- `Ensure-WorktreeRoot.ps1`
- `New-CIWorktree.ps1`
- `New-CIWorktreeForJob.ps1`
- `Resolve-CIWorktreeRoot.ps1`

## Notes

Scripts not referenced by `ci.yml` or its composite actions are intentionally removed.
