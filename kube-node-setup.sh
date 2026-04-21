# kube_install.sh 파일 생성 
cat <<EOF > kube_install.sh
# 다음 지침은 쿠버네티스 v1.35에 대한 것이다.
# apt 패키지 인덱스를 업데이트하고 쿠버네티스 apt 리포지터리를 사용하는 데 필요한 패키지를 설치한다.
sudo apt-get update

# apt-transport-https는 더미 패키지일 수 있다. 그렇다면 해당 패키지를 건너뛸 수 있다
sudo apt-get install -y apt-transport-https ca-certificates curl gpg containerd

# 쿠버네티스 패키지 리포지터리용 공개 샤이닝 키를 다운로드한다. 모든 리포지터리에 동일한 서명 키가 사용되므로 URL의 버전은 무시할 수 있다.
# `/etc/apt/keyrings` 디렉터리가 존재하지 않으면, curl 명령 전에 생성해야 한다. 아래 참고사항을 읽어본다.
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

#참고:
#데비안 12와 우분투 22.04보다 오래된 릴리스에서는 /etc/apt/keyrings 디렉터리가 기본적으로 존재하지 않으며, curl 명령 전에 생성되어야 한다.
#적절한 쿠버네티스 apt 리포지터리를 추가한다. 이 리포지터리에는 쿠버네티스 1.35에 대한 패키지만 있다는 점에 유의한다. 다른 쿠버네티스 마이너 버전의 경우, 원하는 마이너 버전과 일치하도록 URL의 쿠버네티스 마이너 버전을 변경해야 한다 (설치할 계획인 쿠버네티스 버전에 대한 문서를 읽고 있는지도 확인해야 한다).

# 이 명령어는 /etc/apt/sources.list.d/kubernetes.list 에 있는 기존 구성을 덮어쓴다.
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# apt 패키지 색인을 업데이트하고, kubelet, kubeadm, kubectl을 설치하고 해당 버전을 고정한다.
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# (선택사항) kubeadm을 실행하기 전에 kubelet 서비스를 활성화한다.
sudo systemctl enable --now kubelet
EOF

# 생성한 스크립트를 실행
sudo bash kube_install.sh

############################################
# CKA 시험에도 나오는 기본 네트워크 설정 
# 1. iptables 설정
# k8s.conf 파일에 필요한 커널 모듈을 추가
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# overlay 네트워크와 br_netfilter 모듈을 즉시 로드
sudo modprobe overlay
sudo modprobe br_netfilter

# 쿠버네티스에 필요한 네트워크 설정을 sysctl 파일에 추가
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# 시스템 전체에 sysctl 설정을 적용
sudo sysctl --system

##############################################
# 2. containerd 기본 설정 
# containerd 설정 디렉토리 생성
sudo mkdir -p /etc/containerd

# containerd의 기본 설정을 파일로 저장
sudo containerd config default | sudo tee /etc/containerd/config.toml

# 2. containerd 설정 파일에서 SystemdCgroup을 true로 변경
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# 3. cri가 꺼져 있는지 확인하기 리스트가 비어있으면 cri가 활성화된 것임
cat /etc/containerd/config.toml | grep -i disable 

# containerd 서비스 재시작
sudo systemctl restart containerd