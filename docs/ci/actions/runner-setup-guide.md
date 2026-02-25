# Runner Setup Guide

This guide covers self-hosted runner setup for the LabVIEW Icon Editor CI pipeline (`.github/workflows/ci.yml`).

## Prerequisites

- LabVIEW version declared in `.lvversion` (currently `20.0`), 32-bit and 64-bit.
- LabVIEWCLI available on PATH for Windows automation paths.
- VIPM/VIPC installed.
- PowerShell 7+ and Git for Windows.

## Quickstart

1. Apply `.github/actions/apply-vipc/runner_dependencies.vipc` in both 32-bit and 64-bit LabVIEW.
2. Register a self-hosted runner and ensure the `self-hosted-windows-lv` label is present.
3. Run `ci.yml` via `push`, `pull_request`, or `workflow_dispatch`.

## CI Profiles (Summary)

- `full`: default for `push` and `workflow_dispatch` without `force_gcli_lunit=true`.
- `pr-fast`: used for pull requests; 64-bit-only for selected jobs.
- `release-priority`: manual dispatch with `force_gcli_lunit=true`; skips selected heavy jobs while keeping required gates.

## Worktree Root (Recommended)

Use short worktree paths to avoid Windows path-length issues. The runner contract helper creates a standard worktree root:

```
pwsh -NoProfile -File .\Tooling\Setup-Runner.ps1 -RunnerRoot C:\actions-runner -Scope Machine
```

This writes `runner-contract.json` and sets `LVIE_WORKTREE_ROOT`, `LVIE_ARTIFACT_ROOT`, `LVIE_LOCK_ROOT`, and `LVIE_LOG_ROOT`.

## Notes

- CI treats `.lvversion` as the canonical LabVIEW version.
- Manual dev-mode scripts can still be run locally, but there is no dedicated workflow for dev-mode toggling.
