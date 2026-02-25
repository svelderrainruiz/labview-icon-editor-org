# Local CI/CD Workflows

**Last updated:** 2026-02-25

Quick link: `.github/workflows/ci.yml`.

This repository is CI-only. The workflow surface is intentionally minimal and centered on a single canonical workflow.

## Workflow Surface

- `.github/workflows/ci.yml` — canonical build/test/publish workflow.
- `.github/workflows/runner-cli-reusable.yml` — internal reusable workflow used by `ci.yml` to build runner-cli artifacts.

All other workflows were removed to eliminate stale automation and avoid conflicts with external orchestrators.

## Quickstart

1. Install prerequisites: LabVIEW per `.lvversion`, PowerShell 7+, Git, g-cli, VIPM/VIPC.
2. Configure a self-hosted Windows runner with the `self-hosted-windows-lv` label.
3. Run `ci.yml` via `push`, `pull_request`, or `workflow_dispatch`.

## Release Publication Policy

- Publish logic lives inside `ci.yml`.
- Eligible `develop` push runs can publish prereleases.
- Manual `workflow_dispatch` supports deterministic backfill using `expected_sha` and `strict_sha` inputs.

## Runner CLI

`ci.yml` builds runner-cli artifacts via `runner-cli-reusable.yml` and consumes them within the same run.

## Notes

If a document or script references a workflow other than `ci.yml` or `runner-cli-reusable.yml`, treat it as stale.
