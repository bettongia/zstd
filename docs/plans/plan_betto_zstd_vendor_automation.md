# betto_zstd: Vendored C source update automation

**Status**: Open

**PR link**: —

**Depends on**: `plan_betto_zstd_pipeline.md` (Phase 3 VERSION_ZSTD pinning complete)

## Problem statement

The `third_party/zstd/` amalgamation (`zstd.c`, `zstd.h`) was assembled
manually by running Zstd's `create_single_file_library.sh` script against a
downloaded release tarball. The steps are documented in prose in
`third_party/zstd/README.md` but there is no automation: no `make` target,
no pinned download URL, no integrity check. Any Zstd version bump requires a
developer to manually replicate those steps with no reproducibility guarantee.

This plan adds a `make update_zstd VERSION=x.y.z` target that makes version
bumps a single auditable command.

## Proposed approach

A `Makefile` target that:

1. Downloads the Zstd release tarball from the GitHub releases URL
   (`https://github.com/facebook/zstd/releases/download/vVERSION/zstd-VERSION.tar.gz`)
2. Verifies the download against a SHA-256 digest stored in
   `third_party/zstd/VERSION_ZSTD.sha256` (updated by the target itself
   on first run, or provided by the developer for a new version)
3. Runs `create_single_file_library.sh` from the extracted tarball
4. Copies `zstd.c` and `zstd.h` to `third_party/zstd/src/` and
   `third_party/zstd/`
5. Updates the `VERSION_ZSTD` file at the repo root

The WASM blob (`lib/assets/zstd.wasm`) also needs to be regenerated after a
source update. The `make wasm` target (added in the pipeline plan) handles
this; the update target should print a reminder to re-run `make wasm` and
commit the new blob.

## Open questions

- [ ] **Q1 — Shell vs. Dart script.** Should the update target be a shell
  script (invoked from `Makefile`) or a Dart script in `tool/`? Shell is
  simpler for a download-and-copy task; Dart would be consistent with
  `hook/build.dart` but adds overhead for a maintenance-only tool.

- [ ] **Q2 — SHA-256 source of truth.** Zstd GitHub releases include
  `.tar.gz.sha256` files alongside the tarballs. The target can fetch and
  verify against these automatically rather than requiring a manually
  maintained `VERSION_ZSTD.sha256` file. Confirm this is available for all
  recent Zstd releases.

- [ ] **Q3 — `create_single_file_library.sh` dependencies.** The script
  requires standard tools (`cat`, `awk`, `sed`). Confirm it runs cleanly on
  macOS and Linux without additional dependencies. Document any requirements
  in the README.

## Implementation plan

_To be filled in after investigation._

## Summary

_To be completed after implementation._
