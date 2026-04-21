#!/bin/bash
# =============================================================================
#  E2E test: feat-002 — gke-startup.sh ZONE CLI 인자 지원
#  - 실제 GCP 호출 없이 gcloud / kubectl 을 스텁으로 대체해 인자 파싱과 요약 출력을 검증한다.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="${SCRIPT_DIR}/gke-startup.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

cat >"${TMPDIR}/gcloud" <<'STUB'
#!/bin/bash
case "$*" in
  "config list --format=value(core.project)"*) echo "test-project" ;;
  "config list"*) echo "[core]"; echo "project = test-project" ;;
  "config get-value project"*) echo "test-project" ;;
  *) : ;;
esac
exit 0
STUB
chmod +x "${TMPDIR}/gcloud"

cat >"${TMPDIR}/kubectl" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "${TMPDIR}/kubectl"

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
  grep -E '^ ZONE' | head -1 | awk -F: '{print $2}' | tr -d '[:space:]'
}

# Case 1: 기본값
out1="$(run 2>&1 || true)"
zone1="$(printf '%s\n' "${out1}" | extract_zone)"
check "기본값(us-central1-c)" "us-central1-c" "${zone1}"

# Case 2: 환경변수
out2="$(ZONE=us-central1-b run 2>&1 || true)"
zone2="$(printf '%s\n' "${out2}" | extract_zone)"
check "환경변수 ZONE=us-central1-b" "us-central1-b" "${zone2}"

# Case 3: CLI --zone
out3="$(run --zone us-central1-a 2>&1 || true)"
zone3="$(printf '%s\n' "${out3}" | extract_zone)"
check "--zone us-central1-a" "us-central1-a" "${zone3}"

# Case 4: CLI -z (환경변수보다 우선)
out4="$(ZONE=us-central1-c run -z us-central1-a 2>&1 || true)"
zone4="$(printf '%s\n' "${out4}" | extract_zone)"
check "-z us-central1-a (환경변수 override)" "us-central1-a" "${zone4}"

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
  echo "PASS feat-002"
  exit 0
else
  echo ""
  echo "FAIL feat-002"
  exit 1
fi
