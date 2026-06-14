# betto_zstd: iOS and Android CI coverage

**Status**: Questions

**PR link**: —

**Depends on**: —

## Problem statement

`README.md` and `docs/spec/README.md` list iOS and Android as fully supported
platforms ("Compress + decompress"). The `integration_test_app/` Flutter
harness exists (`integration_test/zstd_test.dart` covers round-trip, empty
input, and compression level bounds) and the `make android_test` / `make
ios_test` Makefile targets exist — but both targets are empty shells, and no
GitHub Actions job invokes either.

`.github/workflows/ci.yml` has four jobs: `build` (Linux), `test-macos`,
`test-windows`, `test-web`. Mobile is entirely absent. This means:

- The `native_toolchain_c` build hook has **never been proven to cross-compile
  `zstd.c` for `arm64-apple-ios`, the iOS simulator, or Android ABIs in
  automation**. Mobile cross-compilation is exactly where toolchain surprises
  live: NDK version selection, bitcode requirements, simulator vs device arch
  differences, and minimum OS deployment targets.
- A regression in mobile support — or a first-time failure that was never
  detected — would only surface when a KMDB consumer attempts a mobile build,
  with no prior CI warning.

This plan adds automated CI coverage for iOS and Android, at minimum proving
that the package compiles for both platforms.

## Proposed approach

### Minimum viable: compile-only jobs

Two new jobs in `.github/workflows/ci.yml`, both dependent on `build`:

**`test-ios` (on `macos-latest`):**
1. Checkout + `dart-lang/setup-dart` + `subosito/flutter-action` (stable
   channel).
2. `cd integration_test_app && flutter build ios --no-codesign`

**`test-android` (on `ubuntu-latest`):**
1. Checkout + `dart-lang/setup-dart` + `subosito/flutter-action` (stable
   channel).
2. Set up Java (required by the Android build toolchain) with
   `actions/setup-java`.
3. `cd integration_test_app && flutter build apk`

Compile-only is the non-negotiable minimum. It proves that `native_toolchain_c`
can locate the NDK / Xcode toolchain and cross-compile `zstd.c` for the
target, and that the Dart FFI wiring resolves correctly at build time. It does
not prove the code runs correctly on a device, but it catches the class of
failure most likely to surprise KMDB (build-time breakage).

### Preferred: full integration test runs

The integration harness in `integration_test_app/integration_test/zstd_test.dart`
is already written and tests the important cases. Running it in CI is strongly
preferred over compile-only because it gives runtime confidence, not just
link-time confidence.

**Android emulator** runs are supported on GitHub Actions `ubuntu-latest`
runners via `reactivecircus/android-emulator-runner`. This adds significant
wall-clock time (~10 min) but gives real runtime assurance.

**iOS simulator** runs are supported on `macos-latest` via
`apple-actions/import-codesign-certs` + `xcrun simctl` + `flutter test
--device <simulator-id>`, or more simply via `flutter drive` targeting the
simulator. Requires no provisioning profiles for the simulator (as distinct
from device).

The compile-only jobs should be shipped first (fast, low-risk), with the full
emulator/simulator runs as a follow-up once the compile gate is green.

### Makefile targets

`make android_test` and `make ios_test` are currently empty. They should be
filled in to at minimum run the compile step, so developers can reproduce the
CI check locally before pushing:

```makefile
android_test:
	cd integration_test_app && flutter build apk
.PHONY: android_test

ios_test:
	cd integration_test_app && flutter build ios --no-codesign
.PHONY: ios_test
```

If full emulator/simulator runs are added to CI, the Makefile targets should
be updated to match (and retain the existing `EMULATOR_ANDROID` /
`EMULATOR_IOS` variable scaffolding for device-specific overrides).

## Open questions

- [ ] **Q1 — Compile-only vs. full emulator first.** Does KMDB currently target
  mobile, or is mobile a future requirement? If mobile is not yet a KMDB target,
  compile-only is sufficient for `0.1.0`. If mobile is active, full emulator
  runs should be the day-one target.

- [ ] **Q2 — Flutter channel.** The integration harness uses
  `sdk: ^3.12.0`. Should CI use the `stable` Flutter channel, or a pinned
  Flutter version? Pinning avoids surprise breakage from Flutter upgrades but
  requires periodic maintenance. `stable` is simpler.

