# GitHub Actions Workflows (placeholder)

This directory is reserved for CI workflows to be added in Phase 2 (implementation
phase). See `docs/DESIGN.md`, section "CI / GitHub Actions Integration", for the
intended design of these workflows:

- `ci.yml` — build + unit tests on push/PR.
- `generate-check.yml` — regenerate `.d.ts` output from fixture assemblies and
  fail the build if the working tree differs from committed output (drift
  detection for consumers who commit generated files).
- `release.yml` — package and publish the CLI (target package manager / channel
  still TBD, see DESIGN.md "Open Questions").

No YAML is implemented yet; this file exists only so the directory is tracked
by git ahead of Phase 2.
