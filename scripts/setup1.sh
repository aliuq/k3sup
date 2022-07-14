#! /bin/bash

clear
# Colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
plain='\033[0m'

KERNEL_LIMIT_VERSION="5.4.205"
DRY_RUN=${DRY_RUN:-}
ip=''
agent=false
verbose=false
kernel='ml'
input_hostname=''
help=false
k3s_url=''
k3s_token=''

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

if [ $kernel != 'ml' ] && [ $kernel != 'lt' ]; then
  kernel='ml'
fi

if [ $input_hostname ]; then
  hostnamectl set-hostname $hostname
else
  input_hostname=$(hostname)
fi

info() {
  if $verbose; then
    echo "$1"
  fi
}
yellow() {
  if $verbose; then
    echo "${yellow}$1${plain}"
  fi
}
green() {
  if $verbose; then
    echo "${green}$1${plain}"
  fi
}
red() {
  if $verbose; then
    echo "${red}$1${plain}"
  fi
}
cyan() {
  if $verbose; then
    echo "${cyan}$1${plain}"
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
  kernel_ver=$(uname -r | grep -oP '^[\d.]+')

  if version_lt $kernel_ver $KERNEL_LIMIT_VERSION; then
    info "The current version less than $(yellow 5.4.205), need to upgrade kernel version, wait for 5s, will be auto started upgrade!\n"
    cyan 'Load the public key of the ELRepo'
    run 'rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org'
    cyan 'Preparing udpate ELRepo'
    run 'rpm -Uvh https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm'
    cyan 'Load elrepo-kernel metadata'
    run 'yum --disablerepo=\* --enablerepo=elrepo-kernel repolist'
    cyan 'List avaliable'
    run 'yum --disablerepo="*" --enablerepo="elrepo-kernel" list available'
    cyan "Install $(green kernel-$kernel)"
    run "yum --disablerepo=\* --enablerepo=elrepo-kernel install kernel-$kernel -y"
    cyan 'Generate grub file'
    run 'grub2-mkconfig -o /boot/grub2/grub.cfg'
    cyan 'Remove old kernel tools'
    run 'yum remove -y kernel-tools-libs.x86_64 kernel-tools.x86_64'
    cyan 'Install newest kernel tools'
    run "yum --disablerepo=\* --enablerepo=elrepo-kernel install -y kernel-$kernel-tools.x86_64"
    cyan 'Setup default'
    run "sed -i \"s/GRUB_DEFAULT=saved/GRUB_DEFAULT=0/g\" /etc/default/grub"
    cyan 'Wait for 5s to reboot'
    run 'sleep 5'
    green 'Reboot now!'
    run 'reboot'
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
    run 'docker --version'
    if is_dry_run; then
      return
    fi
    echo "\n\033[0;33mTo reinstall docker, please run the below command firstly:\033[0m"
    echo
    echo "    yum -y remove docker-*"
    echo
  else
    cyan 'Install docker (Need a little time)'
    run 'curl -fsSL https://get.docker.com | sh -s - --mirror Aliyun'
    cyan 'Setup startup'
    run 'systemctl enable --now docker'
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
    kubectl_ver=$(echo $kubectl_version | grep -oP "gitVersion: v[\d.]+\+" | grep -oP "[\d.]+")
    if version_lt $kubectl_ver $kubectl_latest; then
      echo "kubectl version$(yellow $kubectl_ver) is less than offical latest$(yellow $kubectl_latest)"
      echo
      echo "    curl -LO https://dl.k8s.io/release/$kubectl_latest/bin/linux/amd64/kubectl"
      echo "    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
      echo "    kubectl version --client --output=yaml"
      echo
    else
      echo "kubectl version$(yellow $kubectl_ver) is greater than offical latest$(yellow $kubectl_latest), no need to update!"
    fi
  else
    cyan 'Install kubectl binary'
    run "curl -fsSLO https://dl.k8s.io/release/$kubectl_latest/bin/linux/amd64/kubectl"
    cyan 'Validate the binary'
    run "curl -fsSLO https://dl.k8s.io/$kubectl_latest/bin/linux/amd64/kubectl.sha256"
    run "echo \"\$(cat kubectl.sha256) kubectl\" | sha256sum --check"
    cyan 'Install kubectl'
    run "sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
    run "kubectl version --output=yaml"
  fi
}

