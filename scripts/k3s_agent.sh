#! /bin/bash
set -e

# Install k3s agent
# This script is mainly executed after ssh remote login, and is not recommended to be used alone.
#

verbose=false
mirror=false
use_docker=true
cri_dockerd=true
k3s_version=""
node_name=""
ip=""
k3s_url=""
k3s_token=""
while [ $# -gt 0 ]; do
  case "$1" in
  --mirror) mirror=true ;;
  --verbose) verbose=true ;;
  --disable-docker) use_docker=false ;;
  --disable-cri-dockerd) cri_dockerd=false ;;
  --ip) ip="$2" shift ;;
  --k3s-version) k3s_version="$2" shift ;;
  --node-name) node_name="$2" shift ;;
  --k3s-url) k3s_url="$2" shift ;;
  --k3s-token) k3s_token="$2" shift ;;
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

  suf=""
  if ! $verbose; then
    suf=">/dev/null 2>&1"
  else
    set -x
  fi
}

waitNodeReady() {
  starting=true;
  while $starting; do
  	[[ $(k3s kubectl get nodes "$1" | awk '$2 == "Ready" {print $2}') == "Ready" ]] && starting=false;
	  sleep 1;
  done
}

# Install cri-dockerd, k3s 1.24.0+ required
# https://github.com/Mirantis/cri-dockerd
install_cri_dockerd() {
  echo_title "Install cri-dockerd"
  if command_exists cri-dockerd; then
    cri_version=$(cri-dockerd --version 2>&1 | awk '{print $2}')
    log "cri-dockerd already installed with version v$cri_version"
  else
    lt_version=$(curl --connect-timeout 5 -m 5 -fsSL https://api.github.com/repos/Mirantis/cri-dockerd/releases/latest | grep -oP 'tag_name": "v\K[\d.]+' || echo "0.2.3")
    if $mirror; then
      releases_url="https://hub.fastgit.xyz/Mirantis/cri-dockerd/releases"
      raw_url="https://raw.fastgit.org"
    else
      releases_url="https://github.com/Mirantis/cri-dockerd/releases"
      raw_url="https://raw.githubusercontent.com"
    fi
    log "Start installing cri-dockerd"
    $sh_c "wget $releases_url/download/v$lt_version/cri-dockerd-$lt_version.amd64.tgz -O cri-dockerd.tgz $suf"
    $sh_c "tar -xvf cri-dockerd.tgz $suf"
    $sh_c "cp ./cri-dockerd/cri-dockerd /usr/local/bin/"
    if [ $? != 0 ]; then
      log "\033[0;31mFailed to install cri-dockerd\033[0m"
      exit 1
    fi
    $sh_c "wget $raw_url/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.service $suf"
    $sh_c "wget $raw_url/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.socket $suf"
    $sh_c "cp -a cri-docker.* /etc/systemd/system/"
    $sh_c "sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service"
    $sh_c "systemctl daemon-reload"
    $sh_c "systemctl enable --now cri-docker.service $suf"
    $sh_c "systemctl enable --now cri-docker.socket $suf"
    cri_version=$(cri-dockerd --version 2>&1 | awk '{print $2}')
    log "Successfully installed cri-dockerd, version v$cri_version"
  fi
}

# Install k3s as a agent ndoe
install_k3s_agent() {
  echo_title "Install K3S as a agent"
  if command_exists k3s; then
    log "K3S already installed with version v$(k3s -v | grep -oP 'k3s version\s+v\K.*')"
  else
    log "Start installing k3s"
    k3s_run_str="curl -fsSL"
    if $mirror; then
      k3s_run_str="$k3s_run_str https://rancher-mirror.oss-cn-beijing.aliyuncs.com/k3s/k3s-install.sh"
      k3s_run_str="$k3s_run_str | INSTALL_K3S_MIRROR=cn"
    else
      k3s_run_str="$k3s_run_str https://get.k3s.io |"
    fi
    if [ $k3s_version ]; then
      k3s_run_str="$k3s_run_str INSTALL_K3S_VERSION=$k3s_version"
    fi
    agent_name="$(hostname)"
    if [ $node_name ]; then
      agent_name="$node_name"
      k3s_run_str="$k3s_run_str K3S_NODE_NAME=$agent_name"
    fi
    k3s_run_str="$k3s_run_str K3S_URL=$k3s_url K3S_TOKEN=$k3s_token INSTALL_K3S_EXEC=\""
    if $use_docker; then
      if $cri_dockerd; then
        install_cri_dockerd
        k3s_run_str="$k3s_run_str --container-runtime-endpoint unix:///var/run/cri-dockerd.sock"
      else
        k3s_run_str="$k3s_run_str --docker"
      fi
    fi
    k3s_run_str="$k3s_run_str --node-external-ip $ip --kube-proxy-arg metrics-bind-address=0.0.0.0\""
    $sh_c "$k3s_run_str sh $suf"
    log "Successfully installed k3s, wait for node ready"
  fi
}

do_start() {
  set_var
  install_k3s_agent
}

do_start
