# Local Agent Instructions

This repository uses LabVIEW, g-cli, and PowerShell tooling. Follow the steps below so the agent can run tests and local CI parity safely.

## Prerequisites
- Windows with PowerShell 7+ available as `pwsh`.
- `g-cli` available on PATH.
- LabVIEW version declared in `.lvversion` (currently `20.0`) installed for required 32-bit/64-bit lanes.
- VIPM/VIPC installed (required for dependency application).
- Python 3 with `pylavi` installed so `vi_validate` is on PATH.
- Node.js/npm available so `npx` can run `markdownlint-cli2` for local docs linting.

## Repo Setup
- Open a PowerShell terminal at the repo root.
- Confirm `g-cli` is available:
  - `g-cli --version`
- Resolve the current repository for `gh` commands:
  - `$repo = gh repo view --json nameWithOwner --jq .nameWithOwner`
  - `GH_REPO` is an optional override and takes precedence when set.
- If you need to open a PR from the current branch, use `gh`:
  - Default template: `gh pr create --repo $repo --base develop -T .github/PULL_REQUEST_TEMPLATE.md`
  - Draft PR: `gh pr create --repo $repo --base develop -T .github/PULL_REQUEST_TEMPLATE.md --draft`

## Repo-Agnostic Issue/Discussion Policy
- Issue and discussion actions operate on the repository currently being worked in.
- Use this command before issue/PR/workflow operations:
  - `$repo = gh repo view --json nameWithOwner --jq .nameWithOwner`
- Examples:
  - Create issue: `gh issue create --repo $repo --template "Bug Report"`
  - Create PR: `gh pr create --repo $repo --base develop -T .github/PULL_REQUEST_TEMPLATE.md`
  - List issues: `gh issue list --repo $repo --limit 50`

## GitHub Templates and Labels
- Use issue templates with `gh` (preferred):
  - Bug report: `gh issue create --repo $repo --template "Bug Report"`
  - Feature request: `gh issue create --repo $repo --template "Feature request"`
- Use PR templates with `gh`:
  - Generic: `gh pr create --repo $repo --base develop -T .github/PULL_REQUEST_TEMPLATE.md`
  - Bug fix: `gh pr create --repo $repo --base develop -T .github/PULL_REQUEST_TEMPLATE/bug_fix.md`
  - Feature addition: `gh pr create --repo $repo --base develop -T .github/PULL_REQUEST_TEMPLATE/feature_request.md`
  - Documentation update: `gh pr create --repo $repo --base develop -T .github/PULL_REQUEST_TEMPLATE/documentation.md`
  - Infrastructure change: `gh pr create --repo $repo --base develop -T .github/PULL_REQUEST_TEMPLATE/infrastructure_change.md`
- Web fallback links:
  - Resolve repository URL: `$repoUrl = gh repo view $repo --json url --jq .url`
  - Issues: `"$repoUrl/issues/new/choose"`
  - Bug form: `"$repoUrl/issues/new?template=bug_report.yml"`
  - Feature form: `"$repoUrl/issues/new?template=feature_request.yml"`
  - PR page: `"$repoUrl/compare"`

Label policy:
- Canonical release labels:
  - `Version Increment: Major`
  - `Version Increment: Minor`
  - `Version Increment: Patch`
- Canonical issue-type labels:
  - `Issue group: Bug`
  - `Type: Enhancement`
- Compatibility aliases are accepted for two release cycles:
  - `major` -> `Version Increment: Major`
  - `minor` -> `Version Increment: Minor`
  - `patch` -> `Version Increment: Patch`
  - `bug` -> `Issue group: Bug`
  - `enhancement` -> `Type: Enhancement`

Metadata quick-checks:
- Unlabeled PRs (no normalized release label):
  - `gh pr list --repo $repo --state open --search "-label:'Version Increment: Major' -label:'Version Increment: Minor' -label:'Version Increment: Patch' -label:major -label:minor -label:patch"`
- Unlabeled issues:
  - `gh issue list --repo $repo --state open --search "no:label" --limit 200`
