#! /bin/bash

clear
# Colors
bold="\033[1m"
red="\033[0;31m"
green="\033[0;32m"
yellow="\033[0;33m"
cyan="\033[0;36m"
plain="\033[0m"

KERNEL_LIMIT_VERSION="5.4.205"
DRY_RUN=${DRY_RUN:-}
ip=""
agent=false
verbose=false
force=false
kernel="ml"
input_hostname=""
help=false
k3s_url=""
k3s_token=""

while [ $# -gt 0 ]; do
  case "$1" in
  --kernel)
    kernel="$2"
    shift
    ;;
  --ip)
    ip="$2"
    shift
    ;;
  --hostname)
    input_hostname="$2"
    shift
    ;;
  --k3s_url)
    k3s_url="$2"
    shift
    ;;
  --k3s_token)
    k3s_token="$2"
    shift
    ;;
  --agent)
    agent=true
    ;;
  --verbose)
    verbose=true
    ;;
  -y)
    force=true
    ;;
  --dry-run)
    DRY_RUN=1
    ;;
  --help)
    help=true
    ;;
  --*)
    echo "Illegal option $1"
    ;;
  esac
  shift $(($# > 0 ? 1 : 0))
done

info() {
  if $verbose; then
    echo "$1"
  fi
}
yellow() {
  if $verbose; then
    printf "${yellow}$1${plain}\n"
  fi
}
green() {
  if $verbose; then
    printf "${green}$1${plain}\n"
  fi
}
red() {
  if $verbose; then
    printf "${red}$1${plain}\n"
  fi
}
cyan() {
  if $verbose; then
    printf "${cyan}$1${plain}\n"
  fi
}

echo_title() {
  if $verbose; then
    green "\n======================= 🧡 $1 =======================\n"
  fi
}

command_exists() {
  command -v "$@" >/dev/null 2>&1
}

# version_lt checks if the version is less than the argument
#
# examples:
#
# version_lt 5.0.4 5.0.5 // true (success)
# version_lt 5.0.4 5.1.5 // true (success)
# version_lt 5.0.5 5.0.5 // false (fail)
# version_lt 5.1.4 5.0.5 // false (fail)
version_lt() {
  test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1";
}

is_dry_run() {
  if [ -z "$DRY_RUN" ]; then
    return 1
  else
    return 0
  fi
}

run() {
  if ! is_dry_run; then
    echo "+ $sh_c $1"
  fi
  $sh_c "$1"
}

# Centos 7.x kernel default version is 3.x, so we need to update it to 5.x
# if the kernel version is greater than $KERNEL_LIMIT_VERSION, will skip this step
update_kernel() {
  echo_title "Update Kernel"
  kernel_ver=$(uname -r | grep -oP "^[\d.]+")

  if version_lt $kernel_ver $KERNEL_LIMIT_VERSION; then
    info "The current version $(yellow v$kernel_ver) less than $(yellow v$KERNEL_LIMIT_VERSION), need to upgrade kernel version"
    info "wait for 5s, will be auto started upgrade!\n"
    cyan "Load the public key of the ELRepo"
    run "rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org"
    cyan "Preparing udpate ELRepo"
    run "rpm -Uvh https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm"
    cyan "Load elrepo-kernel metadata"
    run "yum --disablerepo=\* --enablerepo=elrepo-kernel repolist"
    cyan "List avaliable"
    run "yum --disablerepo=\"*\" --enablerepo=\"elrepo-kernel\" list available"
    cyan "Install $(green kernel-$kernel)"
    run "yum --disablerepo=\* --enablerepo=elrepo-kernel install kernel-$kernel -y"
    cyan "Generate grub file"
    run "grub2-mkconfig -o /boot/grub2/grub.cfg"
    cyan "Remove old kernel tools"
    run "yum remove -y kernel-tools-libs.x86_64 kernel-tools.x86_64"
    cyan "Install newest kernel tools"
    run "yum --disablerepo=\* --enablerepo=elrepo-kernel install -y kernel-$kernel-tools.x86_64"
    cyan "Setup default"
    run "sed -i \"s/GRUB_DEFAULT=saved/GRUB_DEFAULT=0/g\" /etc/default/grub"
    cyan "Wait for 5s to reboot"
    run "sleep 5"
    run "reboot"
  else
    info "The current version($(yellow $kernel_ver)) greater than $(yellow $KERNEL_LIMIT_VERSION), no need to upgrade kernel version!\n"
  fi
}

# Install docker
#
# see more: https://get.docker.com
#
install_doker() {
  echo_title "Install Docker"
  if command_exists docker; then
    run "docker --version"
    if is_dry_run; then
      return
    fi
    printf "\n${yellow}To reinstall docker, please run the below command firstly:${plain}\n"
    echo
    echo "    yum -y remove docker-*"
    echo
  else
    cyan "Install docker (Need a little time)"
    run "curl -fsSL https://get.docker.com | sh -s - --mirror Aliyun"
    cyan "Setup startup"
    run "systemctl enable --now docker"
  fi
}

# Install kubectl
install_kubectl() {
  echo_title "Install Kubectl"
  kubectl_latest=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
  if command_exists kubectl; then
    if is_dry_run; then
      return
    fi
    kubectl_version=$(kubectl version --client --output=yaml)
    kubectl_ver=$(echo $kubectl_version | grep -oP "gitVersion: v[\d.]+\+?" | grep -oP "[\d.]+")
    if version_lt $kubectl_ver $kubectl_latest; then
      echo "kubectl version($(yellow v$kubectl_ver)) is less than offical latest($(yellow $kubectl_latest))"
      echo "run the below commands to upgrade kubectl:"
      echo
      echo "    curl -LO https://dl.k8s.io/release/$kubectl_latest/bin/linux/amd64/kubectl"
      echo "    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
      echo "    kubectl version --client --output=yaml"
      echo
    else
      echo "kubectl version($(yellow v$kubectl_ver)) is greater than offical latest($(yellow $kubectl_latest)), no need to update!"
    fi
  else
    cyan "Install kubectl binary"
    run "curl -fsSLO https://dl.k8s.io/release/$kubectl_latest/bin/linux/amd64/kubectl"
    cyan "Validate the binary"
    run "curl -fsSLO https://dl.k8s.io/$kubectl_latest/bin/linux/amd64/kubectl.sha256"
    run "echo \"\$(cat kubectl.sha256) kubectl\" | sha256sum --check"
    cyan "Install kubectl"
    run "sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
    run "kubectl version --output=yaml"
  fi
}

# Install wireguard
install_wireguard() {
  echo_title "Install Wireguard"
  run "yum update -y"
  run "yum install epel-release https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm -y"
  run "yum install yum-plugin-elrepo -y"
  run "yum install kmod-wireguard wireguard-tools -y"
}

# Get public ip address
get_public_ip() {
  if [ -z "$ip" ]; then
    if is_dry_run; then
      return
    fi
    ip=$(curl -fsSL https://api.ipify.org)
  fi
}

# Install K3S
install_k3s() {
  echo_title "Install K3S"
  get_public_ip
  if $agent; then
    cyan "Install k3s binary"
    run "curl -fsSL https://rancher-mirror.oss-cn-beijing.aliyuncs.com/k3s/k3s-install.sh | INSTALL_K3S_MIRROR=cn K3S_URL=$k3s_url K3S_TOKEN=$k3s_token sh -s - --docker"
    cyan "Write /etc/systemd/system/k3s-agent.service"
    run "cat >/etc/systemd/system/k3s-agent.service <<-EOF
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
				--node-external-ip $ip \
				--node-ip $ip \
				--kube-proxy-arg \"proxy-mode=ipvs\" \"masquerade-all=true\" \
				--kube-proxy-arg \"metrics-bind-address=0.0.0.0\"
		EOF"
    cyan "Setup enable"
    run "systemctl enable k3s-agent --now"
  else
    cyan "Install k3s binary"
    # curl -sfL https://get.k3s.io | sh -s - --docker
    run "curl -fsSL https://rancher-mirror.oss-cn-beijing.aliyuncs.com/k3s/k3s-install.sh | INSTALL_K3S_MIRROR=cn sh -s - --docker"
    cyan "Link config file"
    run "mkdir ~/.kube -p"
    run "cat /etc/rancher/k3s/k3s.yaml >> ~/.kube/config"
    run "chmod 600 ~/.kube/config"
    cyan "Write /etc/systemd/system/k3s.service"
    cat > /etc/systemd/system/k3s.service <<-EOF
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
				--tls-san $ip \
				--node-ip $ip \
				--node-external-ip $ip \
				--no-deploy servicelb \
				--flannel-backend wireguard \
				--kube-proxy-arg "proxy-mode=ipvs" "masquerade-all=true" \
				--kube-proxy-arg "metrics-bind-address=0.0.0.0"
		EOF
    cyan "Setup enable"
    run "systemctl enable k3s --now"
    cyan "Check k3s health"
    run "kubectl get cs"
  fi
  run "sleep 5"
  cyan "Overwrite public ip"
  run "kubectl annotate nodes $(hostname) flannel.alpha.coreos.com/public-ip-overwrite=$ip"
  cyan "View [wireguard] connection status"
  run "wg show flannel.1"
}

# Prinit help info
echo_info() {
  if is_dry_run; then
    return
  fi
  echo
  echo

  if ! $agent; then
    master_url="https://$ip:6443"
    master_token=$(cat /var/lib/rancher/k3s/server/node-token)
    cat <<-EOF
		INFO

		K3S_URL:   `green master_url`
		K3S_TOKEN: `green master_token`


		Used by cluster agent:

		${bold}sh <(curl -fsSL https://raw.githubusercontent.com/aliuq/k3sup/master/scripts/setup1.sh) --agent --k3s_url $master_url --k3s_token $master_token --hostname ${red}<New Node Name>${plain} ${plain}
		EOF
  fi

  printf "\n${yellow}After reboot, run $(green \"wg show flannel.1\") to check the connection status${plain}\n"
  echo
}

# Echo help message
echo_help() {
  echo
  echo "Description:"
  echo
  echo "  The script is about how to easily deploy k3s in cross public cloud on Centos 7.x"
  echo "  it contains upgrade kernel, install docker、wireguard、kubectl、k3s"
  echo "  when run this script in cluster master node, it will print k3s_url and k3s_token"
  echo "  which must be required to join the cluster"
  echo
  echo "Usage:"
  echo
  printf "  ${bold}sh <(curl -fsSL https://raw.githubusercontent.com/aliuq/k3sup/master/scripts/setup1.sh)${plain}\n"
  echo
  echo "Options:"
  echo
  printf "  --kernel     Kernel type, options are: ${bold}ml${plain}, ${bold}lt${plain}; default is ${bold}ml${plain}\n"
  printf "               lt is stands for long term, ml is based on mainline branch\n"
  printf "  --agent      Install k3s agent, default is ${bold}false${plain}\n"
  printf "               if the value is ${bold}true${plain}, the script will install k3s agent, k3s_url and k3s_token are required\n"
  printf "               if the value is ${bold}false${plain}, the script will install k3s server\n"
  printf "  --ip         Public ipv4 address, default is ${bold}$ip${plain}, it is from ${bold}curl -fsSL https://api.ipify.org${plain}\n"
  printf "               if provided ip address, the script will overwrite the ipv4 address\n"
  printf "  --hostname   Hostname, default is ${bold}$hostname${plain}, it will be used as cluster node name\n"
  printf "               no duplicate names with nodes in the cluster\n"
  printf "  --k3s_url    The k3s master api server url, general format is: ${bold}https://<master_ip>:6443${plain}\n"
  printf "               where <master_ip> is the public IP of the cluster control node. only used in k3s agent\n"
  printf "  --k3s_token  The token required to join the cluster, only used in k3s agent\n"
  printf "               run ${bold}cat /var/lib/rancher/k3s/server/node-token${plain} in your control node\n"
  printf "  --dry-run    Print command only, will not install anything, default is ${bold}false${plain}\n"
  printf "  --verbose    Output more information, default is ${bold}false${plain}\n"
  printf "  -y           Skip script prompt, default is ${bold}false${plain}\n"
  printf "  --help       Show this help message and exit\n"
  echo
}

do_preinstall() {
  if is_dry_run; then
    return
  fi
  if [ $kernel != "ml" ] && [ $kernel != "lt" ]; then
    cyan "Set kernel to ml"
    kernel="ml"
  fi

  if [ $input_hostname ]; then
    cyan "Set hostname to $input_hostname"
    hostnamectl set-hostname $hostname
  else
    input_hostname=$(hostname)
  fi

  if $agent; then
    if [ -z $k3s_url ] || [ -z $k3s_token ]; then
      printf "${red}--k3s_url and --k3s_token is required when --agent is specified${plain}\n"
      echo_help
      exit 1
    fi
  fi
}

do_install() {
  if $help; then
    echo_help
    exit 0
  fi
  if ! $force && ! is_dry_run; then
    echo_help
    echo
    read -p "Do you want to continue? [y/N]" answer
    if [ $answer != "y" ] && [ $answer != "Y" ]; then
      echo
      echo "Aborted."
      echo
      exit 1
    fi
  fi

  user="$(id -un 2>/dev/null || true)"
  sh_c="sh -c"
  if [ "$user" != "root" ]; then
    if command_exists sudo; then
      sh_c="sudo -E sh -c"
    elif command_exists su; then
      sh_c="su -c"
    else
      cat >&2 <<-EOF
			Error: this installer needs the ability to run commands as root.
			We are unable to find either "sudo" or "su" available to make this happen.
			EOF
      exit 1
    fi
  fi

  if is_dry_run; then
    sh_c="echo"
  fi

  do_preinstall
  update_kernel
  install_doker
  install_wireguard
  install_kubectl
  install_k3s
  run "sleep 2"
  echo_info
  run "sleep 3"
  run "reboot"
}
# Start install steps
do_install
