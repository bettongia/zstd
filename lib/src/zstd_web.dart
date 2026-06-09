// Copyright 2026 The Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Web implementation of betto_zstd using an Emscripten-compiled WASM module.
// The module is compiled from third_party/zstd/src/zstd.c + src/zstd_wasm_helpers.c
// via `make wasm` and checked in at lib/assets/zstd.wasm.
//
// dart:js_interop is a Dart SDK library — no Flutter or external dependency is
// introduced by this file.

// ignore_for_file: avoid_js_rounded_ints

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

// Zstd level bounds — fixed by the Zstd specification, match the compiled WASM.
const int _kMinCLevel = -131072;
const int _kMaxCLevel = 22;
const int _kDefaultLevel = 3;

// ZSTD_BLOCKSIZE_MAX = 131072 * 31; retained for API parity with native impl.
const int _kMaxInputBufferLength = 4064256;

// Zstd version matching third_party/zstd/zstd.h (MAJOR.MINOR.RELEASE).
const String _kVersion = '1.5.7';

// ---------- JS / WebAssembly interop declarations ----------

@JS('fetch')
external JSPromise<_JsFetchResponse> _fetch(JSString url);

extension type _JsFetchResponse._(JSObject _) implements JSObject {
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

@JS('WebAssembly.instantiate')
external JSPromise<_WasmInstResult> _wasmInstantiate(
  JSArrayBuffer buffer, [
  JSObject? imports,
]);

extension type _WasmInstResult._(JSObject _) implements JSObject {
  external _WasmInstance get instance;
}

extension type _WasmInstance._(JSObject _) implements JSObject {
  external _ZstdExports get exports;
}

extension type _WasmMemory._(JSObject _) implements JSObject {
  external JSArrayBuffer get buffer;
}

extension type _ZstdExports._(JSObject _) implements JSObject {
  external _WasmMemory get memory;

  external JSNumber malloc(JSNumber size);
  external void free(JSNumber ptr);

  @JS('ZSTD_compress')
  external JSNumber zstdCompress(
    JSNumber dst,
    JSNumber dstCapacity,
    JSNumber src,
    JSNumber srcSize,
    JSNumber compressionLevel,
  );

  @JS('ZSTD_decompress')
  external JSNumber zstdDecompress(
    JSNumber dst,
    JSNumber dstCapacity,
    JSNumber src,
    JSNumber srcSize,
  );

  @JS('ZSTD_compressBound')
  external JSNumber zstdCompressBound(JSNumber srcSize);

  // zstd_wasm_helpers.c provides a 32-bit wrapper that avoids the i64 interop
  // issue: ZSTD_getFrameContentSize returns unsigned long long (i64 in WASM),
  // which is not directly representable as a JS number without WASM_BIGINT.
  @JS('ZSTD_getFrameContentSize32')
  external JSNumber zstdGetFrameContentSize32(JSNumber src, JSNumber srcSize);

  @JS('ZSTD_isError')
  external JSNumber zstdIsError(JSNumber result);
}

// ---------- Global WASM state ----------

_ZstdExports? _exports;

// Returns a fresh Uint8List view over the WASM linear memory.
// Must be re-fetched after any WASM call that may trigger memory growth.
Uint8List _heap() => _exports!.memory.buffer.toDart.asUint8List();

int _malloc(int size) => _exports!.malloc(size.toJS).toDartDouble.toInt();

void _free(int ptr) => _exports!.free(ptr.toJS);

// ---------- Top-level API (matches zstd_native.dart) ----------

/// Returns the minimum compression level supported on the web platform.
///
/// This is the Zstd specification minimum (−131072) and matches the value
/// returned by the native FFI path.
int minCLevel() => _kMinCLevel;

/// Returns the maximum compression level supported on the web platform.
///
/// This is the Zstd specification maximum (22) and matches the value returned
/// by the native FFI path.
int maxCLevel() => _kMaxCLevel;

/// A simple interface for Zstd compression and decompression on the web.
///
/// Call [ZstdSimple.init] and await the result before creating instances.
/// On native platforms [init] is a no-op; on the web it loads the WASM module.
class ZstdSimple {
  /// The compression level to use (default: 3).
  final int level;

  /// The input buffer length (unused on web; retained for API parity).
  final int inputBufferLength;

  /// The output buffer length (unused on web; retained for API parity).
  final int outputBufferLength;

  /// Creates a new [ZstdSimple] instance with the given [level].
  ///
  /// Throws [ArgumentError] if [level] is outside [minCLevel]..[maxCLevel].
  ZstdSimple({
    this.level = _kDefaultLevel,
    this.inputBufferLength = _kMaxInputBufferLength,
    this.outputBufferLength = -1,
  }) {
    if (level < _kMinCLevel || level > _kMaxCLevel) {
      throw ArgumentError.value(level, 'level', 'Invalid compression level');
    }
  }

