# Release Readiness Review — `betto_zstd` 0.1.0

**Reviewer:** Release Ninja
**Date:** 2026-06-14 (revised after B1/B2/B3 resolution)
**Scope:** Full release-readiness audit of the `betto_zstd` pure-Dart package.
**Verdict (short):** **READY FOR 0.1.0** — for the internal cut consumed by KMDB
via a pinned git ref, and as a credible `0.1.0` (not merely `dev.1`). One
deliberate, documented scope decision (mobile CI automation deferred post-0.1.0)
is the only thing standing between this and a clean public pub.dev publish, and
it is an informed choice, not a gap. See [Verdict](#verdict).

> **Revision note:** This review was first cut against `0.1.0-dev.1` with three
> blockers (B1 WASM CI, B2 mobile CI, B3 `any` constraints). B1 and B3 are now
> **resolved**; B2 has been **deliberately deferred** to a post-0.1.0 release
> with manual local validation accepted as sufficient. The verdict has been
> upgraded from "CONDITIONALLY READY for dev.1 only" to "READY FOR 0.1.0"
> accordingly. The filename retains `0.1.0-dev.1` as the artifact name for this
> release cycle.

---

## Executive Summary

`betto_zstd` is a tight, well-scoped wrapper around the Zstd C library, and the
engineering fundamentals are genuinely good: the same C source feeds both the
native FFI and WASM paths (so frame compatibility is structural, not hoped-for),
native memory is freed in `finally` blocks, the build hook hard-fails on version
drift, and there is a real cross-platform golden-fixture test. `dart analyze` is
clean and the native tests pass.

Since the first cut of this review, the two CI blockers that mattered most have
been closed: **the WASM binary is now rebuilt from source in CI under a pinned
Emscripten and diffed against the committed artifact** (the freshness hole is
gone), and **the three `any` version constraints are now caret-pinned** (the
supply-chain and pub.dev-scoring smell is gone). `.pubignore` has been added, the
`init()` signatures have been unified, the public API `show` list has been
reconciled, the unused buffer-length params have been removed, and a typed
`ZstdException` now backs the error surface.

The one remaining open item — **automated iOS/Android CI** — has been
consciously deferred to a post-0.1.0 release. This is **not** the "unproven
mobile platform" situation the original review flagged. The `make android_test`
and `make ios_test` targets are full integration-test runs against a real
Android emulator and iOS simulator; the developer runs them locally before
pushing, so mobile cross-compilation through `native_toolchain_c` has been
exercised by a human against real devices. What is deferred is the *automation*
of that validation, and the roadmap, spec, and README now describe the situation
honestly. I have reservations about manual-only validation as a long-term
posture (see B2 below), but as a scoped decision for a 0.1.0 with a single,
controlled consumer it is defensible.

---

## Resolved Since First Review

| ID | Issue | Status | Evidence |
|---|---|---|---|
| **B1** | WASM never rebuilt/verified in CI | ✅ **RESOLVED** | `verify-wasm` job in `.github/workflows/ci.yml` reads `EMSCRIPTEN_VERSION` (pinned 6.0.0), sets up emsdk at that version, rebuilds the WASM, and runs `git diff --exit-code lib/assets/zstd.wasm`. `test-web` now `needs: [build, verify-wasm]`, so a stale binary fails the build before any web test runs. |
| **B3** | `any` constraints on 3 runtime + 1 dev dep | ✅ **RESOLVED** | `pubspec.yaml`: `code_assets: ^1.0.0`, `hooks: ^1.0.3`, `logging: ^1.3.0`, `ffigen: ^20.1.1`. No `any` constraints remain. |
| **N2** | No `.pubignore` | ✅ **RESOLVED** | `.pubignore` excludes `integration_test_app/`, `src/`, `docs/`, `test/fixtures/`, `site/`, `coverage/`, `cspell.json`. |
| **N3** | `init()` signatures diverged | ✅ **RESOLVED** | All three now `static Future<void> init({String? wasmUrl})` (native:81, web:152, unsupported:36). A caller writing `init(wasmUrl: ...)` compiles on every platform. |
| **N4** | Spec referenced non-exported consts | ✅ **RESOLVED** | `lib/zstd.dart` exports a clean `show ZstdSimple, minCLevel, maxCLevel` (plus `ZstdException`); the spec's Public API section has been aligned. |
| **N5** | Dead buffer-length constructor params | ✅ **RESOLVED** | No `outputBufferLength` / `inputBufferLength` parameters remain anywhere in `lib/`. |
| **N7** | Bare `Exception` error type | ✅ **RESOLVED** | A typed `ZstdException` (`lib/src/zstd_exception.dart`, exported) now backs all compress/decompress error paths on both native and web. |

| **B2** | iOS/Android have no CI coverage | 🟦 **DEFERRED (post-0.1.0)** — by deliberate decision; see below. |

---

## B2 — Mobile CI automation: deliberately deferred (not a gap)

**Status: 🟦 DEFERRED to post-0.1.0 — informed scope decision, accepted for this release.**

The original review treated iOS/Android as "unproven — no CI, harness exists but
never runs." That framing was wrong in one important respect, and the situation
has now been clarified:

- **`make android_test` and `make ios_test` are not empty shells.** They run the
  full `integration_test_app` suite against a real target:
  - `android_test` (Makefile:48–53): launches the configured Android emulator,
    waits for the device, and runs `flutter test integration_test/zstd_test.dart`
    on `emulator-5554`.
  - `ios_test` (Makefile:59–64): boots the configured iOS simulator, opens
    Simulator, and runs the same integration test on that device.
- **The developer runs these locally before pushing.** Mobile
  cross-compilation through `native_toolchain_c` — the build hook compiling
  `zstd.c` for iOS device/simulator arches and Android ABIs — has therefore been
  exercised against real devices by a human, not merely assumed from a desktop
  build. This is materially different from "never built for mobile."
- **The decision is explicit and documented.** B2 has been moved out of the
  blockers table and into the roadmap's "Deferred (post-0.1.0)" section
  (`docs/roadmap/v0.md`). The spec now states (docs/spec/README.md:399–401):
  *"These tests are run locally via `make android_test` … and `make ios_test` …
  Automated CI coverage for iOS and Android is deferred to a post-0.1.0
  release."* The README's platform table continues to list iOS/Android as
  supported, which is now backed by real (manual) validation rather than an
  untested claim.

**Why this is acceptable for 0.1.0:** the sole consumer is KMDB pulling a pinned
commit; the maintainer controls the cut; and mobile builds have actually been
run, not hoped for. Shipping `0.1.0` on the strength of validated-but-manual
mobile testing is a reasonable risk for a single controlled consumer.

**The risks I am still obliged to name (so the deferral is taken with eyes
open):**

1. **Manual validation is unenforced and invisible to CI.** Nothing in the
   pipeline proves the mobile suite was run before any given commit. A change to
   `hook/build.dart`, a Zstd version bump, or an NDK/Xcode toolchain shift could
   silently break the mobile build, and the only guard is the maintainer
   remembering to run two Makefile targets on a machine with both an Android
   emulator and an iOS simulator configured. The day someone else contributes,
   or the maintainer is rushed, that guard evaporates.
2. **It is environment-dependent and non-reproducible.** The targets hardcode
   emulator/simulator names via `EMULATOR_ANDROID` / `EMULATOR_IOS` and assume a
   local Xcode + Android SDK. There is no record (no log, no artifact) that the
   run happened or what arches it covered. "It passed on my machine" is exactly
   the failure class CI exists to eliminate.
3. **Mobile toolchain regressions are the highest-surprise category.** Of all
   six platforms, iOS/Android native cross-compilation is where this package is
   most exposed to upstream toolchain churn. Deferring *automation* here is the
   deferral with the longest tail of latent risk.

**Recommendation:** Accept the deferral for 0.1.0, but treat mobile CI as the
**first** post-0.1.0 work item, not an open-ended "someday." At minimum, add a
compile-only iOS (`flutter build ios --no-codesign`) + Android
(`flutter build apk`) job on the next cycle; the full emulator/simulator
integration run is the ideal. Until that lands, the maintainer should run
`make android_test` / `make ios_test` on **every** Zstd version bump or change
to `hook/build.dart`, and note in the release that mobile currency is a manual
guarantee.

---

## Remaining Non-Blocking Concerns

These are unchanged from the first review and remain non-blocking for 0.1.0.

### N1 — No CI lock on the WASM `EXPORTED_FUNCTIONS` ↔ Dart interop contract
The Emscripten export list lives in the `Makefile` (`WASM_EXPORTS`) and the
matching `@JS(...)` extern declarations live in `lib/src/zstd_web.dart`. These
must stay in lockstep, but nothing enforces it statically. **Partially
mitigated now:** because `verify-wasm` rebuilds the WASM and `test-web` runs the
Chrome suite against that fresh binary, a rename that breaks instantiation will
now fail CI (it would have been masked by the stale binary before B1). A
cross-reference comment between the two lists is still worth adding.

### N6 — `compress`/`decompress` accept `List<int>` but copy element-by-element
If a caller passes a `List<int>` with values outside 0–255, the high bytes are
silently truncated into the native buffer with no validation. Low risk given
typed-data-first usage; an explicit `RangeError` guard or narrowing to
`Uint8List` would be safer for a library others depend on.

### N8 — `make wasm` rebuild as a release prerequisite
Now largely **superseded by B1's resolution**: `verify-wasm` enforces WASM
currency in CI, so a stale binary can no longer reach a consumer through the
default pipeline. A one-line release-checklist note ("WASM is CI-verified via
`verify-wasm`; rebuild locally with `make wasm` if iterating") closes the loop.

---

## Platform-by-Platform Assessment

| Platform | Build proven in CI? | Tests run in CI? | Notes |
|---|---|---|---|
| **Linux** | ✅ `build` job | ✅ native unit + coverage | Strongest coverage. Reference platform. |
| **macOS** | ✅ `test-macos` | ✅ native unit | Good. Runner is Apple Silicon; x86_64 path is implied, not explicitly matrixed. |
| **Windows** | ✅ `test-windows` | ✅ native unit | Good. The `ZSTD_DLL_EXPORT=1` fix (hook/build.dart) is real and load-bearing; without it FFI throws error 127. Covered by the unit tests on the runner. |
| **iOS** | ⚠️ **local only** | ⚠️ **local only** | `make ios_test` runs the full `integration_test_app` suite on a booted simulator; maintainer runs it before pushing. **Validated manually, not in CI.** Automation deferred post-0.1.0. See B2. |
| **Android** | ⚠️ **local only** | ⚠️ **local only** | `make android_test` runs the full integration suite on a launched emulator; maintainer runs it before pushing. **Validated manually, not in CI.** Automation deferred post-0.1.0. See B2. |
| **Web** | ✅ `verify-wasm` rebuilds + diffs WASM | ✅ Chrome unit tests run against the freshly-verified binary | WASM freshness now enforced (B1 resolved). 4 GiB content-size cap by design. |

**Web-specific design risks (acceptable but document loudly):**
- The 4 GiB cap from `ZSTD_getFrameContentSize32` (i64→i32 truncation in
  `src/zstd_wasm_helpers.c`) means any web frame whose declared content size
  exceeds ~4 GiB throws `ZSTD_CONTENTSIZE_ERROR`. Acceptable for KMDB (payloads
  << 4 GiB) but it is a *silent platform asymmetry*: the same frame that
  decompresses on native can fail on web. This belongs in the README's
  limitations, not just the spec.
- `init()` re-fetches the heap view after every call to survive
  `ALLOW_MEMORY_GROWTH` buffer replacement. This is correct and is the subtle
  bug most WASM wrappers get wrong — good.
- The `wasmUrl` default `'assets/packages/betto_zstd/assets/zstd.wasm'` assumes a
  Flutter asset-serving layout. A non-Flutter Dart web consumer would override
  it. Fine, but undocumented for non-Flutter hosts.

**Native correctness spot-check (passed):** `_getFrameContentSize` is declared
`Uint64` and compared to `-1`/`-2`. On 64-bit Dart, the two's-complement
reinterpretation of `ZSTD_CONTENTSIZE_UNKNOWN`/`ERROR` yields `-1`/`-2`, so this
is correct on all supported 64-bit targets. Not a truncation bug.

---

## Test Coverage Assessment

**What is good:**
- Native tests pass; `dart analyze` clean.
- The matrix hits the right logical cases: empty input, single byte, random
  (incompressible) data, highly compressible data, min/max/just-over/just-under
  compression levels, truncated frames, and unknown-content-size frames. A
  thoughtful set, not metric-padding.
- `frame_compat_test.dart` is the standout: a committed golden fixture
  (`test/fixtures/native_compressed.zst`) generated by the native path and
  decompressed on whatever platform runs the test. With B1 resolved, the Chrome
  run of this test now executes against a CI-verified-current WASM — so the
  cross-platform frame-compat guarantee is now backed end-to-end in automation,
  which it was not at dev.1.
- **Mobile integration tests now genuinely exist and run** (locally):
  `integration_test_app/integration_test/zstd_test.dart` is exercised on real
  Android/iOS targets via the Makefile. The gap is automation, not the tests.

**What is still missing or weak:**
- **The golden cross-platform check is asymmetric.** The committed fixture is
  *native-produced*. There is no committed *WASM-produced* fixture that the
  *native* path must decompress, so "native frames decode on web AND web frames
  decode on native" is only half-tested in the committed fixtures.
- **No test covers `decompress` of a frame whose header lies about content
  size.** Zstd guards this internally, but the wrapper's handling of a mismatched
  `resultSize` is untested.
- **The web `StateError`-before-`init()` path is untested.** `zstd_web.dart`
  throws `StateError` if used before `init()` (the single most likely real-world
  web bug — forgetting to await init), and no test asserts it.
- **The unsupported stub is untested** and unreachable on current Dart targets,
  so coverage tooling never touches it. Low practical risk.
- The ~90.5% native coverage with 4 uncovered lines (compressBound/compress
  failure paths requiring ~4 GB input) is an honest and acceptable gap — those
  paths are genuinely unreachable via the public API.

These are all "nice to have before promoting far past 0.1.0," not blockers.

---

## CI/CD Assessment

**Strengths:**
- Desktop trio (Linux/macOS/Windows) all build and run real tests, gated as
  dependencies of one base `build` job — clean structure.
- **WASM is now rebuilt-from-source and diffed in CI** (`verify-wasm`, pinned
  Emscripten via `EMSCRIPTEN_VERSION`), and `test-web` is gated on it. This was
  the single most important pipeline fix and it is done correctly.
- License headers, formatting, and static analysis enforced in the make targets.
- Coverage generated and uploaded as an artifact.

**Remaining gaps (in priority order):**
1. **No mobile jobs (B2)** — iOS/Android are validated locally but not in CI.
   This is the top post-0.1.0 item. Manual validation is real but unenforced and
   non-reproducible.
2. **No release/publish workflow.** No job runs `dart pub publish --dry-run` or
   validates the package on tag. With B3 and N2 fixed, a dry-run gate would now
   *pass*, which makes it cheap to add and worth having as a regression guard
   against future `any`-constraint or packaging slips.
3. **macOS x86_64 not explicitly matrixed** — `macos-latest` is arm64; if Intel
   Mac support matters to KMDB, it is currently unverified.
4. **No caching** of pub/toolchain — minor, cost/speed only.

The pipeline now catches the regression classes that mattered most (WASM drift,
desktop breakage, dependency-resolution surprises). The one regression class it
does **not** catch is a mobile build break — accepted for 0.1.0 by the B2
deferral.

---

## Verdict

### For the `0.1.0` cut (KMDB consuming a pinned git ref): **READY — GO.**

With B1 (WASM CI freshness) and B3 (version constraints) resolved, and B2
(mobile CI) **deliberately deferred with real local validation in place**, the
package now earns a `0.1.0` rather than a cautious `dev.1`. The original reason
to withhold `0.1.0` was that "supports six platforms" was a claim CI could not
back. That is no longer true for five of six platforms (Linux/macOS/Windows/web
all in CI), and the sixth (iOS/Android, validated locally on real devices) is
documented honestly as having CI automation deferred rather than coverage
absent. This is a defensible, informed posture for a single controlled consumer.

**Conditions carried into the release (all already met or accepted):**
1. ✅ **(B3)** Caret constraints in place.
2. ✅ **(B1)** WASM rebuilt-and-diffed in CI.
3. 🟦 **(B2)** Mobile CI deferred post-0.1.0; manual local validation accepted;
   README/spec/roadmap updated to say so. The maintainer accepts that mobile
   currency is a manual guarantee until the follow-up lands.

### For a public pub.dev publish: **GO with one caveat.**

B1, B2-as-blocker, B3, and N2 — the four things that previously made a public
publish a NO-GO — are resolved or consciously accepted. `dart pub publish
--dry-run` should now pass. The one caveat: a pub.dev audience is broader than
KMDB and cannot run your local Makefile, so the README must state plainly that
**iOS/Android are validated locally but not yet covered by automated CI**. With
that disclosure present (the spec already carries it), a public 0.1.0 is
defensible. I would still prioritise landing mobile CI before a 0.1.x that
attracts external mobile consumers.

### Version recommendation

Promote to **0.1.0**. The platform-coverage and stability promise implied by
dropping the `-dev` suffix is now substantially backed by CI, with the mobile
exception documented rather than hidden.

---

## Recommended Action Plan (prioritised)

**Done — no further action:**
- ~~**[B3]** Pin `code_assets`/`hooks`/`logging`/`ffigen` to `^` constraints.~~ ✅
- ~~**[B1]** Rebuild + `git diff` the WASM in CI under pinned Emscripten.~~ ✅
- ~~**[N2]** Add `.pubignore`.~~ ✅
- ~~**[N3]** Unify `init()` signatures across all three implementations.~~ ✅
- ~~**[N4]** Reconcile the spec's Public API section with the actual `show` list.~~ ✅
- ~~**[N5]** Remove the unused buffer-length constructor params.~~ ✅
- ~~**[N7]** Introduce a typed `ZstdException`.~~ ✅

**Post-0.1.0 follow-ups (in priority order):**
1. **[B2 — TOP POST-0.1.0 ITEM]** Add iOS + Android CI jobs. Compile-only
   minimum (`flutter build ios --no-codesign`, `flutter build apk`); full
   `integration_test_app` emulator/simulator run ideal. Until this lands, run
   `make android_test` / `make ios_test` locally on every Zstd bump or
   `hook/build.dart` change, and note mobile currency as a manual guarantee in
   each release.
2. **[Release process]** Add a `dart pub publish --dry-run` CI gate (now that it
   would pass) to guard against future packaging/constraint regressions.
3. **[Test gap, ~1 hr]** Add: (a) a WASM-produced golden fixture decompressed on
   native; (b) a web `StateError`-before-`init` test; (c) a stub
   `UnsupportedError` test.
4. **[N1]** Add a cross-reference comment linking `WASM_EXPORTS` (Makefile) and
   the `@JS` externs in `zstd_web.dart`.
5. **[Docs]** Document the web-only 4 GiB frame cap and the `wasmUrl` override
   for non-Flutter hosts in the README limitations section.
6. **[Optional]** Matrix macOS x86_64 if Intel Mac support matters to KMDB.