- [ ] **Q3 — Android API level.** `reactivecircus/android-emulator-runner`
  requires an API level. What is the minimum Android API level KMDB targets?
  API 21 (Android 5.0) is the typical Flutter default.

- [ ] **Q4 — iOS minimum deployment target.** `flutter build ios --no-codesign`
  uses the deployment target from `integration_test_app/ios/`. What is the
  minimum iOS version KMDB targets? Confirm the existing `ios/` configuration is
  correct for the target.

- [ ] **Q5 — Job cost and wall-clock time.** Android emulator runs on GitHub
  Actions can take 10–15 minutes and consume significant free-tier minutes.
  Decide whether mobile jobs should run on every push/PR (matching the desktop
  jobs) or only on pushes to `main`.

- [ ] **Q6 — macOS x86_64.** The `test-macos` job uses `macos-latest`
  (currently arm64). If Intel Mac support matters, a matrix
  `[macos-latest, macos-13]` would cover both. Scope this separately from the
  mobile work, but decide at the same time to avoid a second CI restructure.

- [ ] **Q7 — Correct the "empty shells" claim and reconcile with existing
  Makefile targets.** The problem statement says `make android_test` /
  `make ios_test` "are empty shells." They are not — both already run full
  emulator/simulator integration tests (launch emulator, wait for device,
  `flutter test integration_test/zstd_test.dart`). The proposed Makefile
  snippets would *replace* working integration targets with weaker compile-only
  ones, regressing local developer capability. Decide: add separate
  `android_build` / `ios_build` compile-only targets and have CI call those,
  leaving the existing integration targets intact.

- [ ] **Q8 — `flutter drive` requires a test driver that does not exist.** The
  plan offers `flutter drive` as a "more simple" option for iOS simulator runs,
  but there is no `integration_test_app/test_driver/` directory. The existing
  Makefile targets correctly use `flutter test integration_test/...` (which
  needs no driver). Drop the `flutter drive` suggestion, or add the missing
  `test_driver/integration_test.dart` to the implementation scope.

- [ ] **Q9 — Spec and CI table updates.** `docs/spec/README.md` lists only the
  four current CI jobs (build, test-macos, test-windows, test-web) and states
  "A minimal Flutter application used exclusively as a test harness for iOS and
  Android CI" — implying CI coverage that does not yet exist. Adding mobile jobs
  must update the spec's CI/CD Pipeline table (and the integration-test prose if
  full runs land). Confirm this is in implementation scope.

## Implementation plan

_To be filled in after Q1 and Q5 are answered — they determine the scope of
the first implementation step (compile-only vs. full emulator, and run
frequency)._

## Reviews

### Review 1: 2026-06-14

**Problem Statement Assessment**

The problem is real and worth solving. The package's spec and README advertise
iOS and Android as fully supported ("Compress + decompress"), yet no CI job ever
exercises mobile cross-compilation. For a package whose entire native value
proposition is `native_toolchain_c` cross-compiling `zstd.c` per platform, an
unverified mobile claim is exactly the kind of gap that bites a downstream
consumer (KMDB) at integration time. This is correctly tracked as blocker B2 for
`0.1.0` in `docs/roadmap/v0.md`, so it is roadmap-aligned. Good.

However, the problem statement contains a **factual error that undermines the
proposed approach**: it claims `make android_test` and `make ios_test` "are
empty shells." They are not. Both already implement full emulator/simulator
integration runs (launch emulator, `adb wait-for-device` / `simctl boot`, then
`flutter test integration_test/zstd_test.dart`). This matters because the
proposed Makefile changes would overwrite working integration targets with
weaker compile-only ones — a regression in local developer capability dressed up
as filling in a gap. See Q7.

**Proposed Solution Assessment**

The compile-only-first, emulator-later phasing is sound and low-risk, and it
correctly identifies that build-time breakage is the failure class most likely
to surprise KMDB. The two-job structure (`test-ios` on `macos-latest`,
`test-android` on `ubuntu-latest`, both `needs: build`) is consistent with the
existing four-job layout in `.github/workflows/ci.yml`.

Weaknesses:

- The Makefile snippet regresses existing targets (Q7). The fix is trivial: add
  `android_build` / `ios_build` compile-only targets and point CI at those.
  Keep the integration targets.
