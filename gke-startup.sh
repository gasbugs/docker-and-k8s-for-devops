#!/bin/bash
# =============================================================================
#  GKE(Google Kubernetes Engine) 스탠다드 클러스터 생성 스크립트
# -----------------------------------------------------------------------------
#  콘솔에서 "쿠버네티스 엔진 > 클러스터 > 만들기 > 스탠다드로 전환" 후
#  기본값으로 만드는 것과 동일한 결과를 한 번에 생성합니다.
#
#  실행 방법:
#    1) Cloud Shell 또는 gcloud CLI가 설치된 환경에서 실행
#    2) chmod +x gke-startup.sh
#    3) ./gke-startup.sh                          # 기본 ZONE 사용
#       ./gke-startup.sh --zone us-central1-a     # CLI 인자로 ZONE 지정
#       ./gke-startup.sh -z us-central1-b
#       ZONE=us-central1-a ./gke-startup.sh       # 환경변수로 ZONE 지정
# =============================================================================

set -euo pipefail

# =============================================================================
# [ 1. 변경이 잦은 변수 영역 ]  ← 실습 시 이 블록만 수정하시면 됩니다.
# =============================================================================

# -----------------------------------------------------------------------------
# ZONE (존) :
#   우선순위: CLI 인자(--zone/-z) > 환경변수 ZONE > 기본값(us-central1-c)
#   성(姓)에 따라 아래 중 하나로 지정하십시오.
#     ● 가나다라     : us-central1-c
#     ● 마바사아자   : us-central1-b
#     ● 차카타파하   : us-central1-a
# -----------------------------------------------------------------------------
DEFAULT_ZONE="us-central1-c"
ZONE="${ZONE:-${DEFAULT_ZONE}}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [-z|--zone ZONE] [-h|--help]

옵션:
  -z, --zone ZONE    GKE 클러스터를 만들 GCP 존 (예: us-central1-a)
  -h, --help         이 도움말 출력

환경변수:
  ZONE               CLI 인자가 없을 때 사용되는 ZONE 값
  PROJECT_ID         사용할 GCP 프로젝트 ID(미설정 시 자동 감지)

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

# 클러스터 이름 (콘솔 기본값과 동일)
CLUSTER_NAME="cluster-1"

# 프로젝트 ID : 현재 선택된 프로젝트를 자동으로 사용합니다.
#   감지 우선순위:
#     1) 실행 시 환경변수로 전달된 PROJECT_ID   (예: PROJECT_ID=foo bash 스크립트)
#     2) Cloud Shell 환경변수 (DEVSHELL_PROJECT_ID)
#     3) 일반 환경변수 (GOOGLE_CLOUD_PROJECT)
#     4) gcloud config list (최신 권장 방식)
#     5) gcloud config get-value (구버전 호환)
# 특정 프로젝트로 고정하려면 아래 값을 직접 입력하셔도 됩니다. 예) PROJECT_ID="k8s-yg-20251027"
PROJECT_ID="${PROJECT_ID:-${DEVSHELL_PROJECT_ID:-${GOOGLE_CLOUD_PROJECT:-}}}"

if [[ -z "${PROJECT_ID}" ]]; then
  PROJECT_ID="$(gcloud config list --format='value(core.project)' 2>/dev/null | tr -d '[:space:]' || true)"
fi
if [[ -z "${PROJECT_ID}" ]]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null | tr -d '[:space:]' || true)"
fi

# 노드 풀 설정 (콘솔 기본값)
NUM_NODES=2                  # 노드 개수 (콘솔 기본값 3 → 2로 축소)
MACHINE_TYPE="e2-standard-4" # 머신 유형 (4 vCPU / 16 GB, e2-standard-2 대비 한 단계 상향)