  /// Loads and initialises the Zstd WASM module.
  ///
  /// Must be awaited once before any [ZstdSimple] method is called on the web
  /// platform. Subsequent calls are no-ops. Calling [compress] or [decompress]
  /// before [init] completes throws a [StateError].
  ///
  /// [wasmUrl] defaults to the Flutter asset path for the `betto_zstd`
  /// package. Override only when serving the WASM from a custom location.
  static Future<void> init({
    String wasmUrl = 'assets/packages/betto_zstd/assets/zstd.wasm',
  }) async {
    if (_exports != null) return;

    final response = await _fetch(wasmUrl.toJS).toDart;
    final buffer = await response.arrayBuffer().toDart;

    // The compiled WASM imports exactly one function:
    //   env.emscripten_notify_memory_growth(memoryIndex: i32)
    // This callback fires when ALLOW_MEMORY_GROWTH causes the heap to expand.
    // We re-fetch the memory view on every heap access, so no tracking needed.
    final envShim = JSObject();
    envShim['emscripten_notify_memory_growth'] = ((JSNumber _) {}).toJS;
    final imports = JSObject();
    imports['env'] = envShim;

    final result = await _wasmInstantiate(buffer, imports).toDart;
    _exports = result.instance.exports;
  }

  /// Returns the Zstd library version string.
  String get version => _kVersion;

  void _assertReady() {
    if (_exports == null) {
      throw StateError(
        'ZstdSimple.init() must be awaited before compressing or '
        'decompressing on the web platform.',
      );
    }
  }

  /// Compresses [data] and returns the compressed bytes.
  ///
  /// Throws [StateError] if [ZstdSimple.init] has not been awaited.
  /// Throws [Exception] if the Zstd library reports an error.
  Uint8List compress(List<int> data) {
    _assertReady();
    final e = _exports!;
    final srcSize = data.length;

    final dstCapacity = e.zstdCompressBound(srcSize.toJS).toDartDouble.toInt();
    if (e.zstdIsError(dstCapacity.toJS).toDartDouble.toInt() != 0) {
      throw Exception('Zstd compressBound failed (code $dstCapacity)');
    }

    final srcPtr = _malloc(srcSize);
    try {
      // Write input into WASM heap (view captured after all mallocs).
      _heap().setAll(srcPtr, data);

      final dstPtr = _malloc(dstCapacity);
      try {
        final compressed = e
            .zstdCompress(
              dstPtr.toJS,
              dstCapacity.toJS,
              srcPtr.toJS,
              srcSize.toJS,
              level.toJS,
            )
            .toDartDouble
            .toInt();

        if (e.zstdIsError(compressed.toJS).toDartDouble.toInt() != 0) {
          throw Exception('Zstd compression error (code $compressed)');
        }

        // Re-fetch heap view: ALLOW_MEMORY_GROWTH may have replaced the buffer.
        return Uint8List.fromList(_heap().sublist(dstPtr, dstPtr + compressed));
      } finally {
        _free(dstPtr);
      }
    } finally {
      _free(srcPtr);
    }
  }

  /// Decompresses [data] and returns the original bytes.
  ///
  /// Throws [StateError] if [ZstdSimple.init] has not been awaited.
  /// Throws [Exception] if the frame is invalid or the Zstd library errors.
  Uint8List decompress(List<int> data) {
    _assertReady();
    final e = _exports!;
    final compressedSize = data.length;

    final srcPtr = _malloc(compressedSize);
    try {
      _heap().setAll(srcPtr, data);

      // ZSTD_getFrameContentSize32 maps ZSTD_CONTENTSIZE_UNKNOWN  → 0xFFFFFFFF
      // and ZSTD_CONTENTSIZE_ERROR → 0xFFFFFFFE.  WASM i32 is sign-extended to
      // JS Number, so these arrive as −1 and −2 respectively.
      final decompressedSize = e
          .zstdGetFrameContentSize32(srcPtr.toJS, compressedSize.toJS)
          .toDartDouble
          .toInt();

      if (decompressedSize == -1) {
        throw Exception(
          'Zstd decompression error: Unknown content size. '
          'Use streaming API.',
        );
      }
      if (decompressedSize == -2) {
        throw Exception('Zstd decompression error: Invalid frame header.');
      }

      final dstPtr = _malloc(decompressedSize);
      try {
        final resultSize = e
            .zstdDecompress(
              dstPtr.toJS,
              decompressedSize.toJS,
              srcPtr.toJS,
              compressedSize.toJS,
            )
            .toDartDouble
            .toInt();

        if (e.zstdIsError(resultSize.toJS).toDartDouble.toInt() != 0) {
          throw Exception('Zstd decompression error (code $resultSize)');
        }

        return Uint8List.fromList(_heap().sublist(dstPtr, dstPtr + resultSize));
      } finally {
        _free(dstPtr);
      }
    } finally {
      _free(srcPtr);
    }
  }
}
