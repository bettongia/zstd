# betto_zstd: Windows x64 CI build

**Status**: Open

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

- [ ] **Q1 — MSVC via `windows-latest` runner.**
  Does `CBuilder.library` compile `zstd.c` cleanly on `windows-latest`
  using MSVC? What version of the Visual Studio build tools is available on
  `windows-latest`, and are there any compilation flags in `hook/build.dart`
  that need adjustment for MSVC (e.g. `/TC` for C compilation mode)?

- [ ] **Q2 — MinGW-w64 requirement from `0_05.md`.**
  Why does `0_05.md` specify MinGW-w64 rather than MSVC? Is it to enable
  Linux-hosted cross-compilation (building a Windows `.dll` without a Windows
  runner), or is it a preference? If MSVC on `windows-latest` satisfies the
  requirement, MinGW-w64 can be dropped.

- [ ] **Q3 — `native_toolchain_c` MinGW support.**
  If MinGW-w64 is required: does `native_toolchain_c` support pointing
  `CBuilder` at a MinGW toolchain, or does a separate `hook/build.dart`
  branch need to detect the MinGW target and invoke `gcc`/`clang` directly?
  Check `native_toolchain_c` source and issue tracker.

## Implementation plan

_To be filled in after investigation._

## Summary

_To be completed after implementation._
