# docker-and-k8s-for-devops

DevOps를 위한 도커와 쿠버네티스 강의 실습에서 사용하는 스크립트 모음입니다.

## 구성

| 스크립트 | 대상 | 설명 |
|---|---|---|
| `create-k8s-vms.sh` | GCP Compute Engine | kubeadm 실습용 VM 3대(controlplane-1/worker-1/worker-2)를 한 번에 생성 |
| `gke-startup.sh` | GCP GKE | 스탠다드 존(zonal) GKE 클러스터 1개를 기본값 구성으로 생성 |
| `kube-node-setup.sh` | Ubuntu 노드 | kubeadm이 요구하는 containerd·커널 모듈·sysctl·kubelet/kubeadm/kubectl 설치 |

## 사전 조건

- GCP 스크립트(`create-k8s-vms.sh`, `gke-startup.sh`) 실행 환경:
  - `gcloud` CLI 가 설치 및 인증되어 있어야 합니다.
  - 활성 GCP 프로젝트가 선택되어 있어야 합니다.
    - `gcloud config set project <PROJECT_ID>` 혹은 `PROJECT_ID=<id>` 환경변수로 지정.
  - Cloud Shell에서도 그대로 동작합니다.
- 노드 셋업 스크립트(`kube-node-setup.sh`) 실행 환경:
  - Ubuntu 22.04 / 24.04 노드에서 `sudo` 권한으로 실행합니다.

## 사용법

### 1. `create-k8s-vms.sh` — kubeadm 실습용 VM 3대 생성

```bash
# 기본 ZONE(us-west1-b) 사용
./create-k8s-vms.sh

# CLI 인자로 ZONE 지정
./create-k8s-vms.sh --zone us-west1-c
./create-k8s-vms.sh -z us-west1-a

# 환경변수로 ZONE 지정
ZONE=us-west1-c ./create-k8s-vms.sh

# 도움말
./create-k8s-vms.sh --help
```

ZONE 결정 우선순위: **CLI 인자 > 환경변수 `ZONE` > 기본값(`us-west1-b`)**.

생성되는 VM 스펙:
- 머신 타입: `e2-medium` (2 vCPU / 4 GB)
- 이미지: Ubuntu 24.04 LTS (amd64)
- 디스크: `pd-standard` 100 GB

### 2. `gke-startup.sh` — GKE 스탠다드 클러스터 생성

```bash
# 기본 ZONE(us-central1-c) 사용
./gke-startup.sh

# CLI 인자로 ZONE 지정
./gke-startup.sh --zone us-central1-a
./gke-startup.sh -z us-central1-b

# 환경변수로 ZONE / PROJECT_ID 지정
ZONE=us-central1-a ./gke-startup.sh
PROJECT_ID=my-project ZONE=us-central1-a ./gke-startup.sh

# 도움말
./gke-startup.sh --help
```

ZONE 결정 우선순위: **CLI 인자 > 환경변수 `ZONE` > 기본값(`us-central1-c`)**.

생성되는 클러스터 스펙:
- 클러스터 이름: `cluster-1`
- 노드 수 / 머신 타입: 2 × `e2-standard-4`
- 디스크: `pd-standard` 100 GB (SSD 할당량 이슈 회피용 HDD)
- 릴리스 채널: `regular`
- 생성 후 자동으로 `kubectl` 인증 정보를 페치하고 `kubectl get nodes` 로 노드 상태를 확인합니다.

### 3. `kube-node-setup.sh` — Ubuntu 노드에 kubeadm 스택 설치

각 VM(예: `create-k8s-vms.sh` 로 만든 3대)에 SSH 접속 후 노드 내부에서 실행합니다.

```bash
sudo bash kube-node-setup.sh
```

주요 작업:
- Kubernetes v1.35 apt 저장소 등록 및 `kubelet` / `kubeadm` / `kubectl` 설치 + hold
- `overlay`, `br_netfilter` 커널 모듈 로드 및 sysctl 설정(`net.bridge.bridge-nf-call-iptables`, `net.ipv4.ip_forward` 등)
- `containerd` 기본 설정 생성 및 `SystemdCgroup = true` 적용 후 재시작

## 강의 플로우

1. `create-k8s-vms.sh` 로 VM 3대를 생성합니다.
2. 각 VM에 SSH 접속 후 `kube-node-setup.sh` 를 실행해 kubeadm 런타임을 준비합니다.
3. controlplane 노드에서 `kubeadm init` → worker 노드에서 `kubeadm join` 으로 클러스터를 구성합니다.
4. 관리형 환경 비교용으로 `gke-startup.sh` 를 실행해 GKE 클러스터를 생성하고 `kubectl` 로 접근해 봅니다.

## 테스트

프로젝트 하네스 규약에 따라 각 기능의 E2E 테스트는 `tests/e2e/` 하위에 위치합니다.

```bash
bash tests/e2e/test_feat-001.sh   # create-k8s-vms.sh ZONE 인자 검증
bash tests/e2e/test_feat-002.sh   # gke-startup.sh ZONE 인자 검증
bash tests/e2e/test_feat-003.sh   # README 구성 검증
```

테스트는 실제 GCP 리소스를 생성하지 않고, 스크립트의 인자 파싱과 설정 요약 출력만 검증합니다.
