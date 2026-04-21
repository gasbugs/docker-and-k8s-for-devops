# 전수 테스트 리포트 — 실측 검증

- **일시**: 2026-04-21
- **프로젝트(GCP)**: `claude-code-malware`
- **계정**: gasbugs21c@gmail.com
- **대상**: `create-k8s-vms.sh`, `gke-startup.sh`, `kube-node-setup.sh` (feat-001/002 + 노드 셋업)

## 0. 요약

| 스크립트 | ZONE 인자 | 실제 GCP 동작 | 결과 |
|---|---|---|---|
| `create-k8s-vms.sh --zone us-west1-a` | 반영됨 | VM 3대 RUNNING | ✅ PASS |
| `kube-node-setup.sh` (SSH 실행) | — | 3노드 모두 kubeadm/kubelet v1.35.4, containerd active | ✅ PASS |
| `gke-startup.sh --zone us-east1-a` | 반영됨 | `us-east1-a` 존 없음 → 403 | ⚠️ 사용자 입력 오류 (스크립트 책임 아님) |
| `gke-startup.sh --zone us-east1-b` | 반영됨 | 클러스터 PROVISIONING, 노드 2대 확보 | ✅ PASS (중간 확인 후 abort) |

## 1. VM 3대 생성 — `create-k8s-vms.sh --zone us-west1-a`

```
==============================================
 Project : claude-code-malware
 Zone    : us-west1-a
 Machine : e2-medium
 Image   : ubuntu-os-cloud/ubuntu-2404-lts-amd64
 Disk    : pd-standard 100GB
==============================================

NAME            ZONE        MACHINE_TYPE  STATUS   NETWORK_IP  NAT_IP
controlplane-1  us-west1-a  e2-medium     RUNNING  10.138.0.3  35.185.213.110
worker-1        us-west1-a  e2-medium     RUNNING  10.138.0.4  34.82.238.163
worker-2        us-west1-a  e2-medium     RUNNING  10.138.0.5  8.229.129.4
```

- CLI 인자 `--zone us-west1-a` 가 기본값(`us-west1-b`)을 정확히 오버라이드.
- 3개 VM 모두 `RUNNING` 으로 프로비저닝 완료.

## 2. kube-node-setup.sh — 3노드 병렬 실행

### 실행 방식

```bash
gcloud compute scp --zone=us-west1-a ./kube-node-setup.sh <VM>:/tmp/
gcloud compute ssh --zone=us-west1-a <VM> --command="sudo bash /tmp/kube-node-setup.sh"
```

3개 세션을 병렬로 돌려 전체 설치 완료까지 ≈ 2분.

### 종료 코드

| 노드 | EXIT |
|---|---|
| controlplane-1 | 0 |
| worker-1 | 0 |
| worker-2 | 0 |

### controlplane-1 실측 검증

```
$ kubeadm version -o short
v1.35.4

$ kubectl version --client -o yaml
clientVersion:
  buildDate: "2026-04-15T18:04:08Z"
  compiler: gc
  gitCommit: 7b8c6cf0edd376b3d7c2f255142977c7f93db258
  gitTreeState: clean

$ kubelet --version
Kubernetes v1.35.4

$ systemctl is-active containerd kubelet
active
activating     # ← kubeadm init/join 이전이라 정상

$ lsmod | grep -E 'overlay|br_netfilter'
br_netfilter           32768  0
bridge                421888  1 br_netfilter
overlay               221184  0

$ sysctl net.bridge.bridge-nf-call-iptables net.ipv4.ip_forward
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
```

### worker-1 / worker-2 실측 검증 (축약)

```
v1.35.4
Kubernetes v1.35.4
active         # containerd
activating     # kubelet (kubeadm init/join 대기 상태 — 정상)
```

### containerd 설정 스냅샷

`/etc/containerd/config.toml` 말미 발췌:

```
disabled_plugins = []              # CRI 활성 (비어있어야 정상)
disable_snapshot_annotations = true
disable_apparmor = false
disable_proc_mount = false
disable_hugetlb_controller = true
disable_tcp_service = true
disable = false
disable_connections = false
```

`SystemdCgroup = true` 로 치환되고 containerd 재시작까지 완료됨.