- Alias-only issue types:
  - ```
    $items = gh issue list --repo $repo --state open --limit 200 --json number,title,labels | ConvertFrom-Json
    $items | Where-Object {
      ($_.labels.name -contains 'enhancement' -or $_.labels.name -contains 'bug') -and
      -not ($_.labels.name -contains 'Type: Enhancement' -or $_.labels.name -contains 'Issue group: Bug')
    } | Select-Object number,title,@{Name='labels';Expression={ $_.labels.name -join ', ' }}
    ```

## pylavi / vi_validate gate
- The CI pipeline includes a fast LabVIEW file validation step powered by `pylavi` (`vi_validate`) and runs **before** any g-cli/LabVIEW work.
- The gate uses `.lvversion` as the canonical LabVIEW version and passes it to `vi_validate --eq` automatically.
- Absolute-path focus: optionally set `LVIE_PYLAVI_ABSOLUTE_PATH_ROOTS` (semicolon-delimited) to flag specific roots without committing sensitive paths. CI redacts configured roots in logs and the uploaded pylavi log artifact.
- CI also uploads a redacted top-offenders report artifact per pylavi run (`pylavi-validate-offenders-<label>`) and prints the top offenders table in the step summary.
- Local runs write a redacted offenders report to `TestResults\agent-logs\pylavi-offenders.latest.json`. Use `Tooling\Get-PylaviOffenders.ps1` to summarize it.
- If the local report is missing, fetch the latest CI artifact instead: `pwsh -NoProfile -File .\Tooling\Fetch-PylaviOffenders.ps1 -Branch develop` or `pwsh -NoProfile -File .\Tooling\Get-PylaviOffenders.ps1 -FetchLatest`. Requires `GH_TOKEN`/`GITHUB_TOKEN` with `actions:read`.
- Deterministic: `Tooling\Get-PylaviOffenders.ps1 -Sha <commit>` to read `pylavi-offenders.<sha>.json`, or `-RunId <id> -FetchLatest` to pin a specific workflow run.
- Baseline/delta gating (runner-cli): set `LVIE_PYLAVI_BASELINE_PATH` to a redacted offenders report and optionally `LVIE_PYLAVI_FAIL_ON_DELTA=1` to fail on new offenders. Use `LVIE_PYLAVI_BASELINE_REQUIRED=1` to require the baseline file.
- Runner-cli-only toggle: set `LVIE_REQUIRE_RUNNER_CLI=1` to enforce runner-cli usage (no PowerShell fallback).
- Config files:
  - `Tooling/pylavi/vi-validate.yml` (strict scope; version injected at runtime).
  - `Tooling/pylavi/vi-validate-legacy.yml` (legacy scope; typically absolute-path checks only).
- CI report-only step uses the composite action: `.github/actions/pylavi-validate`.
- Install (user scope):
  - `py -m pip install --user pylavi`
- Verify install:
  - `vi_validate --help`
- If `vi_validate` is not found, ensure your Python Scripts folder is on PATH (typical: `%APPDATA%\Python\Python3x\Scripts`).
- To re-run in CI, use `workflow_dispatch` on `ci.yml`.

## VI Analyzer gate
- Canonical task registry: `Tooling\vi-analyzer\tasks.json` (exactly three tasks for API, plugins, and tooling scopes, mapped to repo-root `.viancfg` files).
- Canonical container contract: `.lvcontainer` (literal NI container tag, e.g. `2026q1-linux` or `latest-linux`; CI resolves image/OS/runtime metadata from live Docker Hub tag discovery with snapshot fallback).
- Canonical executor: `Tooling\Run-ViAnalyzer.ps1`.
- Runtime worker: `Tooling\container-parity\run-vi-analyzer-linux.sh` (dockerized LabVIEW Linux lane).
- Local smoke run:
  - `pwsh -NoProfile -File .\Tooling\Run-ViAnalyzer.ps1 -RepoRoot . -SupportedBitness 64`
