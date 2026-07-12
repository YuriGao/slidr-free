#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${PROJECT_ROOT}/release/Slidr-Free.app"
ZIP_PATH="${PROJECT_ROOT}/release/Slidr-Free.app.zip"
ROOT_LICENSE="${PROJECT_ROOT}/LICENSE"

fail() {
  echo "release verification failed: $*" >&2
  exit 1
}

[[ -f "${ROOT_LICENSE}" ]] || fail "root LICENSE is missing: ${ROOT_LICENSE}"

assert_plist_value() {
  local label="$1"
  local info_plist="$2"
  local key="$3"
  local expected="$4"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :${key}" "${info_plist}")" || fail "${label}: cannot read ${key} from Info.plist"
  [[ "${actual}" == "${expected}" ]] || fail "${label}: ${key} expected '${expected}', got '${actual}'"
  echo "verified ${label}: ${key}=${actual}"
}

verify_app_bundle() {
  local label="$1"
  local app_path="$2"
  local info_plist="${app_path}/Contents/Info.plist"
  local packaged_license="${app_path}/Contents/Resources/LICENSE"

  [[ -d "${app_path}" ]] || fail "${label}: app bundle is missing: ${app_path}"
  [[ -f "${info_plist}" ]] || fail "${label}: Info.plist is missing: ${info_plist}"
  [[ -f "${packaged_license}" ]] || fail "${label}: packaged LICENSE is missing: ${packaged_license}"
  cmp -s "${ROOT_LICENSE}" "${packaged_license}" || fail "${label}: packaged LICENSE differs from root LICENSE"

  assert_plist_value "${label}" "${info_plist}" "CFBundleIdentifier" "com.slidr.free"
  assert_plist_value "${label}" "${info_plist}" "CFBundleShortVersionString" "0.3.0"
  assert_plist_value "${label}" "${info_plist}" "CFBundleVersion" "3001"
  codesign --verify --verbose=2 "${app_path}" || fail "${label}: code signature verification failed"
  local signature_details
  local signature=""
  signature_details="$(codesign -dv --verbose=4 "${app_path}" 2>&1)" || fail "${label}: cannot inspect code signature"
  while IFS= read -r line; do
    case "${line}" in
      Signature=*) signature="${line#Signature=}" ;;
    esac
  done <<< "${signature_details}"
  [[ "${signature}" == "adhoc" ]] || fail "${label}: expected ad-hoc signature, got '${signature:-missing}'"
  echo "verified ${label}: Signature=${signature}"
}

verify_app_bundle "loose app" "${APP_PATH}"

[[ -f "${ZIP_PATH}" ]] || fail "release archive is missing: ${ZIP_PATH}"
EXTRACT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/slidr-free-release.XXXXXX")"
trap 'rm -rf "${EXTRACT_ROOT}"' EXIT
unzip -q "${ZIP_PATH}" -d "${EXTRACT_ROOT}" || fail "cannot extract release archive: ${ZIP_PATH}"
verify_app_bundle "archived app" "${EXTRACT_ROOT}/Slidr-Free.app"

echo "release verification passed: loose app and archived app"