# -----------------------------------------------------------------------------
# [ 디스크 설정 & SSD 할당량 오류 대응 ]
#   콘솔 기본값은 DISK_TYPE="pd-balanced" (SSD) → SSD_TOTAL_GB 할당량을 소모합니다.
#   프로젝트 SSD 할당량이 부족하면 아래 오류가 발생합니다.
#     "Insufficient regional quota ... SSD_TOTAL_GB ..."
#
#   해결 옵션:
#     (A) 디스크 크기를 줄인다         → DISK_SIZE=50   (SSD 유지)
#     (B) HDD 타입으로 변경            → DISK_TYPE="pd-standard" (SSD 할당량 미사용) ← 현재 적용
#
#   현재는 (B)안(HDD)으로 설정되어 SSD 할당량 이슈가 원천 차단되어 있습니다.
#   I/O 성능은 SSD보다 낮으니, 강의/실습용으로만 권장드립니다.
# -----------------------------------------------------------------------------
DISK_TYPE="pd-standard"
DISK_SIZE=100

# GKE 릴리스 채널 : regular(권장) / rapid / stable
RELEASE_CHANNEL="regular"

# =============================================================================
# [ 2. 사전 점검 ]
# =============================================================================
if [[ -z "${PROJECT_ID}" ]]; then
  echo "[ERROR] 현재 프로젝트를 감지하지 못했습니다."
  echo ""
  echo "─ 디버깅 정보 ───────────────────────────────────"
  echo "  DEVSHELL_PROJECT_ID  : '${DEVSHELL_PROJECT_ID:-(미설정)}'"
  echo "  GOOGLE_CLOUD_PROJECT : '${GOOGLE_CLOUD_PROJECT:-(미설정)}'"
  echo "  gcloud config list :"
  gcloud config list 2>&1 | sed 's/^/    /'
  echo "─────────────────────────────────────────────────"
  echo ""
  echo "해결 방법(택 1):"
  echo "  [A] 실행 시 환경변수로 전달 (가장 간단)"
  echo "      PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo '<PROJECT_ID>') bash $(basename "$0")"
  echo "  [B] 스크립트 상단 PROJECT_ID=\"...\" 에 직접 입력"
  echo "  [C] Cloud Shell 상단 프로젝트 선택기에서 재선택 후 새 세션으로 실행"
  exit 1
fi

# 감지된 프로젝트를 gcloud 기본값으로도 반영 (이후 명령이 일관된 프로젝트를 쓰도록)
gcloud config set project "${PROJECT_ID}" >/dev/null 2>&1 || true

echo "=========================================================="
echo " PROJECT_ID   : ${PROJECT_ID}"
echo " CLUSTER_NAME : ${CLUSTER_NAME}"
echo " ZONE         : ${ZONE}"
echo " NODES        : ${NUM_NODES} x ${MACHINE_TYPE}"
echo " DISK         : ${DISK_TYPE} ${DISK_SIZE}GB"
echo "=========================================================="

# 필수 API 활성화 (최초 1회만 실행되면 됩니다)
echo "[1/4] 필수 API 활성화 중..."
gcloud services enable container.googleapis.com --project="${PROJECT_ID}"

# =============================================================================
# [ 3. GKE 클러스터 생성 ]
#   - 존 기반(영역) 클러스터 : --zone 사용 (리전 클러스터는 --region 사용)
#   - 콘솔의 "스탠다드 > 기본값"과 동일한 구성
# =============================================================================
echo "[2/4] GKE 클러스터 '${CLUSTER_NAME}' 생성 중... (약 3~5분 소요)"
gcloud container clusters create "${CLUSTER_NAME}" \
  --project="${PROJECT_ID}" \
  --zone="${ZONE}" \
  --release-channel="${RELEASE_CHANNEL}" \
  --num-nodes="${NUM_NODES}" \
  --machine-type="${MACHINE_TYPE}" \
  --disk-type="${DISK_TYPE}" \
  --disk-size="${DISK_SIZE}" \
  --image-type="COS_CONTAINERD" \
  --enable-ip-alias

# =============================================================================
# [ 4. kubectl 인증 정보(토큰) 페칭 ]
#   콘솔의 [연결] 버튼이 알려주는 gcloud 명령과 동일한 역할입니다.
# =============================================================================
echo "[3/4] kubectl 인증 정보 페칭 중..."
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --zone="${ZONE}" \
  --project="${PROJECT_ID}"

# =============================================================================
# [ 5. 노드 확인 ]
# =============================================================================
echo "[4/4] 노드 상태 확인"
kubectl get nodes

echo "=========================================================="
echo " ✅ 완료 : 클러스터 '${CLUSTER_NAME}' (${ZONE}) 사용 준비 완료"
echo "=========================================================="
