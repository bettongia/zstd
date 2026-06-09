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

import 'dart:typed_data';

import 'package:betto_zstd/zstd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => ZstdSimple.init());

  group('ZstdSimple — native round-trip', () {
    test('compress and decompress returns original bytes', () {
      final zstd = ZstdSimple(level: 3);
      final input = Uint8List.fromList(List.generate(256, (i) => i % 256));
      final compressed = zstd.compress(input);
      final result = zstd.decompress(compressed);
      expect(result, equals(input));
    });

    test('empty input round-trips', () {
      final zstd = ZstdSimple(level: 1);
      final compressed = zstd.compress(Uint8List(0));
      final result = zstd.decompress(compressed);
      expect(result, isEmpty);
    });

    test('compression level bounds are accessible', () {
      expect(minCLevel(), lessThan(0));
      expect(maxCLevel(), greaterThan(0));
    });
  });
}