- Use `ci.yml` for deterministic VI Analyzer runs.
  - `auto` runs the gate only when both `pwsh` and `docker` are available; otherwise it prints an explicit skip reason.
- CI evidence:
  - artifact `vi-analyzer-reports` from `builds/vi-analyzer`
  - artifact `vi-analyzer-status` from `builds/status/vi-analyzer-summary.json`
  - step summary table emitted by `Run-ViAnalyzer.ps1`.

## Worktree root (short paths)
Use a short path for worktrees to avoid Windows path-length issues. Local default is repo-derived (`<repo-context>\worktrees`) when `LVIE_WORKTREE_ROOT` is unset; for self-hosted runners, standardize under the runner directory (example: `C:\actions-runner\_work\lvie\w`).

Override:
- Set `LVIE_WORKTREE_ROOT` to change the default worktree root.
  - Runner contract helper: `pwsh -NoProfile -File .\Tooling\Setup-Runner.ps1 -RunnerRoot C:\actions-runner -Scope Machine` (creates `<runner-root>\_work\lvie\w`, writes `<runner-root>\_work\lvie\runner-contract.json`, and sets env vars).

Preflight requirement:
- Explicit worktree roots (`-WorktreeRoot` or `LVIE_WORKTREE_ROOT`) must exist before proceeding.
- Repo-derived default roots are created automatically when missing.
- For CI/self-hosted runners, ensure the directory is pre-created; fail fast with a clear message if missing.
 - Local parity scripts hard-fail if `RepoRoot` is not under the worktree root; set `LVIE_WORKTREE_ROOT` or run from a worktree path.

Example preflight (PowerShell):
```
$worktreeRoot = $env:LVIE_WORKTREE_ROOT
if ([string]::IsNullOrWhiteSpace($worktreeRoot)) { $worktreeRoot = Join-Path (Resolve-Path .).Path 'worktrees' }
if (-not (Test-Path $worktreeRoot)) {
  New-Item -Path $worktreeRoot -ItemType Directory -Force | Out-Null
}
```

Worktree creation helper (recommended):
```
pwsh -NoProfile -File .\Tooling\New-CIWorktree.ps1 `
  -Ref HEAD
