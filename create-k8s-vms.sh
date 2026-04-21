#!/bin/bash
# =============================================================================
#  Kubernetes 클러스터용 VM 3대 생성 스크립트 (GCP)
#  - controlplane-1 / worker-1 / worker-2
#  - Region: us-west1 (Oregon) 기본값 — CLI/환경변수로 변경 가능
#  - OS: Ubuntu 24.04 LTS (amd64)
#  - Disk: 표준 영구 디스크(pd-standard) 100GB
#
#  사용법:
#    ./create-k8s-vms.sh                         # 기본 ZONE(us-west1-b)
#    ./create-k8s-vms.sh --zone us-west1-c       # CLI 인자로 ZONE 지정
#    ./create-k8s-vms.sh -z us-west1-a
#    ZONE=us-west1-c ./create-k8s-vms.sh         # 환경변수로 ZONE 지정
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# [1] ZONE 설정
#     우선순위: CLI 인자 > 환경변수(ZONE) > 기본값(us-west1-b)
#     본인 이름 초성에 해당하는 ZONE 으로 지정하세요.
#       가나다라마 → us-west1-b
#       바사아자   → us-west1-c
#       차카타파하 → us-west1-a
# -----------------------------------------------------------------------------
DEFAULT_ZONE="us-west1-b"
ZONE="${ZONE:-${DEFAULT_ZONE}}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [-z|--zone ZONE] [-h|--help]

옵션:
  -z, --zone ZONE    VM 을 생성할 GCP 존 (예: us-west1-b)
  -h, --help         이 도움말 출력

환경변수:
  ZONE               CLI 인자가 없을 때 사용되는 ZONE 값

현재 기본 ZONE: ${DEFAULT_ZONE}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -z|--zone)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "❌ '$1' 옵션에는 ZONE 값이 필요합니다." >&2
        usage >&2
        exit 2
      fi
      ZONE="$2"
      shift 2
      ;;
    --zone=*)
      ZONE="${1#--zone=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "❌ 알 수 없는 인자: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# -----------------------------------------------------------------------------
# [2] 공통 설정
# -----------------------------------------------------------------------------
MACHINE_TYPE="e2-medium"              # 최소 2 vCPU 권장 (kubeadm 요구사항)
IMAGE_FAMILY="ubuntu-2404-lts-amd64"  # Ubuntu 24.04 LTS x86_64
IMAGE_PROJECT="ubuntu-os-cloud"
DISK_SIZE="100GB"
DISK_TYPE="pd-standard"               # 표준 영구 디스크

VMS=("controlplane-1" "worker-1" "worker-2")

# -----------------------------------------------------------------------------
# [3] 현재 프로젝트 확인
# -----------------------------------------------------------------------------
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "${PROJECT_ID}" ]]; then
  echo "❌ 활성화된 GCP 프로젝트가 없습니다. 'gcloud config set project <PROJECT_ID>' 를 먼저 실행하세요."
  exit 1
fi

echo "=============================================="
echo " Project : ${PROJECT_ID}"
echo " Zone    : ${ZONE}"
echo " Machine : ${MACHINE_TYPE}"
echo " Image   : ${IMAGE_PROJECT}/${IMAGE_FAMILY}"
echo " Disk    : ${DISK_TYPE} ${DISK_SIZE}"
echo "=============================================="

# -----------------------------------------------------------------------------
# [4] VM 3대 생성
# -----------------------------------------------------------------------------
for VM in "${VMS[@]}"; do
  echo ""
  echo "==> [${VM}] 생성 중..."
  gcloud compute instances create "${VM}" \
    --zone="${ZONE}" \
    --machine-type="${MACHINE_TYPE}" \
    --image-family="${IMAGE_FAMILY}" \
    --image-project="${IMAGE_PROJECT}" \
    --boot-disk-size="${DISK_SIZE}" \
    --boot-disk-type="${DISK_TYPE}" \
    --boot-disk-device-name="${VM}"
done

# -----------------------------------------------------------------------------
# [5] 결과 확인
# -----------------------------------------------------------------------------
echo ""
echo "==> 생성 결과"
gcloud compute instances list \
  --filter="zone:(${ZONE}) AND (name=controlplane-1 OR name=worker-1 OR name=worker-2)" \
  --format="table(name,zone,machineType.basename(),status,networkInterfaces[0].networkIP,networkInterfaces[0].accessConfigs[0].natIP)"

echo ""
echo "✅ 완료되었습니다."