- `flutter drive` is offered for the iOS simulator path, but there is no
  `integration_test_app/test_driver/` directory, so that path does not work as
  written (Q8). The existing `flutter test integration_test/...` approach is the
  right one and needs no driver.
- The plan does not mention updating `docs/spec/README.md`, whose CI/CD Pipeline
  table lists only the four current jobs and whose prose already describes the
  harness as being "used exclusively as a test harness for iOS and Android CI" —
  a claim that is currently aspirational. The spec must be updated as part of
  this work (Q9).

**Architecture Fit**

No conflict with the library-architecture three-layer model. This plan touches
only CI configuration, the Makefile, and the Flutter `integration_test_app/`
harness — it does not alter `lib/` structure, the public barrel, storage,
domain models, or widget extraction. The pure-Dart constraint
([[project_betto_zstd_pure_dart_constraint]]) is preserved: the harness app
depends on Flutter, but it lives outside the published package surface and is
already excluded via `.pubignore`. No library-architecture skill concerns apply.

The integration harness exercises only the native FFI path, which is correct —
the web/WASM path is covered by `test-web` and the B1 WASM freshness plan. There
is no double-coverage or gap.

**Risk & Edge Cases**

- **Flutter version drift (Q2).** With `sdk: ^3.12.0` in the harness and a
  `stable`-channel CI, a Flutter release that bumps the minimum NDK or Xcode can
  break the mobile jobs with no source change — the same reproducibility concern
  that drove pinning Emscripten to 6.0.0 for the WASM job
  ([[project_committed_artifact_reproducibility]]). For a release-gating job,
  prefer pinning the Flutter version (mirroring the `EMSCRIPTEN_VERSION` pattern)
  over floating `stable`.
- **CI cost (Q5).** Android emulator runs (10–15 min) on every PR are heavy. The
  compile-only jobs are cheap and belong on every PR; emulator/simulator runs
  are reasonable to gate to `main` pushes only. The plan already raises this;
  it just needs a decision.
- **`native_toolchain_c` + NDK selection.** This is the actual risk the plan
  exists to surface. Worth an explicit note that the *first* green run is the
  deliverable — it is entirely possible the compile fails on first attempt
  (NDK/Xcode toolchain discovery), in which case fixing the build hook is in
  scope, not out of it.
- **iOS deployment target / Android API level (Q3, Q4)** are unanswered and
  depend on KMDB's actual mobile targets. These are blocking for the emulator
  phase but not for compile-only.

**Recommendations**

1. Correct the "empty shells" claim and restructure the Makefile change to *add*
   `android_build` / `ios_build` rather than overwrite the integration targets
   (Q7). This is the most important fix.
2. Drop `flutter drive` from the plan, or add the missing test driver to scope
   (Q8).
3. Add spec updates (`docs/spec/README.md` CI/CD table + harness prose) to the
   implementation plan (Q9).
4. Resolve Q1 (does KMDB target mobile now?) and Q5 (run frequency) — together
   they determine whether the first deliverable is compile-only or full
   emulator, and on what trigger. The implementation plan is explicitly blocked
   on these.
5. Strongly consider pinning the Flutter version rather than tracking `stable`,
   consistent with the project's established artifact-reproducibility stance.
6. Treat the first green mobile build as the deliverable, with build-hook fixes
   in scope if cross-compilation fails on first run.

Once Q1, Q5, Q7, Q8, and Q9 are resolved (and Q3/Q4 if the emulator phase is
day-one), this is ready to move to `Investigated`. The core idea is correct and
roadmap-aligned; the blockers are scope-correctness issues, not conceptual ones.

**Open questions**

- [ ] Q7 — Correct the "empty shells" claim; add compile-only targets instead of
      overwriting the existing integration targets. (Also listed in Open
      questions.)
- [ ] Q8 — Resolve the `flutter drive` / missing `test_driver/` discrepancy.
- [ ] Q9 — Add `docs/spec/README.md` CI/CD table and harness-prose updates to
      scope.
- [ ] Q1, Q3, Q4, Q5 — Pre-existing open questions that gate the emulator phase
      and the implementation plan; still unresolved.

## Summary

_To be completed after implementation._
