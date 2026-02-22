# Build VI Package 📦

Runs **`build_vip.ps1`** to update a `.vipb` file's display info and build the VI Package via VIPM CLI.

## Inputs
| Name | Required | Example | Description |
|------|----------|---------|-------------|
| `supported_bitness` | **Yes** | `64` | Target LabVIEW bitness. |
| `repo_root` | **Yes** | `${{ github.workspace }}` | Repository root path. |
| `vipb_path` | **Yes** | `Tooling/deployment/NI Icon editor.vipb` | Path to the VIPB file. |
| `labview_version` | **Yes** | `2021` | LabVIEW 2021 (21.0). |
| `labview_minor_revision` | No (defaults to `0`) | `0` | LabVIEW minor revision. |
| `major` | **Yes** | `1` | Major version component. |
| `minor` | **Yes** | `0` | Minor version component. |
| `patch` | **Yes** | `0` | Patch version component. |
| `build` | **Yes** | `1` | Build number component. |
| `commit` | **Yes** | `abcdef` | Commit identifier. |
| `release_notes_file` | **Yes** | `Tooling/deployment/release_notes.md` | Release notes file. |
| `display_information_json` | **Yes** | `'{}'` | JSON for VIPB display information. |
| `vipb_build_lock_timeout_seconds` | No (defaults to `180`) | `180` | Timeout waiting for per-VIPB lock acquisition. |
| `vipb_build_lock_stale_seconds` | No (defaults to `300`) | `300` | Lock age threshold used to recover stale lock folders. |

## Collision Guardrail
- Builds acquire a per-`vipb` lock keyed by normalized VIPB path.
- The lock root resolves in this order: `LVIE_LOCK_ROOT`, `RUNNER_TEMP`, `TEMP`, then `<repo>\builds\locks`.
- If an existing lock is older than `vipb_build_lock_stale_seconds`, it is treated as stale and replaced.

## VIPM Port Guardrail
- Before invoking `vipm build`, the action validates VIPM target port mapping against `LabVIEW.ini` (`server.tcp.port`) for the selected LabVIEW version/bitness.
- The build fails fast on mismatch to prevent package operations from targeting the wrong LabVIEW instance.
- Manual check/fix helper:
  - `pwsh -NoProfile -File .\Tooling\Assert-VipmPortAlignment.ps1 -LabVIEWVersion 2020 -LabVIEWBitness 32`
  - `pwsh -NoProfile -File .\Tooling\Assert-VipmPortAlignment.ps1 -LabVIEWVersion 2020 -LabVIEWBitness 32 -Fix`

## Quick-start
```yaml
- uses: ./.github/actions/build-vip
  with:
    supported_bitness: 64
    repo_root: ${{ github.workspace }}
    vipb_path: Tooling/deployment/NI Icon editor.vipb
    labview_version: 2021
    major: 1
    minor: 0
    patch: 0
    build: 1
    commit: ${{ github.sha }}
    release_notes_file: Tooling/deployment/release_notes.md
    display_information_json: '{}'
    vipb_build_lock_timeout_seconds: 180
    vipb_build_lock_stale_seconds: 300
```

## License
This directory inherits the root repository’s license (MIT, unless otherwise noted).