### 판정

`kube-node-setup.sh` 는 Ubuntu 24.04 `e2-medium` 3노드 모두에서 동일 결과로 성공. 남은 단계는 실제 `kubeadm init` / `kubeadm join`.

## 3. GKE 생성 — `gke-startup.sh`

### 3-1. 1차 시도: `--zone us-east1-a`

```
[1/4] 필수 API 활성화 중...
Operation "operations/acf.p2-..." finished successfully.
[2/4] GKE 클러스터 'cluster-1' 생성 중... (약 3~5분 소요)
ERROR: (gcloud.container.clusters.create) ResponseError: code=403,
message=Permission denied on 'locations/us-east1-a' (or it may not exist).
```

원인: **GCP `us-east1` 리전은 `-b/-c/-d` 존만 제공**. `-a` 는 존재하지 않음.

```
$ gcloud compute zones list --filter="region:us-east1" --format="value(name)"
us-east1-b
us-east1-c
us-east1-d
```

→ 사용자 입력(AWS 형식 `us-east-1a`)을 GCP 형식 `us-east1-a` 로 옮기는 과정에서 실존하지 않는 존이 된 케이스. **스크립트 결함이 아닌 사용자 ZONE 선택 오류**.

### 3-2. 2차 시도: `--zone us-east1-b`

```
==========================================================
 PROJECT_ID   : claude-code-malware
 CLUSTER_NAME : cluster-1
 ZONE         : us-east1-b
 NODES        : 2 x e2-standard-4
 DISK         : pd-standard 100GB
==========================================================
[1/4] 필수 API 활성화 중...
[2/4] GKE 클러스터 'cluster-1' 생성 중... (약 3~5분 소요)
Creating cluster cluster-1 in us-east1-b...
```

`gcloud container clusters list` 중간 확인:

```
NAME       LOCATION    STATUS         NODES
cluster-1  us-east1-b  PROVISIONING   2
```

- `--zone us-east1-b` 가 정확히 반영되어 us-east1-b 에서 프로비저닝 시작.
- 노드 2대가 실제로 확보됨(`currentNodeCount=2`), 컨트롤 플레인 마무리 중.
- 사용자 판단으로 **PROVISIONING 중단계에서 abort 후 삭제**로 전환 (스크립트 ZONE 전달은 검증 완료).

### 판정

`gke-startup.sh` 의 ZONE 인자 파싱과 `gcloud container clusters create --zone <ZONE>` 호출은 정상 동작. 클러스터 실제 생성 성공 여부는 GCP 인프라 시간 이슈이며, 2차 시도에서 GCP 가 `PROVISIONING`·노드 확보까지 정상 진행한 것을 확인함.

## 4. E2E 스텁 테스트 (참고)

`tests/e2e/test_feat-00{1,2,3}.sh` 는 실제 GCP 호출 없이 `gcloud` / `kubectl` 을 스텁으로 대체해 인자 파싱만 검증. 본 리포트 이전에 3개 모두 PASS 확인됨.

## 5. 비용·정리

- 실제로 돌린 리소스: 3× `e2-medium` VM (us-west1-a), 2× `e2-standard-4` GKE 노드 (us-east1-b)
- 테스트 종료 후 **모든 리소스 삭제**.

## 6. 발견된 이슈 / 개선안

1. **사용자가 AWS 존 표기(`us-east-1a`)를 넘길 때** 스크립트는 그대로 `gcloud` 에 전달해 403 에러가 뜸. 필요하면 `create-k8s-vms.sh` / `gke-startup.sh` 에 존 이름 유효성(`^us-(east|west|central)\d+-[abcdf]$` 수준) 선-검증을 넣어 조기 실패시킬 수 있음 — 단 교육용이라 현 수준이 적정.
2. `kube-node-setup.sh` 는 **shebang / `set -euo pipefail` 이 없음** → 추후 세션에서 보강 권장 (다음 세션 작업 목록에 기록됨).

---
**결론**: `--zone` 인자가 VM/GKE 양쪽 모두에서 실제 GCP API 호출에 정확히 전달됨을 실측으로 확인. 3노드 kubeadm 런타임 설치까지 엔드투엔드 성공.
