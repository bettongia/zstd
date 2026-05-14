.DEFAULT_GOAL := default

SOURCE_FILES=lib/**/*.dart
TEST_FILES=test/**/*.dart

DOC_DIR=doc
COVERAGE_DIR=coverage
ADDLICENSE_CONFIG=addlicense_config.txt

default: lib/src/third_party/zstd.dart license_check test coverage doc
.PHONY: all

lib/src/third_party/zstd.dart: third_party/zstd/zstd.h third_party/zstd/zdict.h third_party/zstd/zstd_errors.h
	dart run ffigen

third_party/zstd/zstd.h:

third_party/zstd/zdict.h:

third_party/zstd/zstd_errors.h:

test:
	dart test
.PHONY: test

license_check: $(TEST_FILES) $(SOURCE_FILES)
	@echo "Checking for license headers..."
	cat $(ADDLICENSE_CONFIG) | xargs addlicense --check

license_add: $(TEST_FILES) $(SOURCE_FILES)
	cat $(ADDLICENSE_CONFIG) | xargs addlicense

doc: $(TEST_FILES) $(SOURCE_FILES) $(DOC_DIR)/
.PHONY: doc

$(DOC_DIR)/: $(TEST_FILES) $(SOURCE_FILES)
	dart doc --output=$(DOC_DIR) --validate-links .
.PHONY: doc

$(COVERAGE_DIR)/: $(TEST_FILES) $(SOURCE_FILES)
	dart run coverage:test_with_coverage --out $(COVERAGE_DIR)
	lcov --summary $(COVERAGE_DIR)/lcov.info
	genhtml $(COVERAGE_DIR)/lcov.info -o $(COVERAGE_DIR)/html

clean:
	rm -rf $(DOC_DIR)
	rm -rf $(COVERAGE_DIR)
.PHONY: clean
