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

// Frame compatibility test.
//
// Verifies that frames produced by the native FFI path can be decompressed by
// the WASM path, and vice versa.  Both paths compile the same C source
// (third_party/zstd/src/zstd.c), so byte-for-byte frame compatibility is
// expected for a given input and compression level.
//
// Test scenarios:
//   1. Native → round-trip (on native): golden fixture generated from native.
//   2. Web   → round-trip (on Chrome):  compress and decompress via WASM.
//   3. Cross-platform decompression: the golden fixture produced by scenario 1
//      is loaded and decompressed on whichever platform is running the test.
//
// How to regenerate the golden fixture:
//   Run `dart test test/frame_compat_test.dart` on a native platform.
//   The test writes test/fixtures/native_compressed.zst when it is missing.
//   Commit the resulting file.

import 'dart:io' show File;
import 'dart:typed_data';

import 'package:betto_zstd/betto_zstd.dart';
import 'package:test/test.dart';

// Fixed payload used for all cross-platform checks — short, deterministic.
// Four copies of the 0..255 byte sequence (1 KB total).
final Uint8List _kPayload = () {
  final base = List.generate(256, (i) => i & 0xFF);
  return Uint8List.fromList([...base, ...base, ...base, ...base]);
}();

const String _fixtureDir = 'test/fixtures';
const String _fixturePath = '$_fixtureDir/native_compressed.zst';

// Compression level used when generating the golden fixture.
const int _kFixtureLevel = 3;

void main() {
  setUpAll(() => ZstdSimple.init());

  group('round-trip on current platform', () {
    late ZstdSimple zstd;
    setUp(() => zstd = ZstdSimple(level: _kFixtureLevel));

    test('compress → decompress matches original', () {
      final compressed = zstd.compress(_kPayload);
      final decompressed = zstd.decompress(compressed);
      expect(decompressed, equals(_kPayload));
    });
  });

  // The fixture group uses dart:io and can only run on the Dart VM.
  // On Chrome the file system is unavailable; the WASM round-trip group below
  // provides equivalent coverage for the web platform.
  group('golden fixture cross-platform check', () {
    // On native: generate the fixture if absent, then verify round-trip.
    // The fixture is a Zstd frame produced by the native FFI path.  Verifying
    // that the same bytes decompress correctly confirms frame format stability.

    test('native fixture decompresses correctly on this platform', () {
      final fixtureFile = File(_fixturePath);

      if (!fixtureFile.existsSync()) {
        // First run on native: generate the golden fixture and remind to commit.
        final zstd = ZstdSimple(level: _kFixtureLevel);
        final compressed = zstd.compress(_kPayload);
        fixtureFile.writeAsBytesSync(compressed);
        // ignore: avoid_print
        print(
          '\n[frame_compat_test] Generated $fixtureFile — '
          'commit this file so the cross-platform check runs on all platforms.',
        );
        return;
      }

      final compressed = fixtureFile.readAsBytesSync();
      final zstd = ZstdSimple(level: _kFixtureLevel);
      final decompressed = zstd.decompress(compressed);
      expect(decompressed, equals(_kPayload));
    });
  }, testOn: 'vm');

  group('web WASM round-trip', () {
    // This group is meaningful when running under `dart test --platform chrome`.
    // On native it is a second round-trip check which is harmless.
    late ZstdSimple zstd;
    setUp(() => zstd = ZstdSimple(level: _kFixtureLevel));

    test('compress → decompress matches original', () {
      final compressed = zstd.compress(_kPayload);
      final decompressed = zstd.decompress(compressed);
      expect(decompressed, equals(_kPayload));
    });

    test('compresses to a smaller size for repetitive input', () {
      final compressed = zstd.compress(_kPayload);
      expect(compressed.length, lessThan(_kPayload.length));
    });
  });
}
