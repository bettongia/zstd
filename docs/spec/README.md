---
title: betto_zstd — Technical Specification
toc-title: "Contents"
...

# betto_zstd — Technical Specification

- **Package:** `betto_zstd`
- **Version:** 0.1.0-dev.1
- **Dart SDK:** ^3.12.0
- **Upstream C library:** Zstandard v1.5.7

---

# Purpose and Scope

`betto_zstd` is a pure-Dart package that wraps the
[Zstandard (Zstd)](https://github.com/facebook/zstd) C compression library. It
exposes a single, unified Dart API that works across all Dart and Flutter target
platforms:

- **Native** (macOS, Linux, Windows, iOS, Android) — via Dart FFI and the Native
  Assets build system.
- **Web** — via an Emscripten-compiled WebAssembly (WASM) module loaded at
  runtime with `dart:js_interop`.

The package is a direct dependency of **KMDB** (the Bettongia
knowledge-management database) and must remain a pure-Dart package — it must not
introduce a dependency on the Flutter SDK. The `flutter:` section of
`pubspec.yaml` declares the WASM asset but does not pull in Flutter as a code
dependency; the Dart library itself uses only Dart SDK libraries.

---

# Design Constraints

| Constraint                             | Rationale                                                                                                                                  |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| No Flutter SDK dependency in Dart code | KMDB's core layer is pure Dart; importing Flutter here would force Flutter into every host                                                 |
| Same C source on all platforms         | Frame-format compatibility between native and web is guaranteed by construction — both compile the identical `third_party/zstd/src/zstd.c` |
| Dynamic linking only (native)          | `dart build` CLI bundles the resulting shared library in the output bundle's `lib/` directory; no pre-built binaries checked in            |
| WASM checked in                        | The WASM binary (`lib/assets/zstd.wasm`) is committed so the web path works without Emscripten installed                                   |
| Version pinning enforced at build time | `hook/build.dart` compares `VERSION_ZSTD` against the version macros in `third_party/zstd/zstd.h` and fails the build on a mismatch        |
| WASM currency enforced in CI           | The `verify-wasm` CI job rebuilds `lib/assets/zstd.wasm` under the Emscripten version pinned in `EMSCRIPTEN_VERSION` and asserts the result is bit-for-bit identical to the committed binary, preventing the web path from drifting from the current C source |

---

# Repository Layout

```
betto_zstd/
├── bin/
│   └── dartz.dart                  # CLI tool: compress / decompress files
├── docs/
│   ├── plans/                      # Implementation plans (active and completed)
│   └── spec/                       # This specification document
├── example/
│   └── main.dart                   # Minimal usage example
├── hook/
│   └── build.dart                  # Native Assets build hook
├── lib/
│   ├── zstd.dart                   # Public entry point (conditional export)
│   ├── assets/
│   │   └── zstd.wasm               # Pre-built WASM module (~317 KB, committed)
│   └── src/
│       ├── zstd_native.dart        # Native FFI implementation
│       ├── zstd_web.dart           # Web WASM implementation
│       ├── zstd_unsupported.dart   # Stub for unsupported platforms
│       └── third_party/
│           └── zstd.dart           # Auto-generated ffigen bindings (not linted)
├── src/
│   └── zstd_wasm_helpers.c         # WASM-only C helper (i64 wrapper)
├── test/
│   ├── compression_test.dart       # Unit tests (native and web)
│   ├── frame_compat_test.dart      # Cross-platform frame compatibility tests
│   └── fixtures/
│       └── native_compressed.zst  # Golden fixture for cross-platform check
├── third_party/
│   └── zstd/
│       ├── src/zstd.c              # Single-file amalgamation of Zstd C library
│       ├── zstd.h                  # Zstd public header
│       ├── zdict.h                 # Dictionary API header
│       └── zstd_errors.h           # Error codes header
├── integration_test_app/           # Flutter app used for iOS/Android CI tests
├── .github/workflows/ci.yml        # GitHub Actions CI/CD pipeline
├── Makefile                        # Developer and CI task runner
├── VERSION_ZSTD                    # Single source of truth for vendored version
└── pubspec.yaml                    # Package manifest and ffigen config
```

---

# Public API

The public surface is exported from `lib/zstd.dart` and consists of four
symbols:

## `ZstdSimple`

A synchronous compress/decompress interface over `Uint8List`.

```dart
class ZstdSimple {
  ZstdSimple({int level = 3});  // level defaults to ZSTD_CLEVEL_DEFAULT

  static Future<void> init();   // web: loads WASM; native: no-op
  // On web only, init() also accepts an optional wasmUrl parameter:
  // static Future<void> init({String wasmUrl = '<flutter-asset-path>'});

  String get version;           // Zstd library version string
  Uint8List compress(List<int> data);
  Uint8List decompress(List<int> data);
}
```

**`init()`** must be awaited once before any use on the web platform (it loads
the WASM module). On native platforms it is a synchronous no-op, but callers
should always await it so the same call site works on all platforms. The
optional `wasmUrl` parameter is web-only; it overrides the default Flutter
asset path and is not available on native or unsupported-platform builds.

**`compress()`** allocates the output buffer using `ZSTD_compressBound`,
performs a single-shot compression, and returns the compressed bytes trimmed to
the actual compressed size.

**`decompress()`** reads the original content size from the Zstd frame header
(`ZSTD_getFrameContentSize`), allocates the exact output buffer, decompresses,
and returns the result. It throws if the frame header is invalid or the content
size is unknown (streaming frames are not supported).

## `ZstdException`

Thrown by `compress` and `decompress` when the Zstd library reports an error
or the frame header is invalid. Implements `Exception`, so it is caught by
both `on ZstdException` and `on Exception` clauses.

```dart
class ZstdException implements Exception {
  final String message;
  const ZstdException(this.message);
}
```

## `minCLevel()` / `maxCLevel()`

Top-level functions returning the minimum and maximum compression levels
supported by the underlying library.

| Platform                     | `minCLevel()` | `maxCLevel()` |
| ---------------------------- | ------------- | ------------- |
| Native (via FFI)             | −131072       | 22            |
| Web (compile-time constants) | −131072       | 22            |

---

# Platform Dispatch

`lib/zstd.dart` uses Dart's conditional export mechanism to select the correct
implementation at compile time:

```dart
export 'src/zstd_unsupported.dart'
    if (dart.library.ffi) 'src/zstd_native.dart'
    if (dart.library.js_interop) 'src/zstd_web.dart'
    show ZstdSimple, minCLevel, maxCLevel;
```

The compiler resolves this at build time based on which Dart SDK libraries are
available for the target. The three implementations present identical APIs so
callers never need to handle platform differences.

---

# Native Platform Implementation

**File:** [lib/src/zstd_native.dart](../../lib/src/zstd_native.dart)

## FFI Binding Strategy

The native implementation uses `dart:ffi` `@Native` annotations to declare
direct bindings to the compiled shared library. No `DynamicLibrary.open` call is
required; the Native Assets system (via the build hook) registers the library
with the Dart runtime at build time using the `assetName` declared in
`hook/build.dart`.

The set of native functions called:

| C symbol                                            | Purpose                                                    |
| --------------------------------------------------- | ---------------------------------------------------------- |
| `ZSTD_compressBound(srcSize)`                       | Calculate worst-case compressed size for buffer allocation |
| `ZSTD_compress(dst, dstCap, src, srcSize, level)`   | Single-shot compression                                    |
| `ZSTD_decompress(dst, dstCap, src, compressedSize)` | Single-shot decompression                                  |
| `ZSTD_getFrameContentSize(src, srcSize)`            | Read original size from frame header                       |
| `ZSTD_isError(result)`                              | Check if a Zstd size-or-error return code is an error      |
| `ZSTD_getErrorName(result)`                         | Convert an error code to a human-readable string           |
| `ZSTD_minCLevel()`                                  | Query minimum compression level                            |
| `ZSTD_maxCLevel()`                                  | Query maximum compression level                            |

The generated bindings in `lib/src/third_party/zstd.dart` (produced by
`dart run ffigen`) are present for reference and historical tooling use, but the
active native path uses `@Native` annotations exclusively, which avoid the
`DynamicLibrary` lookup overhead.

## Memory Management

All native memory is allocated via `package:ffi`'s `malloc` allocator and freed
in `finally` blocks to prevent leaks. The pattern for both compress and
decompress is:

1. Allocate source buffer, copy `List<int>` data into it.
2. Allocate destination buffer (sized by `ZSTD_compressBound` or
   `ZSTD_getFrameContentSize`).
3. Call the Zstd C function.
4. Copy the result into a Dart-managed `Uint8List`.
5. Free both native buffers unconditionally in `finally`.

## Build Hook

**File:** [hook/build.dart](../../hook/build.dart)

The Native Assets build hook is invoked automatically during `dart build`,
`flutter build`, and `dart test`. It:

1. Calls `_assertVersionPinned()` — reads `VERSION_ZSTD` and parses
   `ZSTD_VERSION_MAJOR`, `ZSTD_VERSION_MINOR`, `ZSTD_VERSION_RELEASE` from
   `third_party/zstd/zstd.h`; throws if they do not match.
2. Constructs a `CBuilder.library` targeting `third_party/zstd/src/zstd.c` with
   `LinkModePreference.dynamic`.
3. On Windows, defines `ZSTD_DLL_EXPORT=1` so MSVC emits `__declspec(dllexport)`
   for the public symbols (without this, symbols are absent from the import
   table and the FFI resolver throws error 127 at runtime).
4. Routes the output library to the app bundle via `ToAppBundle()`.

---

# Web Platform Implementation

**File:** [lib/src/zstd_web.dart](../../lib/src/zstd_web.dart)

## WASM Module

The WASM module at `lib/assets/zstd.wasm` (~317 KB) is compiled from
`third_party/zstd/src/zstd.c` and `src/zstd_wasm_helpers.c` using Emscripten. It
is checked in so that the web path works without the Emscripten toolchain at
development time. The module is declared as a Flutter asset in `pubspec.yaml`.

Emscripten flags used for the build (`make wasm`):

| Flag                       | Purpose                                     |
| -------------------------- | ------------------------------------------- |
| `-Os`                      | Optimise for size (~317 KB output)          |
| `--no-entry`               | No `main()` — this is a library module      |
| `-s STANDALONE_WASM=1`     | Standalone `.wasm` without a JS glue file   |
| `-s ALLOW_MEMORY_GROWTH=1` | WASM heap can grow for variable-size inputs |
| `-s FILESYSTEM=0`          | Disable the Emscripten virtual filesystem   |

## Initialisation

`ZstdSimple.init()` fetches the WASM binary via the browser `fetch` API,
instantiates it with `WebAssembly.instantiate`, and stores the exported function
table in a module-level `_ZstdExports? _exports` variable. Subsequent calls to
`init()` are no-ops. Calling `compress` or `decompress` before `init()`
completes throws `StateError`.

The WASM module imports exactly one host function:
`env.emscripten_notify_memory_growth(memoryIndex: i32)`, which fires when
`ALLOW_MEMORY_GROWTH` expands the heap. The shim is a no-op because
`lib/src/zstd_web.dart` re-fetches a fresh `Uint8List` view over the WASM linear
memory on every heap access.

## Memory Management

The WASM module exposes `malloc` and `free` from its C runtime. The Dart web
implementation uses these to allocate and free buffers within the WASM linear
memory, following the same allocate/copy/call/copy-out/free pattern as the
native implementation. After any WASM call that may trigger heap growth, the
memory view is re-fetched via `_heap()` to avoid operating on a stale
`ArrayBuffer` reference.

## i64 Interop Workaround

**File:** [src/zstd_wasm_helpers.c](../../src/zstd_wasm_helpers.c)

`ZSTD_getFrameContentSize` returns `unsigned long long` (i64 in 32-bit WASM).
JavaScript `Number` cannot represent arbitrary i64 values without `WASM_BIGINT`,
which would require a more complex interop setup. Instead, `zstd_wasm_helpers.c`
provides `ZSTD_getFrameContentSize32`, which converts the result to `uint32_t`:

- `ZSTD_CONTENTSIZE_UNKNOWN` → `0xFFFFFFFF` (arrives in Dart as −1 via sign
  extension)
- `ZSTD_CONTENTSIZE_ERROR` → `0xFFFFFFFE` (arrives in Dart as −2)
- Values above 4 GiB → treated as `ZSTD_CONTENTSIZE_ERROR`

KMDB payload sizes are well under 4 GiB, so this truncation is safe.

---

# Unsupported Platform Stub

**File:** [lib/src/zstd_unsupported.dart](../../lib/src/zstd_unsupported.dart)

When neither `dart:ffi` nor `dart:js_interop` is available (a scenario that does
not arise in practice with current Dart targets), every public member throws
`UnsupportedError`. This stub ensures the conditional export always resolves to
a valid Dart file.

---

# FFI Bindings Generation

The file `lib/src/third_party/zstd.dart` is auto-generated by `dart run ffigen`
using the configuration in `pubspec.yaml`. The `ffigen` config exposes only the
four functions needed by the original binding approach: `ZSTD_compress`,
`ZSTD_decompress`, `ZSTD_minCLevel`, `ZSTD_maxCLevel`. This file is excluded
from analysis, linting, and license checks.

To regenerate after updating the C header:

```sh
dart run ffigen
```

---

# Vendored C Source

The Zstd C library is vendored as a single-file amalgamation, produced by Zstd's
`create_single_file_library.sh` script:

```
third_party/zstd/
├── src/zstd.c          # Single-file amalgamation (~1.7 MB)
├── zstd.h              # Public API header
├── zdict.h             # Dictionary API header
└── zstd_errors.h       # Error code definitions
```

## Version Tracking

`VERSION_ZSTD` at the repository root is the single source of truth for the
vendored version. The build hook enforces that it matches the version macros
compiled into `zstd.h` at every build.

## Updating the Vendored Version

1. Download the desired Zstd release tarball from the Zstd GitHub releases page.
2. Run `create_single_file_library.sh` from the Zstd source tree.
3. Copy `zstd.h`, `zstd.c`, `zdict.h`, `zstd_errors.h` to `third_party/zstd/`.
4. Update `VERSION_ZSTD` to the new version string (e.g. `1.5.8`).
5. Run `dart run ffigen` to regenerate `lib/src/third_party/zstd.dart`.
6. Run `make wasm` to rebuild `lib/assets/zstd.wasm` (requires Emscripten).
7. Commit all changed files including the updated `zstd.wasm`.

The deferred `make update_zstd` automation (which would script steps 1–4) is
tracked in `docs/plans/plan_betto_zstd_vendor_automation.md`.

---

# Testing

## Unit Tests (`test/compression_test.dart`)

Run on both the native VM and Chrome. Tests cover:

- Round-trip correctness at default, minimum, and maximum compression levels.
- Empty input and single-byte round-trips.
- Invalid compression level → `ArgumentError`.
- Decompressing invalid/truncated data → `Exception`.
- Decompressing a frame with unknown content size (no FCS field) → `Exception`.
- Highly compressible data produces smaller output than input.
- Return type is `Uint8List`.

## Frame Compatibility Test (`test/frame_compat_test.dart`)

Verifies that Zstd frames produced by one platform are decodable by the other:

1. **Round-trip on current platform** — compress and decompress a fixed 1 KB
   payload (`0x00..0xFF` × 4) and assert equality.
2. **Golden fixture check (native only)** — on first run, the native path writes
   `test/fixtures/native_compressed.zst`. On subsequent runs (including on
   Chrome), the fixture is loaded and decompressed; the result must match the
   known payload. This catches any frame-format drift between the native FFI and
   WASM paths.
3. **Web WASM round-trip** — compress and decompress the same payload via the
   WASM path and assert equality and compression ratio.

The golden fixture file is committed to the repository.

## Integration Tests (`integration_test_app/`)

A minimal Flutter application used as a test harness for iOS and Android. It
does not ship as a user-facing app. Tests exercise the native FFI path on a real
device/emulator:

- Round-trip compress/decompress with level 3.
- Empty input round-trip.
- Compression level bounds (`minCLevel()` < 0, `maxCLevel()` > 0).

These tests are run locally via `make android_test` (connected Android
emulator/device) and `make ios_test` (connected iOS simulator/device).
Automated CI coverage for iOS and Android is deferred to a post-0.1.0 release.

## Running Tests

The Makefile is the primary interface for running tests. Do not invoke
`dart test` directly — use the appropriate `make` target so that prerequisites
(dependency fetch, coverage tooling) are handled consistently.

| Target              | What it runs                                                                           |
| ------------------- | -------------------------------------------------------------------------------------- |
| `make test`         | Native unit tests (`dart test`)                                                        |
| `make web_test`     | WASM/web tests on Chrome (`dart test --platform chrome`); installs coverage tool first |
| `make android_test` | Integration tests on a connected Android emulator or device                            |
| `make ios_test`     | Integration tests on a connected iOS simulator or device                               |
| `make pre_commit`   | License check + native tests — run this before every commit                            |
| `make all`          | Full suite: license check, format, analyze, test, coverage, docs                       |

---

# CI/CD Pipeline

**File:** [.github/workflows/ci.yml](../../.github/workflows/ci.yml)

The pipeline runs on every push and pull request to `main`.

| Job            | Runner           | Trigger                       | Steps                                                                                                         |
| -------------- | ---------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `build`        | `ubuntu-latest`  | always                        | `make cicd` — license check, format, analyze, unit tests, coverage                                            |
| `test-macos`   | `macos-latest`   | after `build`                 | `make cicd_macos` — native unit tests on Apple Silicon/x86_64                                                 |
| `test-windows` | `windows-latest` | after `build`                 | `make cicd_windows` — native unit tests via MSVC                                                              |
| `verify-wasm`  | `ubuntu-latest`  | after `build`                 | Rebuilds `lib/assets/zstd.wasm` under the pinned Emscripten version and asserts `git diff --exit-code` is clean |
| `test-web`     | `ubuntu-latest`  | after `build` + `verify-wasm` | `make web_test` — WASM tests on Chrome; only runs after the binary is proven current                          |

Coverage is uploaded as an artifact (`coverage/lcov.info`) from the `build` job.

---

# CLI Tool

**File:** [bin/dartz.dart](../../bin/dartz.dart)

A command-line utility for file compression and decompression:

```sh
dart run bin/dartz.dart <filename>             # compress → <filename>.zst
dart run bin/dartz.dart -d <input.zst> <out>  # decompress
```

Reports original and compressed/decompressed sizes. Writes errors to `stderr`
and exits with code 1 on failure.

---

# Developer Workflow

## Makefile Targets

| Target                | Description                                                           |
| --------------------- | --------------------------------------------------------------------- |
| `make all`            | Full build: license_check → format → analyze → test → coverage → doc  |
| `make pre_commit`     | Pre-commit gate: license_check + test                                 |
| `make cicd`           | CI gate: prepare → license_check → format → analyze → test → coverage |
| `make web_test`       | Run WASM tests on Chrome                                              |
| `make android_test`   | Integration tests on Android emulator                                 |
| `make ios_test`       | Integration tests on iOS simulator                                    |
| `make wasm`           | Rebuild `lib/assets/zstd.wasm` (requires `emcc` on PATH)              |
| `make coverage`       | Generate HTML coverage report in `site/coverage/`                     |
| `make doc`            | Generate API docs in `site/api/`                                      |
| `make site`           | Full documentation site (HTML from Pandoc + API docs + coverage)      |
| `make license_check`  | Verify Apache 2.0 headers on all `.dart` source files                 |
| `make license_add`    | Add missing Apache 2.0 headers                                        |
| `make container_test` | Build and run via Podman/Docker                                       |
| `make clean`          | Remove `site/` and `coverage/`                                        |
| `make purge`          | `clean` + remove `.dart_tool/`                                        |

## License Headers

All `.dart` files under `lib/` and `test/` (except auto-generated files in
`lib/src/third_party/`, generated docs, and coverage output) must carry an
Apache 2.0 header. The `addlicense` tool is configured via
`addlicense_config.txt`.

---

# Dependencies

## Runtime

| Package                      | Purpose                                             |
| ---------------------------- | --------------------------------------------------- |
| `ffi ^2.1.4`                 | `malloc` allocator for native FFI buffer management |
| `native_toolchain_c ^0.17.6` | `CBuilder` — compiles `zstd.c` at build time        |
| `hooks`                      | Native Assets build hook infrastructure             |
| `code_assets`                | Native Assets output type (shared library)          |
| `logging`                    | Structured logging in the build hook                |
| `collection ^1.19.1`         | Utility collections (transitive use)                |

## Dev

| Package        | Purpose                                                 |
| -------------- | ------------------------------------------------------- |
| `test ^1.30.0` | Unit and integration test runner                        |
| `ffigen`       | Generates `lib/src/third_party/zstd.dart` from `zstd.h` |
| `lints ^6.1.0` | Static analysis rule set                                |

---

# Error Handling

| Scenario                                              | Behaviour                                               |
| ----------------------------------------------------- | ------------------------------------------------------- |
| Invalid compression level at construction             | `ArgumentError`                                         |
| Zstd reports a compression or decompression error     | `ZstdException` with the Zstd error name                |
| Frame header is invalid or content size is unknown    | `ZstdException` with a descriptive message              |
| `compress`/`decompress` called before `init()` on web | `StateError`                                            |
| Platform not supported                                | `UnsupportedError` (from stub)                          |
| `VERSION_ZSTD` mismatch at build time                 | Build fails with an `Exception` describing the mismatch |

---

# Known Limitations

- **Single-shot only.** Both the native and web implementations use the simple
  one-shot Zstd API. Streaming compression/decompression (for payloads whose
  uncompressed size is not stored in the frame header, or for very large data)
  is not supported.
- **Web content size cap at 4 GiB.** `ZSTD_getFrameContentSize32` truncates the
  64-bit content size to 32 bits. Decompression of WASM frames larger than ~4 GB
  will fail with `ZSTD_CONTENTSIZE_ERROR`.
- **No dictionary support.** The Zstd dictionary API (`zdict.h`) is vendored but
  not exposed.
