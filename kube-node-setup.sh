# ============================================================================
# kube-node-setup.sh
# ----------------------------------------------------------------------------
# 목적: Ubuntu(데비안 계열) VM에서 쿠버네티스 v1.35 컨트롤플레인/워커 노드로
#       동작하는 데 필요한 "공통 전제 조건"을 준비하는 스크립트.
#
# 이 스크립트가 하는 일(크게 3단계):
#   1) kubelet / kubeadm / kubectl 설치 + containerd 런타임 설치
#   2) 쿠버네티스 네트워크 전제 커널 모듈 / sysctl 적용
#      (iptables 브리지 호출 + IPv4 포워딩 활성화)
#   3) containerd(CRI 런타임) 기본 설정 생성 및 SystemdCgroup 활성화
#
# 사용 대상: create-k8s-vms.sh 로 띄운 GCE VM(들), 또는 동일한 요구사항을
#           가진 온프레 / 타 클라우드의 Ubuntu 호스트.
#
# 주의:
#   - sudo 권한을 사용한다. 루트 또는 sudo 가능한 사용자로 실행.
#   - kubeadm init / kubeadm join 같은 "클러스터를 실제로 구성하는" 명령은
#     이 스크립트에 포함되어 있지 않다. 여기서는 어디까지나 "전제 조건"만 만든다.
#   - 본 스크립트는 셔뱅(#!) 줄이 없다. `bash kube-node-setup.sh` 형태로
#     명시적으로 bash로 실행하는 것을 권장한다.
# ============================================================================


# ============================================================================
# [1단계] 쿠버네티스 apt 저장소 등록 + kubelet/kubeadm/kubectl + containerd 설치
# ============================================================================
# 다음 지침은 쿠버네티스 v1.35에 대한 것이다.
# 마이너 버전을 바꾸려면 아래 URL의 `v1.35` 부분을 원하는 버전으로 수정하면 된다.

# apt 패키지 인덱스를 최신화. 이어지는 install 명령이 신선한 메타데이터를 보도록.
sudo apt-get update

# HTTPS 저장소 접근과 CRI 런타임에 필요한 패키지들을 한 번에 설치.
#   - apt-transport-https : HTTPS 저장소 지원 (최신 배포에서는 더미 패키지일 수 있음)
#   - ca-certificates     : TLS 루트 인증서
#   - curl                : Release.key 등 다운로드용
#   - gpg                 : ASCII armored 키를 바이너리 키링(.gpg)으로 dearmor 하는 데 사용
#   - containerd          : 쿠버네티스 CRI 런타임(필수). 3단계에서 설정 파일을 손본다.
sudo apt-get install -y apt-transport-https ca-certificates curl gpg containerd

# 쿠버네티스 apt 서명 키를 받을 디렉터리 준비.
# 데비안 12 / 우분투 22.04 미만에서는 /etc/apt/keyrings 가 기본 생성되어 있지 않으므로
# 명시적으로 만들어 준다. -m 755 는 keyring 디렉터리 표준 권한(소유자 rwx + 그 외 rx).
sudo mkdir -p -m 755 /etc/apt/keyrings

# 쿠버네티스 패키지 리포지터리용 공개 서명 키를 다운로드한다.
# 모든 마이너 버전이 동일한 서명 키를 쓰므로, URL 경로의 버전 문자열은 형식상 존재할 뿐
# 키 자체에는 영향이 없다.
# curl 로 받은 ASCII armored 키를 gpg --dearmor 로 바이너리 키링으로 변환해서 저장한다.
# 이 키링은 아래 sources.list.d/kubernetes.list 의 [signed-by=...] 가 참조한다.
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# 쿠버네티스 apt 리포지터리를 추가한다. 이 리포지터리에는 v1.35 패키지만 들어 있다.
# 다른 마이너 버전을 쓰려면 URL 의 버전 문자열을 바꿔야 하며, 설치 대상 버전의 공식
# 문서를 함께 확인하는 것이 안전하다.
# [signed-by=...] 로 방금 받은 키링을 지정 → 이 저장소는 해당 키로만 검증된다.
# tee 는 `sudo echo > ...` 가 리다이렉션 단계에서 권한 오류를 내는 문제를 피하기 위한 관용구.
# (이 명령은 /etc/apt/sources.list.d/kubernetes.list 기존 내용을 덮어쓴다.)
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# 방금 추가한 저장소를 반영하도록 apt 색인을 다시 최신화.
sudo apt-get update

