.DEFAULT_GOAL := all

SOURCE_FILES=lib/**/*.dart
TEST_FILES=test/**/*.dart

DOC_DIR=doc
COVERAGE_DIR=coverage
ADDLICENSE_CONFIG=addlicense_config.txt

# Emscripten exported functions for the WASM build.
# ZSTD_getFrameContentSize32 is from src/zstd_wasm_helpers.c; it wraps the
# original i64-returning function to avoid BigInt requirements in Dart/JS.
WASM_EXPORTS = ['_ZSTD_compress','_ZSTD_decompress','_ZSTD_compressBound','_ZSTD_getFrameContentSize32','_ZSTD_isError','_ZSTD_minCLevel','_ZSTD_maxCLevel','_malloc','_free']

all: license_check format analyze test coverage doc
.PHONY: all

pre_commit: license_check test
.PHONY: pre_commit

prepare:
	dart pub global activate coverage
	dart pub get
.PHONY: prepare

cicd: prepare license_check format analyze test coverage
.PHONY: cicd

cicd_macos: prepare test
.PHONY: cicd_macos

cicd_windows: prepare test
.PHONY: cicd_windows

web_test: prepare
	dart test --platform chrome
.PHONY: web_test

test:
	dart test
.PHONY: test

format:
	dart format lib/ test/ example/
.PHONY: format

analyze:
	dart analyze
.PHONY: analyze

coverage:
	dart run coverage:test_with_coverage --out $(COVERAGE_DIR)
	lcov --remove $(COVERAGE_DIR)/lcov.info 'lib/src/third_party/*' -o $(COVERAGE_DIR)/lcov.info
	genhtml $(COVERAGE_DIR)/lcov.info -o $(COVERAGE_DIR)/html
.PHONY: coverage

license_check:
	@echo "Checking for license headers..."
	cat $(ADDLICENSE_CONFIG) | xargs addlicense --check

license_add:
	cat $(ADDLICENSE_CONFIG) | xargs addlicense

doc:
	dart doc --output=$(DOC_DIR) --validate-links .
.PHONY: doc

clean:
	rm -rf $(DOC_DIR)
	rm -rf $(COVERAGE_DIR)
.PHONY: clean

# Build the Zstd WASM module from source using Emscripten.
#
# Prerequisites: emcc must be on PATH (install via emsdk).
#   https://emscripten.org/docs/getting_started/downloads.html
#
# Output: lib/assets/zstd.wasm — check this file in after running make wasm.
#
# Flags:
#   -Os              Optimise for size (roughly 200–350 KB output).
#   --no-entry       No main() entry point; this is a library module.
#   STANDALONE_WASM  Produce a standalone .wasm without a JS glue file.
#   ALLOW_MEMORY_GROWTH  WASM heap can grow; required for variable-size inputs.
#   FILESYSTEM=0     Disable the Emscripten virtual filesystem (not needed).
#
# If instantiation fails with missing WASI imports, inspect the module with
# `wasm-objdump -x lib/assets/zstd.wasm | grep import` and extend the WASI
# shim in lib/src/zstd_web.dart accordingly.
wasm: third_party/zstd/src/zstd.c src/zstd_wasm_helpers.c
	emcc -Os \
	  --no-entry \
	  -s STANDALONE_WASM=1 \
	  -s "EXPORTED_FUNCTIONS=$(WASM_EXPORTS)" \
	  -s ALLOW_MEMORY_GROWTH=1 \
	  -s FILESYSTEM=0 \
	  -I third_party/zstd \
	  third_party/zstd/src/zstd.c src/zstd_wasm_helpers.c \
	  -o lib/assets/zstd.wasm
.PHONY: wasm
