#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${PROJECT_ROOT}/release/Slidr-Free.app"
ZIP_PATH="${PROJECT_ROOT}/release/Slidr-Free.app.zip"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"
PACKAGED_LICENSE="${APP_PATH}/Contents/Resources/LICENSE"
ROOT_LICENSE="${PROJECT_ROOT}/LICENSE"

fail() {
  echo "release verification failed: $*" >&2
  exit 1
}

[[ -d "${APP_PATH}" ]] || fail "app bundle is missing: ${APP_PATH}"
[[ -f "${INFO_PLIST}" ]] || fail "Info.plist is missing: ${INFO_PLIST}"
[[ -f "${PACKAGED_LICENSE}" ]] || fail "packaged LICENSE is missing: ${PACKAGED_LICENSE}"
[[ -f "${ROOT_LICENSE}" ]] || fail "root LICENSE is missing: ${ROOT_LICENSE}"
cmp -s "${ROOT_LICENSE}" "${PACKAGED_LICENSE}" || fail "packaged LICENSE differs from root LICENSE"

assert_plist_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :${key}" "${INFO_PLIST}")" || fail "cannot read ${key} from Info.plist"
  [[ "${actual}" == "${expected}" ]] || fail "${key} expected '${expected}', got '${actual}'"
  echo "verified ${key}=${actual}"
}

assert_plist_value "CFBundleIdentifier" "com.slidr.free"
assert_plist_value "CFBundleShortVersionString" "0.3.0"
assert_plist_value "CFBundleVersion" "3001"

codesign --verify --verbose=2 "${APP_PATH}"

[[ -f "${ZIP_PATH}" ]] || fail "release archive is missing: ${ZIP_PATH}"
unzip -Z1 "${ZIP_PATH}" | grep -qx "Slidr-Free.app/Contents/Resources/LICENSE" || fail "release archive does not contain Contents/Resources/LICENSE"
unzip -p "${ZIP_PATH}" "Slidr-Free.app/Contents/Resources/LICENSE" | cmp -s "${ROOT_LICENSE}" - || fail "LICENSE in release archive differs from root LICENSE"

echo "release verification passed: ${APP_PATH}"
