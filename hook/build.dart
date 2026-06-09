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

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Build hook for native assets.
///
/// Compiles the Zstd C library for the target platform.
void main(List<String> args) async {
  await build(args, (input, output) async {
    _assertVersionPinned();

    // Always use dynamic linking. dart build cli bundles the resulting dylib
    // alongside the executable in the output bundle's lib/ directory, so the
    // binary can locate it at runtime without any link-hook step.
    final cBuilder = CBuilder.library(
      name: 'zstd',
      assetName: 'src/zstd_native.dart',
      sources: ['third_party/zstd/src/zstd.c'],
      linkModePreference: LinkModePreference.dynamic,
      // On Windows/MSVC, ZSTDLIB_API only emits __declspec(dllexport) when
      // ZSTD_DLL_EXPORT=1 is defined. Without it the symbols are omitted from
      // the import table and the FFI resolver throws error 127 at runtime.
      defines: {
        if (input.config.code.targetOS == OS.windows) 'ZSTD_DLL_EXPORT': '1',
      },
    );
    await cBuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        ..onRecord.listen((record) => print(record.message)),
      routing: [const ToAppBundle()],
    );
  });
}

/// Verifies that VERSION_ZSTD matches the version encoded in zstd.h.
///
/// Parses ZSTD_VERSION_MAJOR / MINOR / RELEASE from the header and compares
/// with the single-source-of-truth file. Fails the build on a mismatch so
/// silent version drift is impossible.
void _assertVersionPinned() {
  final versionFile = File('VERSION_ZSTD');
  if (!versionFile.existsSync()) return; // file absent → skip (bootstrap)

  final expected = versionFile.readAsStringSync().trim();

  final header = File('third_party/zstd/zstd.h').readAsStringSync();
  final major = RegExp(r'#define ZSTD_VERSION_MAJOR\s+(\d+)').firstMatch(header)?.group(1);
  final minor = RegExp(r'#define ZSTD_VERSION_MINOR\s+(\d+)').firstMatch(header)?.group(1);
  final release = RegExp(r'#define ZSTD_VERSION_RELEASE\s+(\d+)').firstMatch(header)?.group(1);

  if (major == null || minor == null || release == null) {
    throw Exception(
      'Could not parse ZSTD_VERSION_MAJOR/MINOR/RELEASE from '
      'third_party/zstd/zstd.h.',
    );
  }

  final actual = '$major.$minor.$release';
  if (actual != expected) {
    throw Exception(
      'VERSION_ZSTD mismatch: VERSION_ZSTD says "$expected" but '
      'third_party/zstd/zstd.h defines "$actual". '
      'Update VERSION_ZSTD or refresh the vendored source with make update_zstd.',
    );
  }
}
