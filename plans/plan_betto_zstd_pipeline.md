# betto_zstd: Web/WASM support and multi-platform pipeline

**Status**: Implementing

**PR link**: —

## Problem statement

`betto_zstd` currently works only on native platforms (macOS, Linux, iOS, Android,
Windows) via Dart FFI and `native_toolchain_c`. The web platform is entirely
unsupported.

For KMDB v0.05 this creates two distinct problems of different severity:

1. **Web decompression is non-deferrable.** Native KMDB clients write
   Zstd-compressed SSTable values (flag byte prefix = `0x01`). A web client
   that cannot decompress those values cannot participate in a sync pool with
   native devices — it will silently fail to decode every document written by a
   native device. WASM decompression must land before any web KMDB client can
   sync with native.

2. **Web write-side compression is a go/no-go gate.** Whether web clients can
   *produce* Zstd-compressed values depends on whether the WASM Zstd frames are
   byte-compatible with what native `betto_zstd` decompresses. This must be
   verified empirically. If the frames are incompatible, web writes remain
   uncompressed (the current behaviour) — which is safe and already supported by
   KMDB's 1-byte flag prefix. If they are compatible, web write compression can
   be enabled.

Secondary concerns:

- The `native_toolchain_c` `CBuilder` handles single-platform compilation at
  build time. Multi-platform CI (Linux cross-compilation, Windows MinGW,
  Android, iOS) needs a GitHub Actions pipeline and verification that the hook
  compiles cleanly on each target.
- `publish_to: none` must be removed for the pub.dev beta release (see KMDB
  roadmap review §3.8). Any remaining pub.dev publishing blockers must be
  resolved.

## Open questions