# 쿠버네티스 핵심 바이너리 3종 설치.
#   - kubelet : 노드 에이전트. 파드/컨테이너 수명주기 관리.
#   - kubeadm : 클러스터 부트스트랩 도구(init / join).
#   - kubectl : 클러스터 조작 CLI.
sudo apt-get install -y kubelet kubeadm kubectl

# apt-mark hold : 세 패키지를 `apt upgrade` 자동 업그레이드 대상에서 제외한다.
# 쿠버네티스는 아무 때나 마이너 업그레이드해도 되는 소프트웨어가 아니라
# `kubeadm upgrade` 같은 문서화된 절차로만 올려야 하므로, 사고 방지용 고정.
sudo apt-mark hold kubelet kubeadm kubectl

# (선택사항) kubeadm 을 실행하기 전에 kubelet 서비스를 활성화.
# enable --now : 부팅 시 자동 시작 + 지금 즉시 시작.
# kubeadm init / join 단계에서 정적 파드(etcd / apiserver 등)가 올라오려면
# kubelet 이 먼저 떠 있어야 한다.
sudo systemctl enable --now kubelet


# ============================================================================
# [2단계] 쿠버네티스 네트워크 전제 조건 (커널 모듈 + sysctl)
# ============================================================================
# CKA 시험에도 나오는 단골 주제. 쿠버네티스(특히 kube-proxy iptables 모드,
# CNI 브리지 네트워크)는 리눅스 브리지를 통과하는 패킷이 iptables 체인을
# "타도록" 강제해야 한다. 이를 위해 다음 두 커널 모듈이 필요하다:
#   - overlay      : 컨테이너 런타임 오버레이 파일시스템 지원
#   - br_netfilter : 브리지 트래픽이 netfilter(iptables) 훅을 타게 해 주는 모듈

# /etc/modules-load.d/k8s.conf 에 모듈 이름을 남겨 두면, 재부팅 후에도 자동 로드된다.
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# 재부팅을 기다리지 않고 "지금 이 세션"에 두 모듈을 즉시 로드.
sudo modprobe overlay
sudo modprobe br_netfilter

# 쿠버네티스에 필요한 커널 네트워크 파라미터를 영구 설정 파일로 기록한다.
#   - bridge-nf-call-iptables  : 브리지 통과 IPv4 트래픽을 iptables 가 처리하도록
#   - bridge-nf-call-ip6tables : 동일 옵션의 IPv6 버전
#   - ip_forward               : 라우팅(포워딩) 허용. 파드 간 / 노드 간 통신 필수.
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# --system 옵션: /etc/sysctl.d/*.conf 를 포함해 모든 sysctl 파일을 다시 읽어 적용.
# 이걸 거쳐야 위에서 기록한 값들이 런타임에 즉시 반영된다.
sudo sysctl --system


# ============================================================================
# [3단계] containerd(CRI 런타임) 기본 설정
# ============================================================================
# containerd 는 1단계에서 이미 설치되어 있다. 여기서는 설정 파일을 생성 / 수정한다.

# /etc/containerd/ 를 준비. containerd 데몬이 재시작 시 이 경로의 config.toml 을 읽는다.
sudo mkdir -p /etc/containerd

# `containerd config default` 가 기본 설정 전체를 stdout 으로 출력 →
# tee 로 /etc/containerd/config.toml 에 저장.
# 패키지 설치 직후에는 config.toml 이 아예 없거나 최소 설정뿐인 경우가 많아서
# "완전한 기본값"을 한 번 펼쳐 두고 거기서부터 수정하는 패턴이다.
sudo containerd config default | sudo tee /etc/containerd/config.toml

# kubelet 이 systemd cgroup 드라이버를 사용하므로 CRI 런타임도 같은 드라이버를
# 써야 한다. 드라이버가 서로 다르면 kubelet 이 파드를 정상적으로 기동하지 못한다.
# sed 로 `SystemdCgroup = false` → `SystemdCgroup = true` 인플레이스 치환.
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# CRI 플러그인이 disabled_plugins = ["cri"] 로 꺼져 있으면 kubelet 이 containerd 와
# 통신하지 못한다. `disable` 키를 grep 해 설정이 비어 있는지 눈으로 확인하는 진단 단계.
# (이 줄이 빈 리스트를 가리켜야 CRI 가 활성화된 상태.)
cat /etc/containerd/config.toml | grep -i disable

# 바뀐 config.toml 을 적용하려면 containerd 데몬을 재시작해야 한다.
sudo systemctl restart containerd
