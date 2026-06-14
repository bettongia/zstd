# betto_zstd: WASM CI freshness check

**Status**: Investigated

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

- [x] **Q1 — Emscripten version selection.** Which version of Emscripten was
  used to produce the currently committed `lib/assets/zstd.wasm`? This must be
  determined (e.g., by checking `emcc --version` output recorded in a past
  commit, or by trying recent versions and comparing the binary) and recorded as
  the initial value of `EMSCRIPTEN_VERSION` before the CI job can be made
  non-flaky.
  _Decision (review 1): The version is unrecoverable from the repository. Git
  history records no `emcc --version` output (the WASM landed in a single commit,
  47cfe91, with no toolchain note), and the binary itself carries no producers /
  toolchain metadata — `-Os` strips it and `strings` finds only Emscripten symbol
  names, not a version. The local toolchain is `emcc 5.0.7-git`, a non-pinnable
  git build, which is almost certainly NOT what produced the June-9 binary.
  Conclusion: the committed binary cannot be reproduced bit-for-bit by any known
  version. The honest fix is to **rebuild the binary once under the most recent
  stable tagged emsdk release, commit that as the new baseline, and record the
  version** — not to reverse-engineer the old one. This makes Q1 a "pick and pin"
  decision, not an archaeology task. Always use the most recent stable tagged
  release available at the time of pinning (never a `-git` build); upgrade
  opportunistically when a newer release is available._
  _Investigation method: add Emscripten to the `Containerfile` at the chosen
  tagged release, build the image, run `make wasm` twice inside the container, and
  check `git diff --exit-code lib/assets/zstd.wasm`. The container gives a clean
  Linux environment matching the CI OS without needing a CI run. The container
  itself is not used in CI; the version is extracted into an `EMSCRIPTEN_VERSION`
  file read by both the `Containerfile` and the CI action._

- [x] **Q2 — Reproducibility of the Emscripten build.**
  _Decision: Verified. `make wasm` run twice inside a fresh container at
  emscripten 6.0.0 produced bit-for-bit identical output both times. Raw
  `git diff --exit-code` is safe — no normalisation step needed. The new
  binary was committed as the reproducible baseline (replacing the old binary
  whose toolchain was unrecoverable)._

- [x] **Q3 — emsdk cache strategy.**
  _Decision: Rely on `mymindstorm/setup-emscripten`'s built-in
  `actions/cache` integration (keyed on the version string from
  `EMSCRIPTEN_VERSION`). No custom cache configuration needed; the action
  handles this out of the box. Acceptable given the gate only runs on pushes
  to main and on PRs._

- [x] **Q4 — Job placement in CI DAG.**
  _Decision: `verify-wasm` is a prerequisite of `test-web` (i.e.
  `test-web` gets `needs: [build, verify-wasm]`). Testing a binary that has
  not been proven current is the exact bug this gate exists to prevent; the
  extra wall-clock time is the correct price. Both jobs still depend on
  `build` so analysis and native tests must pass first._

- [x] **Q5 — `EMSCRIPTEN_VERSION` file location.** Decide between a root-level
  `EMSCRIPTEN_VERSION` file (consistent with `VERSION_ZSTD`) or a comment in
  the Makefile's `wasm:` recipe. The file approach is more explicit and easier
  to grep for in CI.
  _Decision (review 1): Root-level `EMSCRIPTEN_VERSION` file, mirroring the
  existing `VERSION_ZSTD` (6 bytes, at repo root, the single source of truth for
  the native pin). The Makefile `wasm:` recipe should read it (`$(shell cat
  EMSCRIPTEN_VERSION)`) and the CI step should feed it to
  `mymindstorm/setup-emscripten`, so there is exactly one place to change on an
  upgrade. A bare Makefile comment would not be machine-readable by the CI action
  and would drift. If `make wasm` is taught to read the file, also extend the
  N8/`addlicense`-style discipline so the file is documented in the README's
  "Rebuilding the WASM module" section._

## Implementation plan

Prerequisites already done as part of investigation:
- `EMSCRIPTEN_VERSION` file created at repo root (value: `6.0.0`).
- `Containerfile` updated to install emsdk at the version from that file.
- `lib/assets/zstd.wasm` rebuilt under emscripten 6.0.0 and committed as the
  new reproducible baseline.

