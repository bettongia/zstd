# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`betto_zstd` is a pure-Dart package that wraps the [Zstandard](https://github.com/facebook/zstd) C library via Dart FFI and the Native Assets build system. It is a dependency of KMDB and must remain a pure-Dart package — no Flutter SDK dependency.

## Commands

```sh
dart test                             # run all tests (native)
dart test test/compression_test.dart  # run a single test file
dart test --platform chrome           # run web/WASM tests (requires Chrome)
dart analyze                          # static analysis
dart format lib/ test/ example/       # format source

make all          # license_check + format + analyze + test + coverage + doc
make pre_commit   # license_check + test (run before committing)
make web_test     # run tests on Chrome (sets up coverage tool first)
make wasm         # rebuild lib/assets/zstd.wasm (requires Emscripten/emcc)
make coverage     # generate HTML coverage report in coverage/html/
make doc          # generate API docs in doc/
make license_add  # add missing Apache 2.0 headers
```

## Architecture

The C library is a vendored single-file amalgamation at `third_party/zstd/src/zstd.c`, produced by Zstd's `create_single_file_library.sh`. Headers live alongside it in `third_party/zstd/`.

The native build hook at `hook/build.dart` uses `native_toolchain_c`'s `CBuilder` to compile `zstd.c` into a dynamic library (`libzstd.dylib` / `.so` / `.dll`) at Dart build time. No pre-built binaries are checked in.

The Dart FFI bindings in `lib/src/zstd_native.dart` use `@Native` annotations to call directly into the compiled library without `dart:ffi` `DynamicLibrary.open`. The generated FFI bindings in `lib/src/third_party/zstd.dart` (produced by `dart run ffigen`) are excluded from analysis and linting.

On web, `lib/src/zstd_web.dart` loads the pre-built `lib/assets/zstd.wasm` module via `dart:js_interop` and exposes the same API. `lib/zstd.dart` selects the implementation via a conditional export (`if (dart.library.js_interop)`). `lib/src/zstd_unsupported.dart` is the fallback stub.

The public API surface exported from `lib/zstd.dart` is:
- `ZstdSimple` — synchronous compress/decompress over `Uint8List`
- `minCLevel()` / `maxCLevel()` — compression level bounds

## FFI bindings regeneration

To regenerate `lib/src/third_party/zstd.dart` after updating the C header:

```sh
dart run ffigen
```

The `ffigen` config in `pubspec.yaml` only exposes the four functions used by the Dart layer (`ZSTD_compress`, `ZSTD_decompress`, `ZSTD_minCLevel`, `ZSTD_maxCLevel`).

## License headers

All `.dart` files (except `analysis_options.yaml`, `pubspec.yaml`, `third_party/**`, `lib/src/third_party/**`, `doc/**`, `coverage/**`) require an Apache 2.0 header. Use `make license_check` to verify and `make license_add` to add missing headers.

## Active plan

No active plan. `plans/completed/` holds the completed pipeline and Windows build plans. `plans/plan_betto_zstd_vendor_automation.md` (Q6 from the pipeline plan) tracks the deferred `make update_zstd` automation work.