- [x] **Q1 — `zstandard` pub.dev package in non-Flutter web context.**
  The [`zstandard`](https://pub.dev/packages/zstandard) package claims WASM
  support on web. Does it work in a pure-Dart web context (i.e. compiled with
  `dart compile wasm` / `webdev`, not Flutter Web)? KMDB's web clients are
  Flutter Web, so Flutter dependency may be acceptable — but it must be
  confirmed.
  _Decision: BLOCKED — `zstandard` (and every sub-package in its federated
  plugin family: `zstandard_web`, `zstandard_platform_interface`) declare
  `flutter: sdk: flutter` and `flutter: ">=3.3.0"` in their `environment`
  field. Adding `zstandard` to `betto_zstd` would make `betto_zstd` depend on
  Flutter. KMDB is a pure-Dart project (confirmed via CLAUDE.md: `kmdb_ui` is
  the Flutter layer in a separate repo); `betto_zstd` is a KMDB dependency and
  must not carry a Flutter SDK requirement. Option A as written is incompatible
  with the pure-Dart constraint. See Q5 for the replacement approach._

- [x] **Q2 — Frame compatibility between `zstandard` WASM output and native
  `betto_zstd` output.** Compress a known byte sequence with native
  `betto_zstd` and decompress with the WASM path (and vice versa). Any mismatch
  blocks write-side compression; decompression-only can still land.
  _Decision: RESOLVED by Q5. Option B (Emscripten) compiles the same
  `third_party/zstd/src/zstd.c` source with the same flags for both native
  (via `native_toolchain_c`) and WASM (via Emscripten). The Zstd frame format
  is deterministic for a given input and compression level regardless of the
  host architecture or compilation target, so byte-for-byte frame compatibility
  between the native FFI path and the WASM path is guaranteed by construction.
  No empirical go/no-go test is required for write-side compression — both
  paths are always enabled. The `test/frame_compat_test.dart` golden-file test
  remains valuable as a regression guard but is no longer a decision gate._

- [ ] **Q3 — `native_toolchain_c` cross-compilation for Android and iOS.**
  The `CBuilder` compiles C source for the *target* platform during a Flutter
  build. Does this work out-of-the-box for `arm64-v8a` Android and iOS arm64
  without manual toolchain configuration? Confirm with a test build.

- [ ] **Q4 — Windows MinGW-w64 cross-compilation path.**
  0_05.md specifies MinGW-w64 in a Podman container for Windows builds.
  Does `native_toolchain_c` support MinGW targets, or does a separate
  `hook/build.dart` branch (or a pre-built `.dll`) need to be used?
  _Deferred: Windows build is out of scope for this plan. Resolve in a
  follow-up after Phases 1–4 (non-Windows) are complete._

- [x] **Q5 — Pure-Dart web implementation approach.** Given that `zstandard`
  requires Flutter SDK (Q1 resolved as blocked), what is the correct web
  implementation?
  _Decision: Option B (Emscripten) confirmed. Build `third_party/zstd/src/zstd.c`
  to WASM via Emscripten; load the `.wasm` blob via `dart:js_interop`'s
  `WebAssembly.instantiate` API in `lib/src/zstd_web.dart`. No Flutter
  dependency — `dart:js_interop` is part of the Dart SDK. Guarantees frame
  compatibility with the native FFI path (same source, same flags; see Q2).
  No other Zstandard packages will be used by KMDB. `betto_zstd` handles all
  platforms itself: native (macOS, Linux, iOS, Android, Windows) via FFI and
  web via a self-built Emscripten WASM module compiled from the same
  `third_party/zstd/src/zstd.c` source. Option C (native-assets WASM target)
  remains unsupported as of Dart SDK 3.12 and is deferred._

- [ ] **Q6 — Vendored C source download automation.** The `third_party/zstd/`
  amalgamation was assembled manually using Zstd's `create_single_file_library.sh`
  script. There is no `make update_zstd` or equivalent target. How should
  version bumps be automated? The `betto_icu` package does not vendor any C
  source (it uses system ICU), so there is no comparable pattern to follow in
  this project family. Proposal: add a `make update_zstd VERSION=x.y.z` target
  that downloads the Zstd release tarball, runs `create_single_file_library.sh`,
  copies the output to `third_party/zstd/`, and updates `VERSION_ZSTD`. This
  makes version bumps reproducible and auditable.
  _Deferred: get compilation working first (Phases 1–3), then automate the
  update workflow in a follow-up._

## Investigation

### Current state

`betto_zstd` is a Dart native-assets package. The `hook/build.dart` calls
`CBuilder.library` to compile `third_party/zstd/src/zstd.c` into a platform
dynamic library (`libzstd.dylib`, `.so`, or `.dll`). The Dart API is a thin
`@Native` wrapper (`ZstdSimple`) with `compress()` and `decompress()` methods,
using `malloc`/`free` for FFI memory management.

The test suite (`test/compression_test.dart`) exercises round-trips, edge cases
(empty, truncated, invalid), and level bounds.

No `.github/` directory exists; there is no CI pipeline.

`pubspec.yaml` has `publish_to: none` — not yet ready for pub.dev.

### Web/WASM approach

`dart:ffi` is unavailable on web. The chosen approach is Option B: a
self-built Emscripten WASM module (Q5 resolved).

**Option A (`zstandard` pub.dev package) — DISQUALIFIED.**
Every package in the `zstandard` federated plugin family (`zstandard`,
`zstandard_web`, `zstandard_platform_interface`) declares `flutter: sdk: flutter`
in `dependencies` and `flutter: ">=3.3.0"` in `environment`. Adding any of them
to `betto_zstd`'s `pubspec.yaml` would introduce a Flutter SDK dependency into
a package that must remain pure Dart (KMDB is a pure-Dart project; `betto_zstd`
is a direct KMDB dependency, not a `kmdb_ui` dependency).

**Option B — Build Zstd to WASM ourselves via Emscripten (CONFIRMED).**
Compile `third_party/zstd/src/zstd.c` with Emscripten to produce a `.wasm`
module, bundle it under `lib/src/` as a compiled asset, and call it from
`lib/src/zstd_web.dart` via `dart:js_interop`'s `WebAssembly.instantiate` API.
`dart:js_interop` is part of the Dart SDK — no Flutter dependency is introduced.
Frame compatibility with the native FFI path is guaranteed by construction
(same source, same flags; Zstd frame format is deterministic for a given input
and level — see Q2). Both compress and decompress are enabled on web.
`betto_icu`'s `BrowserTokenizer` is the reference implementation pattern for
`dart:js_interop` usage in this package family.

### Conditional export structure

```
lib/
  zstd.dart                   — conditional export
  src/
    zstd_native.dart          — @Native FFI impl (renamed from current zstd_base.dart)
    zstd_web.dart             — dart:js_interop wrapper around self-built Emscripten WASM
    zstd_unsupported.dart     — throws UnsupportedError (fallback / test stub)
lib/assets/
    zstd.wasm                 — pre-compiled Emscripten WASM module (checked in)
```

`lib/zstd.dart` selects the right implementation using Dart's `platform`
conditional imports:

```dart
export 'src/zstd_native.dart'
    if (dart.library.js_interop) 'src/zstd_web.dart';
```

The public API (`ZstdSimple`, `minCLevel`, `maxCLevel`) must remain unchanged.
On web, `minCLevel` / `maxCLevel` expose the known Zstd defaults (−131072, 22)
as constants — these are fixed by the Zstd specification and match the values
compiled into the WASM module from the same source.

`zstd_web.dart` loads `zstd.wasm` via `dart:js_interop`'s
`WebAssembly.instantiate`, manages WASM heap allocation/deallocation explicitly
(using the module's exported `malloc`/`free` or Zstd's internal allocator), and
exposes compress and decompress. Both directions are enabled — frame
compatibility is guaranteed because the WASM module is compiled from the same
`third_party/zstd/src/zstd.c` source (Q2 resolved).

### Frame compatibility verification test

A dedicated test file (`test/frame_compat_test.dart`) must run on both native
and web (`dart test --platform chrome`) and verify:

1. A fixed byte sequence compressed by the native FFI path decompresses
   correctly via the WASM path (if WASM decompression is available).
2. A fixed byte sequence compressed by the WASM path decompresses correctly via
   the native FFI path (go/no-go gate for write-side compression).
3. Round-trip on web: compress web → decompress web.

The test must use a fixture produced by the *other* platform (golden-file style)
so that any frame format divergence is detected immediately rather than only at
integration test time. Generate the golden fixture file from the native path
and check it into `test/fixtures/`.

### Multi-platform CI

The `native_toolchain_c` `CBuilder` compiles for the target platform at Flutter
/ Dart build time — no pre-built binaries are required. CI verification is
needed to confirm the hook compiles cleanly on each platform:

| Platform | CI runner | Toolchain |
|---|---|---|
| macOS (universal) | `macos-latest` | Xcode clang; `lipo` for universal binary |
| Linux x86_64 | `ubuntu-latest` | gcc |
| Linux arm64 | `ubuntu-latest` (QEMU) or `ubuntu-24.04-arm` | gcc cross |
| iOS | `macos-latest` | Xcode / iOS SDK |
| Android (arm64-v8a) | `ubuntu-latest` | Android NDK via `native_toolchain_c` |
| Windows x64 | — | Deferred (Q4) |
| Web (WASM) | `ubuntu-latest` | Chrome via `dart test --platform chrome` |

Each job runs `dart test` for the native path (or the WASM path on the web
job). A combined matrix job fails the pipeline if any platform regresses.

### VERSION_ZSTD pinning

A `VERSION_ZSTD` file at the repo root (e.g. `1.5.7`) is the single source of
truth for which Zstd C source version is vendored in `third_party/`. The
`hook/build.dart` reads this file at build time and asserts that it matches the
version string embedded in the compiled library (`ZSTD_VERSION_STRING`). This
prevents silent drift between the vendored source and the stated version.

Note: `third_party/zstd/src/zstd.c` is already the amalgamation file — the
version is encoded in `zstd.h` as `ZSTD_VERSION_STRING`. The build hook
assertion can be a simple string comparison at hook run time.

### pub.dev publishing

To remove `publish_to: none` and publish to pub.dev:

1. Remove `publish_to: none` from `pubspec.yaml`.
2. Add a `homepage` / `repository` field pointing to the GitHub repo.
3. Ensure all public API has doc comments (currently good).
4. Run `dart pub publish --dry-run` and resolve any warnings.
5. Tag a `v0.1.0` release on GitHub.

No `dependency_overrides` using `git:` refs are present in `betto_zstd`'s own
`pubspec.yaml` — this is clean.

## Implementation plan

### Phase 1 — WASM compression and decompression (required; unblocks KMDB web sync)

- [ ] Build `third_party/zstd/src/zstd.c` with Emscripten (`emcc -Os -s
  WASM=1 -s EXPORTED_FUNCTIONS=[...]`) to produce `lib/assets/zstd.wasm`;
  document the exact `emcc` invocation in `Makefile` as `make wasm`
- [ ] Check `lib/assets/zstd.wasm` into the repository
- [ ] Refactor `lib/src/zstd_base.dart` → `lib/src/zstd_native.dart` (rename
  only; no API changes)
- [ ] Update `hook/build.dart` `assetName` to reference `zstd_native.dart`
  (required after the rename — the `CBuilder` `assetName` must match the file
  containing `@Native` declarations or the native library will fail to load)
- [ ] Create `lib/src/zstd_web.dart`: `ZstdSimple` implementation that loads
  `lib/assets/zstd.wasm` via `dart:js_interop`'s `WebAssembly.instantiate`,
  manages WASM heap allocation/deallocation explicitly, and exposes both
  `compress()` and `decompress()` (both enabled — frame compatibility is
  guaranteed, see Q2)
- [ ] Create `lib/src/zstd_unsupported.dart`: stub implementation that throws
  `UnsupportedError` (fallback for unsupported platforms / test stub)
- [ ] Update `lib/zstd.dart` to use conditional export
  (`if (dart.library.js_interop) 'src/zstd_web.dart'`)
- [ ] Declare `lib/assets/zstd.wasm` under `flutter: assets:` in `pubspec.yaml`
  (required so Flutter web build bundles the WASM file)
- [ ] Run `dart test --platform chrome` against existing tests on web
- [ ] All existing native tests continue to pass

### Phase 2 — Frame compatibility verification

Frame compatibility between native and WASM is guaranteed by construction
(same source; see Q2), but the golden-file test remains valuable as a
regression guard.

- [ ] Generate golden fixture: compress a fixed payload with native FFI, write
  to `test/fixtures/native_compressed.zst`
- [ ] Write `test/frame_compat_test.dart` with the three scenarios above
  (native→WASM decompress, WASM→native decompress, WASM round-trip)
- [ ] Run frame compat test on native and on Chrome; both compress and
  decompress must pass on web
- [ ] Update README with web support status

### Phase 3 — VERSION_ZSTD pinning

- [ ] Create `VERSION_ZSTD` file at repo root with current vendored version
- [ ] Add version assertion to `hook/build.dart`: read `VERSION_ZSTD`, compare
  with `ZSTD_VERSION_STRING` from `zstd.h`, throw if mismatch
- [ ] Document version-bump procedure in README

### Phase 4 — GitHub Actions CI pipeline

- [ ] Create `.github/workflows/ci.yml` with matrix covering: macOS, Linux
  x86_64, Web (Chrome)
- [ ] Add Android and iOS jobs (require Flutter SDK in the runner; confirm
  `native_toolchain_c` cross-compiles cleanly — resolves Q3)
- [ ] Investigate and resolve Windows MinGW-w64 path (resolves Q4); add Windows
  job or document limitation
- [ ] Pipeline runs `make pre_commit` (license_check + test) on each platform
- [ ] Tag CI as a required status check on the default branch

## Summary

_To be completed after implementation._

## Reviews

### Review 1: 2026-06-09

#### Problem Statement Assessment

The problem is real and correctly scoped. KMDB native clients write
Zstd-compressed SSTable values; a web client that cannot decompress them cannot
participate in a sync pool. The two-tier framing (decompression as
non-deferrable; write-side compression as a go/no-go gate on frame
compatibility) is sound, and the flag-byte prefix design in KMDB's value codec
means falling back to uncompressed writes on web is a safe option that's already
handled.

The secondary concerns (multi-platform CI, `publish_to: none` removal) are
legitimate housekeeping items, but they do not block each other and can be
sequenced independently.

One scope concern: Phase 4 (CI pipeline) includes Android and iOS jobs that
require Flutter SDK in the runner. Given that `betto_zstd` is a pure-Dart
package (see Architecture Fit below), those jobs should be scoped as
integration-test jobs using an external Flutter app (analogous to
`betto_icu`'s `integration_test_app`), not as jobs that treat Flutter SDK as
a build-time requirement of `betto_zstd` itself. The plan's CI table should
make this distinction explicit.

#### Proposed Solution Assessment

**Critical defect: Option A is incompatible with the pure-Dart constraint.**

The plan recommends adding `zstandard` as a `betto_zstd` dependency for the web
implementation path. This is not viable. Confirmed via the pub.dev API: every
package in the `zstandard` federated plugin family declares both
`flutter: sdk: flutter` in `dependencies` and `flutter: ">=3.3.0"` in
`environment`. This includes `zstandard`, `zstandard_web`, and
`zstandard_platform_interface`. Adding any of them to `betto_zstd`'s
`pubspec.yaml` would introduce a Flutter SDK dependency into a package that
must remain pure Dart.

Why this matters: KMDB is a pure-Dart project. `kmdb_ui` is the Flutter layer
and lives in a separate repo. `betto_zstd` is a direct dependency of KMDB
packages, not of `kmdb_ui`. A Flutter SDK dependency in `betto_zstd` would
cascade into KMDB, breaking `dart compile exe` usage and `dart test` on any
runner without Flutter installed.

**Option B (Emscripten) is the correct approach for web.**

Compile `third_party/zstd/src/zstd.c` via Emscripten to a `.wasm` module and
call it from `lib/src/zstd_web.dart` using `dart:js_interop`'s
`WebAssembly.instantiate`. This has no Flutter dependency — `dart:js_interop`
is part of the Dart SDK, not the Flutter SDK. The `betto_icu` package
demonstrates the pattern: `BrowserTokenizer` uses `dart:js_interop` to call
browser-native JS APIs, and `betto_icu` carries no Flutter dependency in its
own `pubspec.yaml`. The same approach applies here, substituting a bundled
`.wasm` blob for the browser's `Intl.Segmenter`.

Advantages over Option A: identical source code guarantees frame compatibility
by construction, eliminating Q2 as an open question for compression. The only
frame-compat question that remains is whether Emscripten's default Wasm memory
model produces byte-identical output to the native FFI path for
`ZSTD_compress()` — which it does, since the Zstd format is deterministic for
a given input and level.

The cost is a one-time Emscripten build step to produce the `.wasm` bundle and
check it into `lib/src/`. This adds a build-time dependency on Emscripten for
maintainers who need to update the WASM blob, but consumers of the package see
only a pre-built asset with no external toolchain requirement.

**`native_toolchain_c` is not a Flutter dependency.**

The plan's CI section mentions "require Flutter SDK in the runner" for Android
and iOS jobs. This is a category error worth clarifying: `native_toolchain_c`
itself has no Flutter dependency (confirmed via pub.dev API). The `CBuilder`
hook runs during `dart build` / `flutter build`. For pure-Dart CI testing,
`dart test` invokes the build hook automatically; Flutter SDK is only needed if
you want to run integration tests inside a Flutter app on a physical device or
simulator. The CI jobs for Android and iOS should be separated into two
concerns: (a) cross-compilation verification via `dart build` with the
appropriate NDK/SDK toolchain, which does not require Flutter; and (b) optional
integration tests inside an `integration_test_app`, which would require Flutter.

**VERSION_ZSTD pinning approach is sound** but incomplete — see Vendored Source
Automation below.

#### Architecture Fit

`betto_zstd` is a pure-Dart library package. Its current `pubspec.yaml` has no
Flutter dependency, and the `hook/build.dart` uses only `code_assets`, `hooks`,
`logging`, and `native_toolchain_c` — all pure Dart. The conditional export
pattern proposed for the web implementation (`if (dart.library.js_interop)`) is
exactly what `betto_icu` uses for `BrowserTokenizer`, and is the correct
idiomatic approach for platform-conditional Dart code.

The `lib/zstd.dart` barrel currently exports via `show ZstdSimple, minCLevel,
maxCLevel`. The plan preserves this API surface on both native and web targets.
The web stub (throwing `UnsupportedError` on construction or per-method) follows
the `betto_icu` stub pattern and should be adopted verbatim.

One structural issue: the build hook references `assetName: 'src/zstd_base.dart'`
but the plan proposes renaming this file to `zstd_native.dart`. The
`assetName` in `CBuilder.library` must match the Dart file that contains the
`@Native` declarations — this rename must be reflected in `hook/build.dart` or
the native library will fail to load at runtime. The plan's Phase 1 checklist
mentions the rename but does not mention updating `hook/build.dart`. This is a
missing implementation step.

#### Risk and Edge Cases

1. **`zstd_web.dart` + WASM memory management.** The Emscripten-compiled Zstd
   module uses its own heap. The Dart wrapper must manage allocation and
   deallocation in WASM memory explicitly, using the module's exported `malloc`
   and `free` (or the Zstd single-file lib's internal allocator). This is more
   involved than the FFI path and must be tested against edge cases (empty
   input, truncated frames, very large inputs exceeding WASM's default heap).

2. **`.wasm` blob size and bundle cost.** The Zstd amalgamation at 51k lines of
   C compiles to a non-trivial WASM binary (typically 200–400 KB before
   Emscripten's `-Os` optimisation). This is acceptable for a desktop/WASM
   Flutter app but should be documented. The plan does not address the bundle
   size question.

3. **VERSION_ZSTD pinning assertion.** The plan proposes reading `VERSION_ZSTD`
   at hook run time and comparing it with `ZSTD_VERSION_STRING` from `zstd.h`.
   `ZSTD_VERSION_STRING` is a preprocessor macro, not a runtime symbol — the
   hook cannot call a compiled function to retrieve it. The comparison must be
   done by parsing the `#define ZSTD_VERSION_MAJOR/MINOR/RELEASE` lines from
   `zstd.h` directly in Dart, or by emitting a small C probe program, or by
   reading the version from the README in `third_party/zstd/README.md` (which
   currently documents the version in prose). Clarify the mechanism; the current
   wording ("compare with `ZSTD_VERSION_STRING` from `zstd.h`") is ambiguous.

4. **Vendored source download is entirely manual.** The `third_party/zstd/README.md`
   documents the manual steps to regenerate the amalgamation using Zstd's
   `create_single_file_library.sh`. There is no `make update_zstd` target, no
   pinned download URL, and no integrity check (e.g. SHA-256 of the downloaded
   tarball). The `betto_icu` package does not vendor C source at all (it links
   against system ICU), so there is no comparable automation pattern in this
   project family to follow. This gap means any Zstd version bump requires a
   developer to manually replicate the steps in the README, with no
   reproducibility guarantee. The plan's Phase 3 mentions `VERSION_ZSTD` but
   does not add a download/update automation target. This should be addressed
   before Phase 3 is considered complete.

5. **`binaries.mk` — untracked file in the working tree.** The git status shows
   `binaries.mk` as an untracked file. It contains a cross-compilation shell
   script that builds Zstd shared libraries via clang, xcrun, and Podman/MinGW.
   This script is for a manual pre-built binary approach that predates
   `native_toolchain_c`. It conflicts with the plan's approach (letting
   `CBuilder` handle compilation). It should either be deleted or explicitly
   excluded. If retained for reference, it should be added to `.gitignore` or
   moved to a `scripts/` directory with a comment explaining its status.

6. **`lib/zstd_base.dart` at the library root.** The file
   `lib/zstd_base.dart` exists at the library root (confirmed by `ls
   lib/`), alongside `lib/zstd.dart` and `lib/src/`. This is unexpected —
   library internals belong under `lib/src/`. The plan does not mention cleaning
   this up. It should be investigated: if it is an artefact of an earlier layout,
   it should be removed or moved before pub.dev publishing (point 4 of Phase 5
   will flag it as a `dart pub publish --dry-run` issue if it exposes unintended
   public API).

#### Recommendations

1. **Replace Option A with Option B as the stated web approach.** Revise the
   "Web/WASM approach" section to remove Option A's recommendation, explain why
   `zstandard` is disqualified (Flutter SDK dependency), and promote Option B as
   the primary path. Q5 (added to Open questions above) captures the decision.

2. **Add a `make update_zstd VERSION=x.y.z` target.** This target should:
   download the Zstd release tarball from GitHub, verify its SHA-256 against a
   pinned value in a `VERSION_ZSTD.sha256` file, run
   `create_single_file_library.sh`, copy output to `third_party/zstd/`, and
   update `VERSION_ZSTD`. The `binaries.mk` Podman pattern is useful precedent
   for the containerised build step. Add this as a Phase 3 implementation task.
   Q6 (added above) captures this.

3. **Fix the `hook/build.dart` assetName in the Phase 1 checklist.** Add an
   explicit step: "Update `hook/build.dart` `assetName` to match the renamed
   `zstd_native.dart`."

4. **Clarify the `VERSION_ZSTD` assertion mechanism.** The build hook must
   parse `#define ZSTD_VERSION_MAJOR/MINOR/RELEASE` from `third_party/zstd/zstd.h`
   rather than comparing a runtime symbol. Update the Phase 3 description
   accordingly.

5. **Investigate and dispose of `lib/zstd_base.dart` at the library root.**
   Either move it under `lib/src/` or delete it before Phase 5.

6. **Disposition `binaries.mk`.** Decide whether it belongs in the repo.
   If not, delete it; if it is a useful reference, move to `scripts/` and add
   a header comment.

The plan is not ready for implementation until Q5 (web back-end replacement
for Option A) is resolved. Q6 (download automation) should be resolved before
Phase 3 is started.

#### Open questions

- [ ] Q5 and Q6 (added to the top-level `## Open questions` section above) are
  the two blocking questions from this review. Q3 and Q4 remain open from the
  original investigation.
