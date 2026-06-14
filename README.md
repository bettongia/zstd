# betto_zstd

A Zstandard (Zstd) compression library for Dart. Supports native platforms via
FFI and the web platform via an Emscripten-compiled WASM module. Both paths
compile the same C source (`third_party/zstd/src/zstd.c`) so frame format
compatibility is guaranteed by construction.

## Platforms

| Platform | Implementation | Status |
|---|---|---|
| macOS, Linux, Windows | Native FFI (`native_toolchain_c`) | Compress + decompress |
| iOS, Android | Native FFI (`native_toolchain_c`) | Compress + decompress |
| Web (Flutter Web) | Emscripten WASM (`dart:js_interop`) | Compress + decompress |

## Getting started

Add `betto_zstd` to your `pubspec.yaml`:

```yaml
dependencies:
  betto_zstd:
    git:
      url: https://github.com/bettongia/zstd.git
```

**Native platforms** require a C compiler available at build time (e.g. `clang`
on macOS/iOS, `gcc` on Linux/Android, MSVC on Windows). The
`native_toolchain_c` build hook compiles `zstd.c` automatically during
`dart build` / `flutter build`.

**Flutter Web** requires `lib/assets/zstd.wasm` to be declared as a Flutter
asset (already done in `pubspec.yaml`) and `ZstdSimple.init()` to be awaited
before first use (see usage below).

## Usage

### Native platforms

```dart
import 'dart:typed_data';
import 'package:betto_zstd/zstd.dart';

void main() async {
  await ZstdSimple.init(); // no-op on native; safe to always call

  final zstd = ZstdSimple(level: 3);
  final data = Uint8List.fromList([1, 2, 3, 4, 5, 1, 2, 3, 4, 5]);

  final compressed = zstd.compress(data);
  final decompressed = zstd.decompress(compressed);
  assert(decompressed.length == data.length);
}
```

### Flutter Web

Call `ZstdSimple.init()` once during app startup — for example in `main()` —
before creating any `ZstdSimple` instance:

```dart
import 'package:betto_zstd/zstd.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ZstdSimple.init(); // loads lib/assets/zstd.wasm
  runApp(const MyApp());
}
```

`ZstdSimple.compress` and `ZstdSimple.decompress` are then synchronous and
safe to call from any context.

Frames produced by the web path are byte-compatible with the native FFI path
and vice versa — both compile the same `third_party/zstd/src/zstd.c` source, so
the Zstd frame format is identical by construction. This is verified by
`test/frame_compat_test.dart`, which runs a golden-file cross-platform check on
every CI run.

### Compression levels

```dart
print('min level: ${minCLevel()}'); // −131072
print('max level: ${maxCLevel()}'); // 22
final zstd = ZstdSimple(level: maxCLevel()); // maximum compression
```

### CLI tool

The package includes `bin/dartz.dart` for compressing and decompressing files:

```bash
dart run bin/dartz.dart myfile.txt            # compress
dart run bin/dartz.dart -d myfile.txt.zst out # decompress
```

## Vendored C source

The Zstd C library is vendored as a single-file amalgamation at
`third_party/zstd/src/zstd.c`, produced by Zstd's
`create_single_file_library.sh` script. The current vendored version is
recorded in `VERSION_ZSTD` at the repository root.

### Bumping the Zstd version

1. Download the desired Zstd release tarball from
   <https://github.com/facebook/zstd/releases>.
2. Run `create_single_file_library.sh` from the Zstd source tree.
3. Copy the output (`zstd.h`, `zstd.c`, `zdict.h`, `zstd_errors.h`) to
   `third_party/zstd/`.
4. Update `VERSION_ZSTD` to the new version string (e.g. `1.5.8`).
5. Run `dart run ffigen` to regenerate `lib/src/third_party/zstd.dart`.
6. Run `make wasm` to rebuild `lib/assets/zstd.wasm` (requires Emscripten).
7. Commit all changed files including the new `zstd.wasm`.

The build hook (`hook/build.dart`) verifies at build time that `VERSION_ZSTD`
matches the version encoded in `third_party/zstd/zstd.h` and fails the build
on a mismatch.

### Rebuilding the WASM module

The pinned Emscripten version is recorded in `EMSCRIPTEN_VERSION` at the
repository root (analogous to `VERSION_ZSTD` for the C library). Always use
that exact version so the rebuilt binary is bit-for-bit identical to the
committed one and the CI `verify-wasm` job passes.

#### Using the Containerfile (recommended)

The `Containerfile` at the repository root installs the pinned Emscripten
version automatically. This is the easiest way to build without polluting your
host environment:

```bash
podman build -t betto-zstd-wasm .
podman run --rm -v "$(pwd)":/work -w /work betto-zstd-wasm make wasm
```

Commit `lib/assets/zstd.wasm` after building.

#### Using a local Emscripten install

Install the exact version from `EMSCRIPTEN_VERSION` via
[emsdk](https://emscripten.org/docs/getting_started/downloads.html), activate
it so `emcc` is on `PATH`, then run:

```bash
make wasm
```

Output: `lib/assets/zstd.wasm` (~317 KB). Commit this file after building.

#### Upgrading the pinned Emscripten version

1. Update `EMSCRIPTEN_VERSION` to the new tagged release (e.g. `6.1.0`).
2. Rebuild the WASM module using the container or local workflow above.
3. Commit both `EMSCRIPTEN_VERSION` and the new `lib/assets/zstd.wasm`.

## Development

```sh
dart test                       # native tests
dart test --platform chrome     # web/WASM tests (requires committed zstd.wasm)
dart analyze
dart format lib/ test/ example/

make all          # license_check + format + analyze + test + coverage + doc
make pre_commit   # license_check + test
make wasm         # rebuild lib/assets/zstd.wasm (needs emcc)
```

## Acknowledgements

This package uses the [Zstandard](https://github.com/facebook/zstd) C library
under the [BSD Licence](https://github.com/facebook/zstd/blob/dev/LICENSE).
See also [third_party/zstd/README.md](third_party/zstd/README.md).
