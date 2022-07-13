#! /bin/bash

clear
echo
echo "###################################################################"
echo "#                                                                 #"
echo "# Centos 7.x fast install K3S                                     #"
echo "# Author: AliuQ                                                   #"
echo "#                                                                 #"
echo "###################################################################"
echo

# Colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
plain='\033[0m'

version_lt() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; }

yellow() {
  echo -e "${yellow}$1${plain}"
}
green() {
  echo -e "${green}$1${plain}"
}
red() {
  echo -e "${red}$1${plain}"
}
cyan() {
  echo -e "${cyan}$1${plain}"
}

update_yum() {
  cyan "Update yum repo"
  yum update -y
}

echo_title() {
  echo
  green "======================= 🧡 $1 ======================="
  echo
}

update_kernel() {
  echo_title "Update Kernel"
  kernel_version=$(uname -r)
  kernel_ver=$(echo $kernel_version | grep -P '^[\d.]+' -o)
  echo "Current kernel version: $(yellow $kernel_version)"
  if version_lt $kernel_ver "5.4.205"; then
    echo
    yellow "The current version less than $(yellow 5.4.205), need to upgrade kernel version, wait 5s, will be auto start upgrade!"
    echo
    read -p "Confirm? (y/n) " update_confirm
    if [[ $update_confirm == "y" ]] || [[ $update_confirm == "Y" ]]; then
      cyan 'Load the public key of the ELRepo'
      rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
      yum --disablerepo="*" --enablerepo="elrepo-kernel" list available &> /dev/null
      if [ $? -eq 0 ]; then
        cyan 'Preparing udpate ELRepo'
        rpm -Uvh https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
      else
        cyan 'Preparing install ELRepo'
        yum install -y https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
      fi
      cyan 'Load elrepo-kernel metadata'
      yum --disablerepo=\* --enablerepo=elrepo-kernel repolist
      cyan 'List avaliable'
      yum --disablerepo="*" --enablerepo="elrepo-kernel" list available
      read -p "Select a install type, 1) LTS, 2) Stable? (1/2) " install_type
      if [[ $install_type -eq 1 ]] || [[ -z $install_type ]]; then
        echo "Install kernel $(green LTS)"
        yum --disablerepo=\* --enablerepo=elrepo-kernel install kernel-lt -y
      else
        echo "Install kernel $(green Stable)"
        yum --disablerepo=\* --enablerepo=elrepo-kernel install kernel-ml -y
      fi
      cyan 'Setup default'
      sed -i "s/GRUB_DEFAULT=saved/GRUB_DEFAULT=0/g" /etc/default/grub
      cyan 'Generate grub file'
      grub2-mkconfig -o /boot/grub2/grub.cfg
      cyan 'Remove old kernel tools'
      yum remove -y kernel-tools-libs.x86_64 kernel-tools.x86_64
      cyan 'Install newest kernel tools'
      yum --disablerepo=\* --enablerepo=elrepo-kernel install -y kernel-lt-tools.x86_64
      cyan "Start a new kernel by default"
      echo
      grep "^menuentry" /boot/grub2/grub.cfg | cut -d "'" -f2
      echo
      read -p "select a kernel name to set default: " input_kernel_name
      grub2-set-default "$input_kernel_name"
      cyan 'Wait for 5s to reboot'
      sleep 5
      green 'Reboot now!'
      reboot
    fi
  fi
}

install_doker() {
  echo_title "Install Docker"
  which docker &> /dev/null
  if [ $? -eq 0 ]; then
    docker --version
    echo
    echo
    read -p "$(yellow 'docker installed, remove and reinstall? (y/n)') " reinstall_docker
    if [[ $reinstall_docker == "y" ]] || [[ $reinstall_docker == "Y" ]]; then
      cyan 'Remove existing docker'
      yum -y remove docker-*
      cyan 'Install docker (Need a little time)'
      curl -fsSL https://get.docker.com | sh -s - --mirror Aliyun
      cyan 'Setup startup'
      systemctl enable --now docker
    fi
  else
    cyan 'Install docker (Need a little time)'
    curl -fsSL https://get.docker.com | sh -s - --mirror Aliyun
    cyan 'Setup startup'
    systemctl enable --now docker
  fi
}

install_kubectl() {
  echo_title "Install Kubectl"
  kubectl_latest=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
  which kubectl &> /dev/null
  if [ $? -eq 0 ]; then
    kubectl_version=$(kubectl version --client --output=yaml)
    kubectl_ver=$(echo $kubectl_version | grep -oP "gitVersion: v[\d.]+\+" | grep -oP "[\d.]+")
    if version_lt $kubectl_ver $kubectl_latest; then
      yellow "kubectl version is less than latest"
      read -p "are you sure to upgrade from $(green $kubectl_ver) to $(green $kubectl_latest)? (y/n) " upgrade_kubectl
      if [[ $upgrade_kubectl == "y" ]] || [[ $upgrade_kubectl == "Y" ]]; then
        cyan 'Install kubectl binary'
        curl -fsSLO "https://dl.k8s.io/release/$kubectl_latest/bin/linux/amd64/kubectl"
        cyan 'Validate the binary'
        curl -fsSLO "https://dl.k8s.io/$kubectl_latest/bin/linux/amd64/kubectl.sha256"
        echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
        cyan 'Install kubectl'
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        kubectl version --output=yaml
      fi
    fi
  else
    cyan 'Install kubectl binary'
    curl -fsSLO "https://dl.k8s.io/release/$kubectl_latest/bin/linux/amd64/kubectl"
    cyan 'Validate the binary'
    curl -fsSLO "https://dl.k8s.io/$kubectl_latest/bin/linux/amd64/kubectl.sha256"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
    cyan 'Install kubectl'
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    kubectl version --output=yaml
  fi
}