Remaining steps:

1. **Update `Makefile` `wasm:` comment** — add a note referencing
   `EMSCRIPTEN_VERSION` so developers know where the pin lives, consistent with
   the `VERSION_ZSTD` documentation pattern.

2. **Update `README.md` "Rebuilding the WASM module" section** — document
   `EMSCRIPTEN_VERSION`, the `Containerfile`-based local workflow, and how to
   upgrade the pin (bump `EMSCRIPTEN_VERSION`, rebuild in container, commit new
   binary). Addresses release-review N8.

3. **Add `verify-wasm` job to `.github/workflows/ci.yml`** — on
   `ubuntu-latest`, with `needs: build`. Steps:
   a. `actions/checkout`
   b. `mymindstorm/setup-emscripten` pinned to `$(cat EMSCRIPTEN_VERSION)`
   c. `make wasm`
   d. `git diff --exit-code lib/assets/zstd.wasm`

4. **Update `test-web` job** — add `verify-wasm` to its `needs:` list so it
   only runs after the binary has been proven current.

5. **Update `docs/spec/README.md`** — add a one-line note documenting the WASM
   CI guard alongside the existing note about the native `_assertVersionPinned`
   guard, so the two paths are documented symmetrically.

## Reviews

### Review 1: 2026-06-14

**Problem Statement Assessment**

The problem is real, correctly diagnosed, and worth solving. It is roadmap item
B1 (`docs/roadmap/v0.md`) and a named blocker in
`docs/reviews/release_review_0.1.0-dev.1.md`. I verified the asymmetry the plan
describes: `hook/build.dart::_assertVersionPinned` guards the native path by
parsing `ZSTD_VERSION_*` from `third_party/zstd/zstd.h` against `VERSION_ZSTD`,
while the WASM path has no equivalent. The `test-web` job
(`.github/workflows/ci.yml:64`) runs `make web_test` against the committed
`lib/assets/zstd.wasm` and never rebuilds it, so it cannot detect staleness. The
spec stakes the design on this: `docs/spec/README.md:40` claims frame
compatibility is "guaranteed by construction" because both paths compile the
identical `zstd.c` — a claim that is only true if the committed WASM actually
tracks the C source. So the problem statement is accurate and the motivation is
well-grounded. Good.

One sharpening: the real risk is narrower and more concrete than "version
drift". `zstd.c` is a generated amalgamation, and the WASM also depends on
`src/zstd_wasm_helpers.c`, the `WASM_EXPORTS` list in the `Makefile`, and the
`emcc` flags. A guard keyed only on `VERSION_ZSTD` (the release-review's option
(b)) would miss a helpers-only or flags-only change. The plan's rebuild-and-diff
(option (a)) is the stronger guard precisely because it is sensitive to all of
these inputs — that is the right reason to prefer it, and it should be stated as
the justification.

**Proposed Solution Assessment**

Rebuild-and-`git diff --exit-code` is the correct shape of solution and is
clearly preferred over the in-binary version stamp (the stamp catches version
but not flags/helpers/export drift, and needs Dart changes — the plan already
says this). Strengths: it reuses the existing `make wasm` recipe verbatim, adds
no production code, and proves currency + reproducibility together.

The serious weakness is that the entire approach rests on an **unproven
premise: that the Emscripten build is bit-for-bit reproducible**. If it is not,
`git diff --exit-code` produces false failures on every run and the gate is
worthless. The plan acknowledges this in Q2, but Q2 is listed as an investigation
item rather than treated as the load-bearing risk it is. My investigation makes
this worse, not better (see Q1 below): the committed binary's toolchain is
unrecoverable, and the only local toolchain is `emcc 5.0.7-git` — a moving git
build, not a pinnable release. So there is no version that reproduces the current
binary, and step 3 (`git diff` against the committed file) **cannot pass today**
regardless of which release you pin. The plan must therefore include, as step 0,
"rebuild the baseline under the chosen pinned release and commit it" — otherwise
the very first CI run red-fails.

**Architecture Fit**

