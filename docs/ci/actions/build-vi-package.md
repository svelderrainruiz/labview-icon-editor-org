# Build VI Package

The VI Package is built inside the canonical CI workflow (`.github/workflows/ci.yml`) by the `build-vip` job.

## What the job does

- Updates the VIPB display info with repo/owner metadata.
- Builds the `.vip` artifact on Windows/self-hosted runners.
- Publishes the `.vip` artifact for eligible profiles (`full`, `pr-fast`).

## Inputs and branding

Branding values are sourced from `github.repository_owner` and `github.event.repository.name` by default. To customize, edit the display-info step in `ci.yml`.

## Manual runs

Use `workflow_dispatch` on `ci.yml` for deterministic backfill. Provide `expected_sha` and `strict_sha=true` when replaying publication for a known commit.

## Notes

- There is no dedicated workflow for VIP builds; `ci.yml` is the single source of truth.
- Release/publication behavior is defined by `docs/vip-prerelease-requirements.md`.
