#! /bin/bash
set -e

# Check requirements for server and agent
# kernel(minimum version: 5.4.205)、docker、kubectl、wireguard
#
# Usage:
#  curl -fsSL https://raw.githubusercontent.com/aliuq/k3sup/master/scripts/requirement.sh | sh
# 
# Mirror of China:
#  curl -fsSL https://raw.fastgit.org/aliuq/k3sup/master/scripts/requirement.sh | sh -s - --mirror
#
clear

verbose=false
mirror=false
kernel="ml"
while [ $# -gt 0 ]; do
  case "$1" in
  --mirror) mirror=true ;;
  --verbose) verbose=true ;;
  --kernel) kernel="$3" shift ;;
  --*) echo "Illegal option $1" ;;
  esac
  shift $(($# > 0 ? 1 : 0))
done

log() {
  echo -e "\033[36m[INFO] $(date "+%Y-%m-%d %H:%M:%S")\033[0m $@"
}

echo_title() {
  echo -e "\033[36m[INFO] $(date "+%Y-%m-%d %H:%M:%S")\033[0m \033[92m===== $@ =====\033[0m"
}

command_exists() {
  command -v "$@" >/dev/null 2>&1
}

version_lt() {
  test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1";
}

set_var() {
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

  if [ $kernel != "ml" ] && [ $kernel != "lt" ]; then
    kernel="ml"
  fi

  suf=""
  if ! $verbose; then
    suf=">/dev/null 2>&1"
  else
    set -x
  fi
}

# Update kernel to required version(minimum v5.4.205)
# When updated, it will be reboot the system
update_kernel() {
  echo_title "Update Kernel"
  KERNEL_LIMIT_VERSION=5.4.205
  kernel_ver=$(uname -r | grep -oP '^[\d.]+')
  if version_lt $kernel_ver $KERNEL_LIMIT_VERSION; then
    log "Your kernel version is $kernel_ver, we need $KERNEL_LIMIT_VERSION or above"
    log "Start Updating, please wait...(\033[5mneed few minutes and reboot required\033[0m)"
    $sh_c "rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org $suf"
    $sh_c "rpm -Uvh https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm $suf"
    $sh_c "yum --disablerepo=\* --enablerepo=elrepo-kernel install kernel-$kernel -y $suf"
    $sh_c "sed -i 's/GRUB_DEFAULT=saved/GRUB_DEFAULT=0/g' /etc/default/grub $suf"
    $sh_c "grub2-mkconfig -o /boot/grub2/grub.cfg $suf"
    $sh_c "yum remove -y kernel-tools-libs.x86_64 kernel-tools.x86_64 $suf"
    $sh_c "yum --disablerepo=\* --enablerepo=elrepo-kernel install -y kernel-$kernel-tools.x86_64 $suf"
    log "Successfully updated kernel, after rebooted, rerun this script"
    $sh_c "reboot"
  else
    log "No need to update kernel, your kernel version is v$kernel_ver"
  fi
}

# Install docker
install_doker() {
  echo_title "Install Docker"
  if command_exists docker; then
    docker_version=$(docker version | grep -oP 'Version:\s+\K[\d.]+' | head -n 1)
    log "Docker already installed with version v$docker_version"
  else
    log "Start installing docker"
    if $mirror; then
      # $sh_c "curl -fsSL https://get.daocloud.io/docker | sh $suf"
      $sh_c "curl -fsSL https://get.docker.com | sh -s - --mirror Aliyun $suf"
    else
      $sh_c "curl -fsSL https://get.docker.com | sh $suf"
    fi
    $sh_c "systemctl enable --now docker $suf"
    $sh_c "docker version $suf"
    docker_version=$(docker version | grep -oP 'Version:\s+\K[\d.]+' | head -n 1)
    log "Successfully installed docker, version v$docker_version"
  fi
}

# Install kubectl
install_kubectl() {
  echo_title "Install Kubectl"
  if command_exists kubectl; then
    kubectl_version=$(kubectl version --client --output=yaml | grep -oP 'gitVersion:\s+v\K[\d.]+')
    log "Kubectl already installed with version v$kubectl_version"
  else
    log "Start installing kubectl"
    kubectl_latest=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
    $sh_c "curl -fsSLO https://dl.k8s.io/release/$kubectl_latest/bin/linux/amd64/kubectl $suf"
    $sh_c "curl -fsSLO https://dl.k8s.io/$kubectl_latest/bin/linux/amd64/kubectl.sha256 $suf"
    $sh_c "echo \"$(cat kubectl.sha256) kubectl\" | sha256sum --check $suf"
    $sh_c "sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl $suf"
    $sh_c "kubectl version --client --output=yaml $suf"
    kubectl_version=$(kubectl version --client --output=yaml | grep -oP 'gitVersion:\s+v\K[\d.]+')
    log "Successfully installed kubectl, version v$kubectl_version"
  fi
}

# Install wireguard(CNI plugin)
install_wireguard() {
  echo_title "Install Wireguard"
  if command_exists wg; then
    wg_version=$(wg --version | grep -oP 'v\K[\d.]+')
    log "Wireguard already installed with version v$wg_version"
  else
    log "Start installing wireguard"
    $sh_c "yum install epel-release https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm -y $suf"
    $sh_c "yum install yum-plugin-elrepo -y $suf"
    $sh_c "yum install kmod-wireguard wireguard-tools -y $suf"
    wg_version=$(wg --version | grep -oP 'v\K[\d.]+')
    log "Successfully installed wireguard, version v$wg_version"
  fi
}

do_start() {
  set_var
  update_kernel
  install_doker
  install_kubectl
  install_wireguard
  log "Successfully installed all requirements"
}

do_start
