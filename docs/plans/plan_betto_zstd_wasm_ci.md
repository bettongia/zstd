# betto_zstd: WASM CI freshness check

**Status**: Open

**PR link**: —

**Depends on**: —

## Problem statement

`lib/assets/zstd.wasm` is a pre-built binary committed to the repository. The
native path is protected from version drift by `_assertVersionPinned` in
`hook/build.dart`, which reads `VERSION_ZSTD` and compares it against the
version macros compiled into `third_party/zstd/zstd.h`, failing the build on
any mismatch. The WASM binary has no equivalent guard.

A contributor can bump `VERSION_ZSTD`, update `third_party/zstd/src/zstd.c`,
regenerate the native bindings, and pass every CI job — while leaving
`lib/assets/zstd.wasm` built from a different version of the C source. The
`test-web` job in `.github/workflows/ci.yml` runs `dart test --platform chrome`
against the committed binary, but it never rebuilds from source and cannot
detect staleness. The "same C source → guaranteed frame compatibility" promise
that the README and spec stake the design on becomes a manual, unverified
human process.

This plan adds a CI gate that proves the committed WASM was built from the
current vendored C source.

## Proposed approach

Add a `verify-wasm` job to `.github/workflows/ci.yml` that:

1. Installs a **pinned version** of the Emscripten SDK via the
   `mymindstorm/setup-emscripten` action (the same `emcc` version used to
   produce the committed binary).
2. Runs `make wasm` to rebuild `lib/assets/zstd.wasm` from source.
3. Runs `git diff --exit-code lib/assets/zstd.wasm` — exits non-zero if the
   rebuilt binary differs from the committed one, failing the job.

This approach proves two things at once: (a) the WASM is reproducible under
the pinned toolchain, and (b) it was produced from the current `zstd.c`.

The `verify-wasm` job should:
- Run on `ubuntu-latest` (Emscripten is Linux-native and the fastest there).
- Depend on the existing `build` job (so it only runs if analysis + tests
  pass first).
- Not replace the existing `test-web` job — that job continues to run the
  Dart/Chrome tests against the committed binary. `verify-wasm` is a separate
  correctness gate.

The pinned Emscripten version must be recorded somewhere in the repository
(e.g., a `EMSCRIPTEN_VERSION` file at the root, analogous to `VERSION_ZSTD`)
so both the CI step and the `make wasm` Makefile comment can reference the
same value, and so any future Emscripten upgrade is an explicit, visible
change.

### Alternative: in-binary version stamp

If Emscripten build times make the CI job too expensive, a lighter alternative
is to embed the Zstd version into the WASM binary at build time — e.g., by
adding a `ZSTD_versionString` export to `src/zstd_wasm_helpers.c` and reading
it in `zstd_web.dart` at `init()` time, asserting it equals `_kVersion`. This
avoids rebuilding in CI but requires Dart-level code changes and a WASM rebuild
to activate; it also does not catch the case where the binary was built from
the right version but with different compiler flags.

The rebuild-and-diff approach is strongly preferred.

## Open questions

- [ ] **Q1 — Emscripten version selection.** Which version of Emscripten was
  used to produce the currently committed `lib/assets/zstd.wasm`? This must be
  determined (e.g., by checking `emcc --version` output recorded in a past
  commit, or by trying recent versions and comparing the binary) and recorded as
  the initial value of `EMSCRIPTEN_VERSION` before the CI job can be made
  non-flaky.

- [ ] **Q2 — Reproducibility of the Emscripten build.** Emscripten builds are
  generally reproducible for the same toolchain version, source, and flags, but
  this should be verified: rebuild `make wasm` twice locally under the same
  `emcc` version and confirm `git diff` is clean. If the build is not
  bit-for-bit reproducible (e.g., timestamps embedded in the binary), a hash of
  a stripped/normalised output may be needed instead of a raw `git diff`.

- [ ] **Q3 — emsdk cache strategy.** The Emscripten SDK installation is large
  (~1–2 GB). The `mymindstorm/setup-emscripten` action supports caching via
  `actions/cache`. Confirm caching works correctly for the pinned version to
  keep job times acceptable.

- [ ] **Q4 — Job placement in CI DAG.** Should `verify-wasm` block `test-web`
  (proving the binary is current before testing it), or run in parallel (saving
  wall-clock time at the cost of testing a potentially stale binary)? The clean
  answer is that `verify-wasm` should be a prerequisite of `test-web`, but that
  makes the web-test wall-clock time dependent on Emscripten install time.

- [ ] **Q5 — `EMSCRIPTEN_VERSION` file location.** Decide between a root-level
  `EMSCRIPTEN_VERSION` file (consistent with `VERSION_ZSTD`) or a comment in
  the Makefile's `wasm:` recipe. The file approach is more explicit and easier
  to grep for in CI.

## Implementation plan

_To be filled in after investigation (Q1 and Q2 are blockers for the plan to
reach Investigated status)._

## Summary

_To be completed after implementation._
