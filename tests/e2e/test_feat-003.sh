#!/bin/bash
# =============================================================================
#  E2E test: feat-003 — README.md 구성 검증
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
README="${SCRIPT_DIR}/README.md"

fail=0
assert_contains() {
  local needle="$1"
  local label="$2"
  if grep -qF -- "${needle}" "${README}"; then
    echo "PASS: ${label}"
  else
    echo "FAIL: ${label} — '${needle}' 누락"
    fail=1
  fi
}

if [[ ! -f "${README}" ]]; then
  echo "FAIL: README.md 파일이 존재하지 않음"
  exit 1
fi

assert_contains "create-k8s-vms.sh" "create-k8s-vms.sh 섹션"
assert_contains "gke-startup.sh" "gke-startup.sh 섹션"
assert_contains "kube-node-setup.sh" "kube-node-setup.sh 섹션"
assert_contains "--zone" "ZONE CLI 인자 사용법"
assert_contains "us-west1-b" "create-k8s-vms.sh 기본 ZONE 언급"
assert_contains "us-central1-c" "gke-startup.sh 기본 ZONE 언급"
assert_contains "tests/e2e" "테스트 섹션"

if [[ "${fail}" -eq 0 ]]; then
  echo ""
  echo "PASS feat-003"
  exit 0
else
  echo ""
  echo "FAIL feat-003"
  exit 1
fi
