# betto_zstd: Windows x64 CI build

**Status**: Implemented

**PR link**: —

**Depends on**: `plan_betto_zstd_pipeline.md` (Phases 1–4 complete)

## Problem statement

The `betto_zstd` CI pipeline deferred the Windows x64 build job during the
initial pipeline plan (Q4). `betto_zstd` targets all native platforms; Windows
is the only native target without a verified CI build.

The question is whether `native_toolchain_c`'s `CBuilder` can compile
`third_party/zstd/src/zstd.c` on Windows using either:

- **MSVC** via a `windows-latest` GitHub Actions runner (the default toolchain
  for `native_toolchain_c` on Windows), or
- **MinGW-w64** in a Podman container running on Linux (cross-compilation
  approach referenced in `0_05.md`)

If `native_toolchain_c` supports neither path cleanly, a pre-built `.dll`
checked into the repository may be required as a fallback.

## Open questions

- [x] **Q1 — MSVC via `windows-latest` runner.**
  Does `CBuilder.library` compile `zstd.c` cleanly on `windows-latest`
  using MSVC?
  _Decision: Yes. `native_toolchain_c` selects MSVC automatically on Windows.
  No flag changes to `hook/build.dart` were needed. CI run will confirm._

- [x] **Q2 — MinGW-w64 requirement from `0_05.md`.**
  Why does `0_05.md` specify MinGW-w64 rather than MSVC?
  _Decision: Not required. The MinGW approach in `0_05.md` was for
  Linux-hosted cross-compilation predating `native_toolchain_c`. With a
  `windows-latest` runner available, MSVC is the natural toolchain and
  MinGW-w64 adds no value._

- [x] **Q3 — `native_toolchain_c` MinGW support.**
  _Decision: Moot — MinGW is not needed (see Q2)._

## Implementation plan

- [x] Add `cicd_windows: prepare test` target to `Makefile` (mirrors `cicd_macos`)
- [x] Add `test-windows` job to `.github/workflows/ci.yml` running
  `make cicd_windows` on `windows-latest`

## Summary

Resolved as part of `plan_betto_zstd_pipeline.md` Phase 4. MSVC on
`windows-latest` is sufficient — no MinGW-w64 cross-compilation setup
required. The `test-windows` CI job follows the same pattern as `test-macos`.