Fits well. It mirrors the established `VERSION_ZSTD` single-source-of-truth
pattern with an analogous `EMSCRIPTEN_VERSION` file (Q5), keeps the native and
web guards conceptually parallel, and touches only CI + Makefile + a root pin
file — no `lib/` structure, storage, domain models, or public API surface. The
library-architecture layering is untouched (this is a pure-Dart package with no
Flutter UI; the design / inclusivity skills do not apply). No spec contradiction:
on the contrary, the change makes `docs/spec/README.md:40` honest rather than
aspirational. The spec does not currently describe a WASM CI guard, so the
implementation plan should add a one-line spec note (analogous to the line
documenting the `hook/build.dart` native pin at `docs/spec/README.md:43`) so the
two guards are documented symmetrically.

**Risk & Edge Cases**

- **Non-reproducible builds (highest risk).** Emscripten/`wasm-ld` can embed a
  `producers` custom section and other toolchain-dependent bytes; output can vary
  across patch releases and across `-git` builds. If any of this is
  non-deterministic, raw `git diff` flakes. Mitigation the plan should commit to
  up front, not defer: pin an exact tagged release (never `-git`), and if needed
  post-process with `wasm-strip` / strip the `producers` section, then compare.
  Comparing a normalised SHA-256 instead of raw bytes is a reasonable fallback,
  but only after confirming determinism — a hash of non-deterministic output is
  just a flaky diff with extra steps.
- **emsdk install cost / caching (Q3).** Real but secondary. ~1–2 GB SDK; rely on
  the action's `actions/cache` integration. Acceptable.
- **Toolchain availability over time.** Pinning a specific emsdk release guards
  reproducibility but means CI breaks if that release is ever pulled. Tagged
  releases are durable; `-git` builds are not — another reason to pin a tag.
- **Export-contract drift (release-review N1).** Out of scope here but adjacent:
  a `WASM_EXPORTS` change that breaks the Dart interop would now at least force a
  rebuild+diff, surfacing the change for review. Worth a sentence noting the
  partial overlap.

**Recommendations**

1. Reframe Q1 from "discover the old version" to "choose and pin a release,
   rebuild the baseline, commit it." The old version is gone (see Q1 note). This
   is the single biggest change to the plan and unblocks everything else.
2. Make Q2 (reproducibility) a hard prerequisite with an explicit acceptance
   test: under the pinned release, `make wasm && git diff --exit-code` must be
   clean across two consecutive local runs *and* on Linux CI (the binary may
   differ between a macOS-built baseline and a Linux CI rebuild — build the
   committed baseline on the same OS the CI job uses, i.e. `ubuntu-latest`).
3. Adopt the root-level `EMSCRIPTEN_VERSION` file (Q5) and have both `make wasm`
   and the CI action read it.
4. For Q4: make `verify-wasm` a prerequisite of `test-web`. Testing a binary you
   have not proven current is the bug this plan exists to kill; the extra
   wall-clock is the correct price. Keep both jobs `needs: build`.
5. Add to the implementation plan: a one-line spec note in `docs/spec/README.md`
   documenting the WASM guard, and a README update to "Rebuilding the WASM
   module" describing `EMSCRIPTEN_VERSION` (addresses release-review N8).
6. Do not pursue the in-binary version stamp as the primary mechanism. The plan
   already reaches this conclusion — keep it.

The plan is well-reasoned and headed in the right direction. It is **not yet
ready for implementation** because Q2 (reproducibility) is unproven and Q1's
resolution changes the shape of the work (baseline rebuild becomes step 0).
Resolve the two questions below and it can move to Investigated.

**Open questions**

- [x] **R1.1 — Confirm reproducibility under the most recent tagged release.**
  _Done. Emscripten 6.0.0 (latest stable tag as of 2026-06-14) added to
  `Containerfile`. Image built; `make wasm` run twice inside it; both runs
  produced bit-for-bit identical output. `EMSCRIPTEN_VERSION` file created
  at repo root. New WASM binary committed as the reproducible baseline._
- [x] **R1.2 — Confirm the baseline-rebuild step is in scope.** Confirmed:
  rebuilding and committing a fresh `lib/assets/zstd.wasm` is acceptable. The
  current binary's toolchain is unrecoverable, so a new baseline under a pinned
  release is the correct fix. Frame-format stability means changing the committed
  bytes is harmless.

## Summary

_To be completed after implementation._
