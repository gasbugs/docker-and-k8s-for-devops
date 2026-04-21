#!/bin/bash
# =============================================================================
#  E2E test: feat-001 — create-k8s-vms.sh ZONE CLI 인자 지원
#  - 실제 GCP 호출 없이 gcloud 를 스텁으로 대체해 인자 파싱과 요약 출력을 검증한다.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="${SCRIPT_DIR}/create-k8s-vms.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

# gcloud 스텁: 어떤 호출이 와도 무해하게 0을 리턴
cat >"${TMPDIR}/gcloud" <<'STUB'
#!/bin/bash
# 프로젝트 감지에만 의미 있는 값을 리턴
case "$*" in
  "config get-value project"*) echo "test-project" ;;
  *) : ;;
esac
exit 0
STUB
chmod +x "${TMPDIR}/gcloud"

run() {
  PATH="${TMPDIR}:${PATH}" bash "${TARGET}" "$@"
}

fail=0
check() {
  local label="$1"; shift
  local expected="$1"; shift
  local got="$1"; shift
  if [[ "${got}" == "${expected}" ]]; then
    echo "PASS: ${label} (zone=${got})"
  else
    echo "FAIL: ${label} — expected=${expected} got=${got}"
    fail=1
  fi
}

extract_zone() {
  grep -E '^ Zone' | head -1 | awk -F: '{print $2}' | tr -d '[:space:]'
}

# Case 1: 기본값
out1="$(run 2>&1 || true)"
zone1="$(printf '%s\n' "${out1}" | extract_zone)"
check "기본값(us-west1-b)" "us-west1-b" "${zone1}"

# Case 2: 환경변수
out2="$(ZONE=us-west1-c run 2>&1 || true)"
zone2="$(printf '%s\n' "${out2}" | extract_zone)"
check "환경변수 ZONE=us-west1-c" "us-west1-c" "${zone2}"

# Case 3: CLI --zone
out3="$(run --zone us-west1-a 2>&1 || true)"
zone3="$(printf '%s\n' "${out3}" | extract_zone)"
check "--zone us-west1-a" "us-west1-a" "${zone3}"

# Case 4: CLI -z (환경변수보다 우선)
out4="$(ZONE=us-west1-b run -z us-west1-a 2>&1 || true)"
zone4="$(printf '%s\n' "${out4}" | extract_zone)"
check "-z us-west1-a (환경변수 override)" "us-west1-a" "${zone4}"

# Case 5: --help 은 exit 0 + 사용법 출력
help_out="$(bash "${TARGET}" --help 2>&1)"
if printf '%s\n' "${help_out}" | grep -q "Usage:"; then
  echo "PASS: --help 은 Usage 출력"
else
  echo "FAIL: --help 에 Usage 섹션이 없음"
  fail=1
fi

# Case 6: 알 수 없는 인자는 exit 2
set +e
PATH="${TMPDIR}:${PATH}" bash "${TARGET}" --bogus >/dev/null 2>&1
rc=$?
set -e
if [[ "${rc}" -eq 2 ]]; then
  echo "PASS: 알 수 없는 인자 rc=2"
else
  echo "FAIL: 알 수 없는 인자 expected rc=2 got rc=${rc}"
  fail=1
fi

if [[ "${fail}" -eq 0 ]]; then
  echo ""
  echo "PASS feat-001"
  exit 0
else
  echo ""
  echo "FAIL feat-001"
  exit 1
fi
