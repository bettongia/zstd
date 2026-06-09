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

// WASM-only helpers compiled alongside zstd.c by `make wasm`.
// These are NOT included in the native build (hook/build.dart).
//
// Rationale: ZSTD_getFrameContentSize returns unsigned long long (i64 in
// 32-bit WASM), which cannot be passed directly to JavaScript as a Number
// without enabling WASM_BIGINT.  The wrapper below converts the result to
// a uint32_t value that JavaScript / Dart can consume without BigInt:
//
//   0xFFFFFFFF  →  ZSTD_CONTENTSIZE_UNKNOWN
//   0xFFFFFFFE  →  ZSTD_CONTENTSIZE_ERROR  (also used for overflow >4 GB)
//
// KMDB payload sizes are well under 4 GB so the truncation is safe.

#include "../third_party/zstd/zstd.h"
#include <stdint.h>

uint32_t ZSTD_getFrameContentSize32(const void* src, size_t srcSize) {
  unsigned long long result = ZSTD_getFrameContentSize(src, srcSize);
  if (result == ZSTD_CONTENTSIZE_UNKNOWN) return 0xFFFFFFFFU;
  if (result == ZSTD_CONTENTSIZE_ERROR)   return 0xFFFFFFFEU;
  if (result > 0xFFFFFFFDULL)             return 0xFFFFFFFEU;
  return (uint32_t)result;
}
