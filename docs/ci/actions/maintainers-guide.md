# Maintainer's Guide

This repository is CI-only. The only workflow surface is `ci.yml` plus the internal reusable `runner-cli-reusable.yml`.

## Operational Notes

- Use `ci.yml` for validation and prerelease publication.
- There are no scheduled maintenance workflows (label sync, stale issues, audit) in this repository.
- Apply labels manually through the GitHub UI or CLI.

## Branch Protection

Keep required checks aligned to `CI Pipeline` and its required synthetic context(s). Remove any required checks that reference deleted workflows.
