# Documentation Index

This directory collects guides and references for working with the LabVIEW Icon Editor.

## General Guides
- [CI Workflows Overview](ci-workflows.md)
  - Canonical source for CI behavior and release/publication policy.
- [LLM Operator Runbook](ci/llm-operator-runbook.md)
  - Deterministic command-first workflow for validate/integrate/release modes.
- [VI Package Pre-Release Requirements](vip-prerelease-requirements.md)
  - Normative contract for `develop` prerelease publication behavior and workflow interfaces.
  - Acceptance matrix: [vip-prerelease-requirements-v1-acceptance.md](vip-prerelease-requirements-v1-acceptance.md)
  - Trace matrix: [vip-prerelease-requirements-v0-to-v1-trace.md](vip-prerelease-requirements-v0-to-v1-trace.md)
- [Runner CLI Requirements](runner-cli-requirements.md)
  - Runner CLI artifacts are built inside `ci.yml` via `runner-cli-reusable.yml`.

## CI and Advanced Topics

- [Experiments Guide](ci/experiments.md)
- [Troubleshooting & FAQ](ci/troubleshooting-faq.md)
- [Composite Actions](ci/actions/README.md)
  - [Build VI Package](ci/actions/build-vi-package.md)
  - [Injecting Repo/Org to VI Package](ci/actions/injecting-repo-org-to-vi-package.md)
  - [Maintainer's Guide](ci/actions/maintainers-guide.md)
  - [Runner Setup Guide](ci/actions/runner-setup-guide.md)
  - [Troubleshooting Experiments](ci/actions/troubleshooting-experiments.md)

## Archived/Historical CI References

- [Multichannel Release Workflow](ci/actions/multichannel-release-workflow.md)
- Not normative. Source of truth is [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) and [CI Workflows Overview](ci-workflows.md).