install_wireguard() {
  echo_title "Install Wireguard"
  which wg &> /dev/null
  if [ $? -eq 0 ]; then
    yellow "Wireguard is already installed in $(which wg)"
  else
    update_yum
    yum install epel-release https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm -y
    yum install yum-plugin-elrepo -y
    yum install kmod-wireguard wireguard-tools -y
    cyan 'Wait for 5s to reboot'
    sleep 5
    green 'Reboot now!'
    reboot
  fi
}

install_k3s() {
  echo_title "Install K3S"
  ipv4=$(curl -fsSL https://api.ipify.org)
  echo -e "$(yellow 'Get your ip address is ')$(green $ipv4)$(yellow ', is will be used by k3s')"
  yellow "If you want to modify it, enter yout ip in below, or else skip the prompt"
  read -p "Enter your ip address: " input_ipv4
  if [[ -n $input_ipv4 ]]; then
    ipv4=$input_ipv4
  fi
  cyan 'Set hostname'
  read -p "Are you sure to change hostname($(green $(hostname))), if not, skip it? " input_hsotname
  if [[ -n $input_hsotname ]]; then
    green "$(hostname) -> $input_hsotname"
    hostnamectl set-hostname $input_hsotname
  fi
  if [[ $1 == '--agent' ]]; then
    cat >&2 <<EOF
Info: the "agent" mode need two variables to start k3s

$(cyan K3S_URL): 
  The k3s master api server url, general format is: $(cyan 'https://<master_ip>:6443'), where <master_ip> is the public IP of the control node.

$(cyan K3S_TOKEN): 
  The token required to join the cluster, run $(cyan 'cat /var/lib/rancher/k3s/server/node-token') in your control node

EOF

  read -p "Input K3S_URL: " k3s_url
  if [ -z $k3s_url ]; then
    exit 0
  fi
  read -p "Input K3S_TOKEN: " k3s_token
  if [ -z $k3s_token ]; then
    exit 0
  fi
  cyan "Install k3s binary"
  curl -fsSL https://rancher-mirror.oss-cn-beijing.aliyuncs.com/k3s/k3s-install.sh | INSTALL_K3S_MIRROR=cn K3S_URL="$k3s_url" K3S_TOKEN="$k3s_token" sh -s - --docker
  cyan "Set /etc/systemd/system/k3s-agent.service"
  cat > /etc/systemd/system/k3s-agent.service <<EOF
[Unit]
Description=Lightweight Kubernetes
Documentation=https://k3s.io
Wants=network-online.target

[Install]
WantedBy=multi-user.target

[Service]
Type=exec
EnvironmentFile=/etc/systemd/system/k3s-agent.service.env
KillMode=process
Delegate=yes
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/k3s agent \
	--docker \
    --node-external-ip $ipv4 \
    --node-ip $ipv4 \
    --kube-proxy-arg "proxy-mode=ipvs" "masquerade-all=true" \
    --kube-proxy-arg "metrics-bind-address=0.0.0.0"
EOF
    cyan 'Setup enable'
    systemctl enable k3s-agent --now
  else
    cyan "Install k3s binary"
    # curl -sfL https://get.k3s.io | sh -s - --docker
    curl -fsSL https://rancher-mirror.oss-cn-beijing.aliyuncs.com/k3s/k3s-install.sh | INSTALL_K3S_MIRROR=cn sh -s - --docker
    cyan 'Link config file'
    mkdir ~/.kube
    ln -s /etc/rancher/k3s/k3s.yaml ~/.kube/config
    cyan "Set /etc/systemd/system/k3s.service"
    cat > /etc/systemd/system/k3s.service <<EOF
[Unit]
Description=Lightweight Kubernetes
Documentation=https://k3s.io
Wants=network-online.target

[Install]
WantedBy=multi-user.target

[Service]
Type=notify
EnvironmentFile=/etc/systemd/system/k3s.service.env
KillMode=process
Delegate=yes
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/k3s \
  server \
  --docker \
  --tls-san $ipv4 \
  --node-ip $ipv4 \
  --node-external-ip $ipv4 \
  --no-deploy servicelb \
  --flannel-backend wireguard \
  --kube-proxy-arg "proxy-mode=ipvs" "masquerade-all=true" \
  --kube-proxy-arg "metrics-bind-address=0.0.0.0"
EOF
    cyan 'Setup enable'
    systemctl enable k3s --now
    sleep 2
    cyan 'Check k3s health'
    kubectl get cs
  fi

  sleep 5
  cyan 'Overwrite public ip'
  kubectl annotate nodes "$(hostname)" flannel.alpha.coreos.com/public-ip-overwrite="$ipv4"
  sleep 2
  cyan 'View [wireguard] connection status'
  wg show flannel.1
}

update_kernel
install_wireguard
install_doker
install_kubectl
install_k3s $1
