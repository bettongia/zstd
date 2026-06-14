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

// Stub implementation for platforms where neither dart:ffi nor dart:js_interop
// is available.  Every public member throws [UnsupportedError].

import 'dart:typed_data';

const String _msg = 'betto_zstd is not supported on this platform.';

/// Returns the minimum compression level.
int minCLevel() => throw UnsupportedError(_msg);

/// Returns the maximum compression level.
int maxCLevel() => throw UnsupportedError(_msg);

/// Stub implementation of [ZstdSimple] for unsupported platforms.
class ZstdSimple {
  /// Throws [UnsupportedError] unconditionally.
  ZstdSimple({int level = 3}) {
    throw UnsupportedError(_msg);
  }

  /// Throws [UnsupportedError].
  static Future<void> init() => throw UnsupportedError(_msg);

  /// Throws [UnsupportedError].
  String get version => throw UnsupportedError(_msg);

  /// Throws [UnsupportedError].
  Uint8List compress(List<int> data) => throw UnsupportedError(_msg);

  /// Throws [UnsupportedError].
  Uint8List decompress(List<int> data) => throw UnsupportedError(_msg);
}