# Install wireguard
install_wireguard() {
  echo_title 'Install Wireguard'
  run 'yum update -y'
  run 'yum install epel-release https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm -y'
  run 'yum install yum-plugin-elrepo -y'
  run 'yum install kmod-wireguard wireguard-tools -y'
}

get_public_ip() {
  if [ -z "$ip" ]; then
    if is_dry_run; then
      return
    fi
    ip=$(curl -fsSL https://api.ipify.org)
  fi
}

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
    cyan 'Setup enable'
    run 'systemctl enable k3s-agent --now'
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

echo_info() {
  echo
  echo

  if ! $agent; then
    cat <<-EOF
		INFO

		K3S_URL:   $(green "https://$ip:6443")
		K3S_TOKEN: $(green $(cat /var/lib/rancher/k3s/server/node-token))
		EOF
  fi

  echo "\n${yellow}After reboot, run $(green 'wg show flannel.1') to check the connection status${plain}"
  echo
}

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
  echo "  \033[1msh <(curl -fsSL https://raw.githubusercontent.com/aliuq/k3sup/master/scripts/setup1.sh)\033[0m"
  echo
  echo "Options:"
  echo
  echo "  --kernel:    Kernel type, options are: \033[1mml\033[0m, \033[1mlt\033[0m; default is \033[1mml\033[0m"
  echo "               lt is stands for long term, ml is based on mainline branch"
  echo "  --agent:     Install k3s agent, default is \033[1mfalse\033[0m"
  echo "               if the value is \033[1mtrue\033[0m, the script will install k3s agent, k3s_url and k3s_token are required"
  echo "               if the value is \033[1mfalse\033[0m, the script will install k3s server"
  echo "  --ip:        Public ipv4 address, default is \033[1m$ip\033[0m, it is from \033[1mcurl -fsSL https://api.ipify.org\033[0m"
  echo "               if provided ip address, the script will overwrite the ipv4 address"
  echo "  --hostname:  Hostname, default is \033[1m$hostname\033[0m, it will be used as cluster node name"
  echo "               no duplicate names with nodes in the cluster"
  echo "  --k3s_url:   The k3s master api server url, general format is: \033[1mhttps://<master_ip>:6443\033[0m"
  echo "               where <master_ip> is the public IP of the cluster control node. only used in k3s agent"
  echo "  --k3s_token: The token required to join the cluster, only used in k3s agent"
  echo "               run \033[1mcat /var/lib/rancher/k3s/server/node-token\033[0m in your control node"
  echo "  --dry-run:   Print command only, will not install anything, default is \033[1mfalse\033[0m,"
  echo "  --verbose:   Output more information, default is \033[1mfalse\033[0m"
  echo "  --help:      Show this help message and exit"
  echo
}

do_install() {
  # echo_help

  user="$(id -un 2>/dev/null || true)"
  sh_c='sh -c'
  if [ "$user" != 'root' ]; then
    if command_exists sudo; then
      sh_c='sudo -E sh -c'
    elif command_exists su; then
      sh_c='su -c'
    else
      cat >&2 <<-'EOF'
			Error: this installer needs the ability to run commands as root.
			We are unable to find either "sudo" or "su" available to make this happen.
			EOF
      exit 1
    fi
  fi

  if is_dry_run; then
    sh_c="echo"
  fi

  if $agent; then
    if is_dry_run; then
      return
    fi
    if [ -z $k3s_url ] || [ -z $k3s_token ]; then
      echo "${red}--k3s_url and --k3s_token is required when --agent is specified${plain}"
      echo_help
      exit 1
    fi
  fi

  update_kernel
  install_doker
  install_wireguard
  install_kubectl
  install_k3s
  sleep 2
  echo_info
  sleep 3
  reboot
}

do_install
