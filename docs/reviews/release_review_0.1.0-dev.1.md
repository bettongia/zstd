# Release Readiness Review — `betto_zstd` 0.1.0-dev.1

**Reviewer:** Release Ninja
**Date:** 2026-06-14
**Scope:** Full release-readiness audit of the `betto_zstd` pure-Dart package.
**Verdict (short):** **CONDITIONALLY READY** for an internal `dev.1` pre-release
consumed by KMDB via a pinned git ref. **NOT READY** for a public pub.dev
publish. See [Verdict](#verdict).

---

## Executive Summary

`betto_zstd` is a tight, well-scoped wrapper around the Zstd C library. The
engineering fundamentals are genuinely good: the same C source feeds both the
native FFI and WASM paths (so frame compatibility is structural, not hoped-for),
native memory is freed in `finally` blocks, the build hook hard-fails on version
drift, and there is a real cross-platform golden-fixture test. `dart analyze`
is clean and all 20 native tests pass. For a `dev.1` tag whose only consumer is
KMDB pulling a pinned git commit, this is acceptable to ship.

It is **not** ready to be published to pub.dev as-is. The blocking gaps are: the
web/WASM path has **zero automated execution in CI** despite being a first-class
advertised platform; iOS and Android have **no CI coverage at all** (the
integration harness exists but is never run by any workflow); and three runtime
dependencies use `any` version constraints, which is disallowed by pub.dev
scoring and is a supply-chain hazard. None of these are hard to fix, but until
they are, "supports six platforms" is a claim the CI cannot back up.

---

## Blocking Issues

These must be resolved before the package can be considered release-ready for
any audience beyond a single internally-controlled consumer.

### B1 — Web platform is advertised but never tested with a real WASM build in CI
**Severity: 🔴 BLOCKER (for any release claiming web support)**

`.github/workflows/ci.yml` has a `test-web` job (lines 64–78) that runs
`make web_test` → `dart test --platform chrome`. That job depends on
`lib/assets/zstd.wasm` being committed and **current**. But nothing in CI ever
rebuilds the WASM from source (`make wasm` needs Emscripten, which is not
installed in any job). The committed binary (`lib/assets/zstd.wasm`, 324,968
bytes) is therefore trusted blindly:

- If someone bumps `VERSION_ZSTD` and the vendored `zstd.c`, the native build
  hook (`hook/build.dart` `_assertVersionPinned`) will catch the drift and fail.
  **The WASM binary has no equivalent guard.** A contributor can update the C
  source, regenerate native bindings, pass all native + macOS + Windows CI, and
  ship a `zstd.wasm` that is silently stale — or forget to rebuild it entirely.
  Web users would get a different Zstd version than every other platform, and
  the frame-compat golden test on Chrome would be the only thing standing
  between that and production. There is no assertion that the committed WASM was
  built from the current `zstd.c`.

**User impact:** Web users could receive a different/older Zstd than native
users, breaking the "same C source → guaranteed frame compatibility" promise
that the README (lines 4–6, 75–79) and spec stake the design on.

**Fix:** Either (a) build the WASM in CI with `emsdk` (the
`mymindstorm/setup-emscripten` action) and `git diff --exit-code` the result
against the committed binary to prove it is reproducible and current, or (b) add
a hash/version stamp check analogous to `_assertVersionPinned` that fails if the
committed WASM does not correspond to the current `VERSION_ZSTD`. Option (a) is
strongly preferred.

### B2 — iOS and Android have no CI coverage whatsoever
**Severity: 🔴 BLOCKER (for any release claiming mobile support)**

The README (lines 12–13) and spec list iOS and Android as fully supported
("Compress + decompress"). The `integration_test_app/` harness and the
`make android_test` / `make ios_test` targets exist. **No GitHub Actions job
invokes either of them.** `.github/workflows/ci.yml` contains exactly four jobs:
`build` (Linux), `test-macos`, `test-windows`, `test-web`. Mobile is entirely
absent.

This means the native-assets build hook has **never been proven to compile
`zstd.c` for `arm64-ios`, the iOS simulator, or Android ABIs in automation**.
Mobile cross-compilation through `native_toolchain_c` is exactly where toolchain
surprises live (NDK selection, bitcode, simulator vs device arch, minimum OS
deployment target). "It builds on macOS desktop" does not prove "it builds for
an iPhone."

**User impact:** A KMDB mobile build could fail at compile time, or — worse —
link against the wrong arch and fail at runtime, and no CI signal would warn the
team before a user hit it.

**Fix:** Add at least a *build* job for iOS (on `macos-latest`) and Android (the
emulator step, or at minimum `flutter build apk`/`flutter build ios --no-codesign`
of `integration_test_app`). A full emulator run is ideal; a compile-only job is
the non-negotiable minimum.

### B3 — `any` version constraints on three runtime dependencies
**Severity: 🟡 HIGH RISK (🔴 BLOCKER for pub.dev publish)**

`pubspec.yaml` lines 20–22 / 30:

```yaml
code_assets: any
hooks: any
logging: any
ffigen: any   # dev dependency
```

`any` constraints currently resolve to `code_assets 1.0.0`, `hooks 1.0.3`,
`logging 1.3.0`, `ffigen 20.1.1`. The problem:

- pub.dev **penalises packages with `any` constraints** in its scoring and the
  publish validator emits warnings; it is considered a release smell because it
  makes the package's resolution non-reproducible and exposes consumers to
  breaking major bumps.
- `code_assets` / `hooks` are part of the *Native Assets* surface, which is
  still stabilising. An unbounded constraint here means a future breaking 2.0 of
  `hooks` would be pulled into KMDB's resolution with no upper bound, and the
  build hook would break with no warning.
- `pubspec.lock` is **not committed** (`git ls-files pubspec.lock` → not
  tracked). For a package that is consumed as a git dependency this is normal,
  but combined with `any` constraints it means there is no pinned record of what
  actually built and passed.

**Fix:** Pin caret constraints: `code_assets: ^1.0.0`, `hooks: ^1.0.0`,
`logging: ^1.3.0`, `ffigen: ^20.1.1` (match what is resolved and tested). Re-run
`dart pub get` and the full suite to confirm.

---

## Non-Blocking Concerns

### N1 — No CI lock on the WASM `EXPORTED_FUNCTIONS` ↔ Dart interop contract
The Emscripten export list lives in the `Makefile` (`WASM_EXPORTS`, line 19) and
the matching `@JS(...)` extern declarations live in `lib/src/zstd_web.dart`
(lines 66–100). These two lists must stay in lockstep, but nothing enforces it.
If a future export is renamed in one place only, instantiation fails at runtime
in the browser — and because CI does not rebuild the WASM, the failure mode
depends on the stale binary. Worth a comment cross-reference at minimum.

### N2 — `integration_test_app` and 2 MB `zstd.c` inflate any pub.dev publish
`third_party/zstd/src/zstd.c` is ~2 MB and `integration_test_app/` adds 66
tracked files (Android/iOS scaffolding). For a git dependency this is harmless.
For a pub.dev publish it bloats the package and ships a Flutter test app inside a
"pure-Dart" package. Add a `.pubignore` excluding `integration_test_app/`,
`src/`, `docs/`, `test/fixtures/` before any public publish. The vendored
`zstd.c` must stay (it is the build input).

### N3 — `init()` signature differs across the three implementations
- Web: `static Future<void> init({String wasmUrl = '...'})`
- Native: `static Future<void> init()` (no params)
- Unsupported stub: `static Future<void> init()` returning a thrown error
  *synchronously* (`=> throw`, not `async`).

The conditional-export contract only requires the *exported* symbols to be
call-compatible, and `init()` with no args works on all three, so this is not a
breakage today. But a caller who writes `ZstdSimple.init(wasmUrl: ...)` compiles
only on web and silently fails to compile on native. Either add the optional
`wasmUrl` parameter to all three signatures for true uniformity, or document
that `wasmUrl` is web-only. The spec (line 109) shows the web signature as *the*
signature, which is misleading.

### N4 — `defaultLevel`, `maxInputBufferLength`, `zStdVersion` are exported only on native
`lib/zstd.dart` exports `show ZstdSimple, minCLevel, maxCLevel`. The
`defaultLevel` / `maxInputBufferLength` / `zStdVersion` top-level consts in
`zstd_native.dart` (lines 23–29) are **not** in the `show` list and have no
equivalent in `zstd_web.dart`, so they are not part of the public API. That is
the correct call — but the spec's "Public API" section (lines 102–107) references
`defaultLevel` and `maxInputBufferLength` as if they were public. Align the spec
with what is actually exported.

### N5 — `outputBufferLength` / `inputBufferLength` are dead parameters
Both are accepted by every `ZstdSimple` constructor and never used for anything
(the spec admits `outputBufferLength` is "reserved; unused"). On native,
`inputBufferLength` defaults to `ZSTD_BLOCKSIZE_MAX` but is ignored — compress
is single-shot over the whole input. Carrying unused public constructor params
into a `dev.1` API is a future deprecation liability. Consider dropping them now,
while you still can without a breaking change, or document them as reserved.

### N6 — `compress`/`decompress` accept `List<int>` but copy element-by-element
Native `compress` does `srcPtr.asTypedList(srcSize).setAll(0, data)` — fine for a
`Uint8List`, but if a caller passes a `List<int>` containing values outside
0–255 the high bytes are silently truncated into the native buffer with no
validation. Low risk given the typed-data-first usage, but an explicit
`RangeError` guard (or narrowing the signature to `Uint8List`) would be safer
for a library others depend on.

### N7 — Error type is bare `Exception`
Both paths throw `Exception('Zstd ... error: ...')` (string-typed). Consumers
cannot catch a specific `ZstdException` — they must catch `Exception` broadly or
string-match. For a `dev.1` this is tolerable, but a typed exception class is the
kind of API decision that is cheap now and breaking later.

### N8 — `make wasm` is undocumented as a release prerequisite
There is no release checklist that says "rebuild and commit `zstd.wasm` before
tagging." Given B1, the human process is currently the *only* guard on WASM
currency. Add a documented release procedure.

---

## Platform-by-Platform Assessment

| Platform | Build proven in CI? | Tests run in CI? | Notes |
|---|---|---|---|
| **Linux** | ✅ `build` job | ✅ native unit + coverage | Strongest coverage. This is the reference platform. |
| **macOS** | ✅ `test-macos` | ✅ native unit | Good. Runner is Apple Silicon; x86_64 path is implied, not explicitly matrixed. |
| **Windows** | ✅ `test-windows` | ✅ native unit | Good. The `ZSTD_DLL_EXPORT=1` fix (hook/build.dart:40-42) is real and load-bearing; without it FFI throws error 127. Covered by the unit tests running on the runner. |
| **iOS** | ❌ **none** | ❌ **none** | Harness exists (`integration_test_app`), `make ios_test` exists, **no CI job**. Unproven. See B2. |
| **Android** | ❌ **none** | ❌ **none** | Same as iOS. Unproven. See B2. |
| **Web** | ⚠️ uses committed WASM | ✅ Chrome unit tests run, **but against a possibly-stale binary** | No source rebuild in CI; 4 GiB content-size cap by design. See B1. |

**Web-specific design risks (acceptable but document loudly):**
- The 4 GiB cap from `ZSTD_getFrameContentSize32` (i64→i32 truncation in
  `src/zstd_wasm_helpers.c`) means any web frame whose declared content size
  exceeds ~4 GiB throws `ZSTD_CONTENTSIZE_ERROR`. Spec lines 508–510 document
  this. Acceptable for KMDB (payloads << 4 GiB) but it is a *silent platform
  asymmetry*: the same frame that decompresses on native can fail on web. This
  belongs in the README's limitations, not just the spec.
- `init()` re-fetches the heap view after every call to survive
  `ALLOW_MEMORY_GROWTH` buffer replacement (zstd_web.dart:108, 233, 289). This
  is correct and is the subtle bug most WASM wrappers get wrong — good.
- The `wasmUrl` default `'assets/packages/betto_zstd/assets/zstd.wasm'` assumes a
  Flutter asset-serving layout. A non-Flutter Dart web consumer would have to
  override it. Fine, but undocumented for non-Flutter hosts.

**Native correctness spot-check (passed):** `_getFrameContentSize` is declared
`Uint64` and compared to `-1`/`-2` (zstd_native.dart:63-66, 164-170). On a
64-bit Dart `int`, the two's-complement reinterpretation of
`ZSTD_CONTENTSIZE_UNKNOWN`/`ERROR` does yield `-1`/`-2`, so this is correct on
all supported 64-bit targets. Verified indirectly by the passing
"unknown content size" and "invalid frame" tests.

---

## Test Coverage Assessment

**What is good:**
- 20 native tests pass; `dart analyze` clean.
- The test matrix hits the right *logical* cases: empty input, single byte,
  random (incompressible) data, highly compressible data, min/max/just-over/
  just-under compression levels, truncated frames, and unknown-content-size
  frames. This is a thoughtful set, not metric-padding.
- `frame_compat_test.dart` is the standout: a committed golden fixture
  (`test/fixtures/native_compressed.zst`) generated by the native path and
  decompressed on whatever platform runs the test. This is exactly the right way
  to catch native↔WASM frame drift, and it is the de facto guard behind B1.

**What is missing or weak:**
- **The golden cross-platform check is asymmetric.** The committed fixture is
  *native-produced*. There is no committed *WASM-produced* fixture that the
  *native* path must decompress. The claim "native frames decode on web AND web
  frames decode on native" (README:75) is only half-tested. Add a committed
  WASM-generated fixture and decompress it on native.
- **No test covers the `decompress` of a frame larger than the buffer the header
  claims** (i.e. a frame whose header lies about content size). Zstd guards this
  internally, but the wrapper's handling of a mismatched `resultSize` is
  untested.
- **The `init()`-not-awaited `StateError` path on web is untested.**
  `zstd_web.dart` `_assertReady()` (lines 187-194) throws `StateError` if used
  before `init()`. There is no test that calls `compress` before `init` and
  asserts the `StateError`. This is the single most likely real-world web bug
  (forgetting to await init), and it is uncovered.
- **The unsupported stub is entirely untested.** Every member of
  `zstd_unsupported.dart` throws `UnsupportedError`, but no test imports it or
  asserts the failure mode. It is also unreachable on current Dart targets, so
  coverage tooling will never touch it. Low practical risk, but the 90.5% figure
  excludes it from honest accounting.
- The 90.5% native coverage with 4 uncovered lines (compressBound/compress
  failure paths requiring ~4 GB input) is an **honest and acceptable** gap. Those
  paths are genuinely unreachable via the public API. No objection.

**Coverage of *platforms* is the real gap, not coverage of *lines*.** 90.5% line
coverage on Linux says nothing about whether the code runs on an iPhone (B2).

---

## CI/CD Assessment

**Strengths:**
- Desktop trio (Linux/macOS/Windows) all build and run real tests, gated as
  dependencies of one base `build` job — clean structure.
- License headers, formatting, and static analysis are enforced in `make cicd`.
- Coverage is generated and uploaded as an artifact.

**Gaps (in priority order):**
1. **No mobile jobs** (B2) — iOS/Android are unbuilt in CI.
2. **WASM is never rebuilt or verified-current in CI** (B1) — `test-web` trusts a
   checked-in binary with no freshness guard.
3. **No release/publish workflow.** There is no job that runs
   `dart pub publish --dry-run`, validates the package, or tags releases. For a
   package meant to be consumed by other Bettongia repos, a dry-run publish gate
   would catch the `any`-constraint warnings (B3) and the `.pubignore` gap (N2)
   automatically.
4. **No dependency on the integration harness from CI** — `make android_test` /
   `ios_test` are developer-only conveniences with no automation behind them.
5. **macOS x86_64 not explicitly matrixed** — `macos-latest` is arm64; if Intel
   Mac support matters to KMDB, it is currently unverified.
6. **No caching** of pub/toolchain — minor, cost/speed only.

A regression in the WASM path or any mobile build would reach a KMDB consumer
before CI noticed. That is the core deficiency.

---

## Verdict

### For the stated `dev.1` use case (KMDB consuming a pinned git ref): **CONDITIONALLY READY — GO**, with conditions.

The code is correct and well-built on the platforms CI actually exercises
(Linux, macOS, Windows, and web *to the extent the committed WASM is current*).
For an internal `0.1.0-dev.1` pre-release where the only consumer is KMDB pulling
a specific commit, and where the team controls when the WASM is rebuilt, this is
shippable **provided**:

1. **(B3)** Replace the four `any` constraints with caret constraints and re-run
   the suite. This is a 5-minute fix with real supply-chain payoff.
2. **(B1)** Either add the WASM-rebuild-and-diff CI step, *or* — if deferring —
   add a documented, enforced manual step to rebuild `zstd.wasm` on every Zstd
   version bump, and add a `dev.1` release note that the web binary's currency is
   a manual guarantee.
3. **(B2)** Add at minimum a *compile-only* iOS and Android CI job before any
   consumer ships a mobile build. If KMDB is not yet targeting mobile, this can
   be a fast-follow — but the README must then stop claiming iOS/Android are
   supported until CI proves it.

### For a public pub.dev publish: **NO-GO.**

B1, B2, and B3 are all blocking for a public release, plus N2 (`.pubignore`). Do
not run `dart pub publish` until the WASM is CI-verified, mobile is at least
compile-tested, constraints are pinned, and the package contents are trimmed.

### Version recommendation

Keep **0.1.0-dev.1** for the internal cut after B3 is fixed. Do **not** promote
to `0.1.0` (a non-dev release implies a stability and platform-coverage promise
the CI cannot currently back). Promotion to `0.1.0` should be gated on B1 and B2
being resolved so that all six advertised platforms are actually exercised by
automation.

---

## Recommended Action Plan (prioritised)

1. **[B3, 5 min]** Pin `code_assets`, `hooks`, `logging` to `^` constraints in
   `pubspec.yaml`; pin `ffigen`. Re-run `dart test` + `dart analyze`.
2. **[B1, ~half day]** Add an `emsdk` setup step + `make wasm` +
   `git diff --exit-code lib/assets/zstd.wasm` to CI to prove the committed WASM
   is reproducible and current.
3. **[B2, ~half day]** Add iOS + Android build jobs (compile-only minimum; full
   `integration_test_app` emulator run ideal).
4. **[N2, 15 min]** Add `.pubignore` excluding `integration_test_app/`, `src/`,
   `docs/`, `test/fixtures/` ahead of any pub.dev publish.
5. **[Test gap, ~1 hr]** Add: (a) a WASM-produced golden fixture decompressed on
   native; (b) a web `StateError`-before-`init` test; (c) a stub
   `UnsupportedError` test.
6. **[N3/N4, 30 min]** Reconcile `init()` signatures and fix the spec's Public
   API section to match the actual `show` list.
7. **[Release process]** Add a `pub publish --dry-run` CI gate and a documented
   release checklist that mandates a WASM rebuild on every Zstd bump.
8. **[N5–N7, later]** Decide the fate of the unused buffer-length params and the
   bare `Exception` type before promoting past `dev`.
