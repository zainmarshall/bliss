#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
PASS=0
FAIL=0

echo "==============================="
echo " bliss test suite"
echo "==============================="

# ---- C++ tests ----
echo ""
echo "[1/2] C++ unit tests"
echo "-------------------------------"

cmake -S "${ROOT_DIR}" -B "${BUILD_DIR}" >/dev/null 2>&1
cmake --build "${BUILD_DIR}" --target test_hosts_block 2>&1 | grep -v "^--\|^Build\|^\[" || true

if "${BUILD_DIR}/test_hosts_block"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# ---- Swift tests ----
echo ""
echo "[2/2] Swift unit tests"
echo "-------------------------------"

SWIFT_TEST_BIN="/tmp/bliss_swift_tests"

# Test file is self-contained (redeclares types to avoid SwiftUI dependency)
if /usr/bin/swiftc -parse-as-library -module-cache-path /tmp/bliss_module_cache -framework Foundation "${ROOT_DIR}/tests/test_gui_logic.swift" -o "${SWIFT_TEST_BIN}" 2>&1; then
    if "${SWIFT_TEST_BIN}"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL: Swift tests failed to compile"
    FAIL=$((FAIL + 1))
fi

# ---- Summary ----
echo ""
echo "==============================="
TOTAL=$((PASS + FAIL))
echo " ${PASS}/${TOTAL} test suites passed"
if [[ "${FAIL}" -eq 0 ]]; then
    echo " ALL SUITES PASSED"
else
    echo " ${FAIL} SUITE(S) FAILED"
    exit 1
fi
