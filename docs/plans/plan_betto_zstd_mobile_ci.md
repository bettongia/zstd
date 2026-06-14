# betto_zstd: iOS and Android CI coverage

**Status**: Open

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

## Implementation plan

_To be filled in after Q1 and Q5 are answered — they determine the scope of
the first implementation step (compile-only vs. full emulator, and run
frequency)._

## Summary

_To be completed after implementation._