```

Notes:
- The helper enforces explicit worktree roots and auto-creates repo-derived defaults when needed.
- Use `-Name` to label the worktree directory.
- Use `-WorktreeRoot` (or `LVIE_WORKTREE_ROOT`) to override the default.

## CI worktree naming (ci.yml)
CI jobs create short-path worktrees under `LVIE_WORKTREE_ROOT` with a deterministic name:
- `ci-<workflowhash>-<jobhash>-<bitness>-<runid>-<attempt>`
- Some workflows insert an extra variant token (e.g. LabVIEW version) between `<jobhash>` and `<bitness>`.
- `workflowhash` is the first 8 chars of the SHA1 of workflow identity (`GITHUB_WORKFLOW_REF`, fallback `GITHUB_WORKFLOW`).
- `jobhash` is the first 8 chars of the SHA1 of `GITHUB_JOB` (prevents collisions across jobs).
- `bitness` is `32` or `64`.
Example: `<worktree-root>\ci-2A4C7D91-D170BDEE-64-21534416929-1`

Troubleshooting:
- CI worktree setup automatically runs `git worktree prune` and clears stale registrations for the target path before creation to avoid `missing but already registered worktree` failures.

The workflow exports:
- `REPO_ROOT` → worktree path (authoritative for all scripts)
- `PROJECT_PATH` → `$REPO_ROOT\lv_icon_editor.lvproj`
- `LABVIEW_VERSION_YEAR` / `LABVIEW_MINOR_REVISION` → derived from `.lvversion` (for example, `20.0` resolves to year `2020` and minor `0`)

Note: CI reads `.lvversion` from `REPO_ROOT` as the canonical LabVIEW version for runs.

Helper used by CI:
```
pwsh -NoProfile -File .\Tooling\New-CIWorktreeForJob.ps1 -Bitness 64
```

## CI concurrency (self-hosted LabVIEW runners)
LabVIEW workflows are serialized on the shared self-hosted runner label to avoid concurrent g-cli/LabVIEW conflicts.

Notes:
- Workflows share a concurrency group keyed by repository + runner label (e.g., `labview-<repo>-self-hosted-windows-lv-ie`).
- Missing-in-project is inlined in `ci.yml` to avoid reusable workflow skips; the standalone workflow is manual only.
- Self-hosted LabVIEW jobs acquire a runner lock at `<lock_root>\labview-runner.lock` via `Tooling\RunnerLock.ps1`. The lock auto-expires stale entries (lease + optional GitHub run status check) and logs owner metadata. Env overrides: `LVIE_LOCK_ROOT`, `LVIE_RUNNER_LOCK_TIMEOUT_SECONDS`, `LVIE_RUNNER_LOCK_LEASE_SECONDS`, `LVIE_RUNNER_LOCK_STALE_SECONDS`, `LVIE_RUNNER_LOCK_GITHUB_CHECK`, `LVIE_RUNNER_LOCK_GITHUB_MIN_AGE_SECONDS`, `LVIE_RUNNER_LOCK_GITHUB_CHECK_INTERVAL_SECONDS`.

## Worktree cleanup
To keep your configured worktree root tidy, remove old worktrees after you’re done with them.

List worktrees:
```
git worktree list
```

Remove a specific worktree directory:
```
git worktree remove <worktree-root>\<worktree-folder>
```

Prune stale worktree metadata (after deleting folders manually):
```
git worktree prune
```

## Run CI for a specific commit (workflow_dispatch)
Dispatch against a temporary branch that points to the target SHA:
```
git push origin <commit>:refs/heads/ci-run/<shortsha>
gh workflow run "CI Pipeline" --ref ci-run/<shortsha> -f expected_sha=<commit> -f strict_sha=true
```

Notes:
- Delete the temporary branch after dispatch when no longer needed: `git push origin --delete ci-run/<shortsha>`.

## Deterministic prerelease publish (manual)
Use workflow_dispatch on `ci.yml` with strict SHA inputs:
```
gh workflow run "CI Pipeline" --ref <ref> -f publish_prerelease=true -f expected_sha=<merged-develop-merge-sha> -f strict_sha=true
```

## Background automation safety
Some automation may be running in the background and must not be killed. Do not terminate `g-cli` or `LabVIEW` processes unless you have explicit confirmation it is safe.
- Before running a new step, record active processes:
  - `Get-Process -Name g-cli,LabVIEW -ErrorAction SilentlyContinue | Format-Table -AutoSize`
- If a process is already running, wait for it to finish or skip the new run and log the reason. Do not kill it.
- Only use `.github\actions\close-labview\Close_LabVIEW.ps1` when it will not interfere with background automation.

## Pester Integration Tests
Run the integration suite (includes dev-mode tests when enabled):
```
pwsh -NoProfile -File .\Test\Pester\Run-Pester.ps1 `
  -LabVIEWBitness both `
  -RunDevModeTests `
  -ConnectTimeoutMs 180000 `
  -ProcessTimeoutMs 300000
```

Notes:
- If LabVIEW is not installed for a bitness, tests will skip that bitness.

## Troubleshooting
- If `g-cli` cannot connect, increase `-ConnectTimeoutMs` and `-ProcessTimeoutMs`.
- If a run hangs, close LabVIEW and re-run the step:
  - `.github\actions\close-labview\Close_LabVIEW.ps1`
- Release note generation can log `git describe` errors in shallow or tagless repos; VIP builds may still complete, but fetch tags if you need accurate version strings.
- If `vi_validate` is missing, confirm `py -m pip show pylavi` and ensure the Python Scripts directory is on PATH.
- If Windows container parity fails with `ScriptRequiresUnmatchedPSVersion`, run `pwsh -NoProfile -File .\Tooling\Test-PathContract.ps1 -WriteSummary` and remove any file-scope `#Requires -Version` from `Tooling\support\PathContract.ps1`.


