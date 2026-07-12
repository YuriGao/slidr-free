#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAKE_BIN="$(mktemp -d "${TMPDIR:-/tmp}/slidr-free-fake-codesign.XXXXXX")"
trap 'rm -rf "${FAKE_BIN}"' EXIT

cp "${PROJECT_ROOT}/scripts/test-fixtures/codesign-valid-non-adhoc" "${FAKE_BIN}/codesign"
chmod +x "${FAKE_BIN}/codesign"

set +e
PATH="${FAKE_BIN}:${PATH}" bash "${PROJECT_ROOT}/scripts/verify-release.sh" >/dev/null 2>&1
fake_result=$?
set -e
[[ ${fake_result} -ne 0 ]] || {
  echo "signature verifier test failed: valid non-ad-hoc signature was accepted" >&2
  exit 1
}

bash "${PROJECT_ROOT}/scripts/verify-release.sh"
echo "signature verifier test passed: non-ad-hoc rejected and real package accepted"
