#! /bin/bash
set -e

# Install k3s server

GET_IP_URL=${GET_IP_URL:-"ip.llll.host"}

verbose=false
mirror=false
use_docker=true
cri_dockerd=false
kilo_location=""
k3s_version="v1.23.9+k3s1"
node_name=""
ip=""
dry_run=false
while [ $# -gt 0 ]; do
  case "$1" in
  --mirror) mirror=true ;;
  --verbose) verbose=true ;;
  --disable-docker) use_docker=false ;;
  --cri-dockerd) cri_dockerd=true ;;
  --dry-run) dry_run=true ;;
  --ip) ip="$2" shift ;;
  --k3s-version) k3s_version="$2" shift ;;
  --node-name) node_name="$2" shift ;;
  --kilo-location) kilo_location="$2" shift ;;
  --*) echo "Illegal option $1" ;;
  esac
  shift $(($# > 0 ? 1 : 0))
done

if [ ! $ip ]; then
  ip=$(curl -fsSL $GET_IP_URL)
  if [ $? != 0 ]; then
    echo "Failed to get ip from $GET_IP_URL, please input ip manually!"
    exit 1
  fi
fi

if $mirror; then
  HUB_URL=${HUB_URL:-"https://hub.llll.host"}
  RAW_URL=${RAW_URL:-"https://raw.llll.host"}
else
  HUB_URL="https://github.com"
  RAW_URL="https://raw.githubusercontent.com"
fi

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
    log "Start installing cri-dockerd"
    $sh_c "wget $HUB_URL/Mirantis/cri-dockerd/releases/download/v$lt_version/cri-dockerd-$lt_version.amd64.tgz -O cri-dockerd.tgz $suf"
    $sh_c "tar -xvf cri-dockerd.tgz $suf"
    $sh_c "cp ./cri-dockerd/cri-dockerd /usr/local/bin/"
    if [ $? != 0 ]; then
      log "\033[0;31mFailed to install cri-dockerd\033[0m"
      exit 1
    fi
    $sh_c "wget $RAW_URL/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.service $suf"
    $sh_c "wget $RAW_URL/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.socket $suf"
    $sh_c "cp -a cri-docker.* /etc/systemd/system/"
    $sh_c "sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service"
    $sh_c "systemctl daemon-reload"
    $sh_c "systemctl enable --now cri-docker.service $suf"
    $sh_c "systemctl enable --now cri-docker.socket $suf"
    cri_version=$(cri-dockerd --version 2>&1 | awk '{print $2}')
    log "Successfully installed cri-dockerd, version v$cri_version"
  fi
}

# Install k3s as a server ndoe
install_k3s_server() {
  echo_title "Install K3S server"
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
    k3s_run_str="$k3s_run_str INSTALL_K3S_VERSION=$k3s_version sh -s - server --cluster-init"

    master_name="$(hostname)"
    if [ $node_name ]; then
      master_name="$node_name"
    fi
    k3s_run_str="$k3s_run_str --node-name $master_name"
    if $use_docker; then
      if $cri_dockerd; then
        if ! $dry_run; then
          install_cri_dockerd
        fi
        k3s_run_str="$k3s_run_str --container-runtime-endpoint unix:///var/run/cri-dockerd.sock"
      else
        k3s_run_str="$k3s_run_str --docker"
      fi
    fi
    k3s_run_str="$k3s_run_str --tls-san $ip --node-external-ip $ip --flannel-backend none"
    k3s_run_str="$k3s_run_str --kube-proxy-arg metrics-bind-address=0.0.0.0"
    if $dry_run; then
      log "k3s run command: \033[33m$k3s_run_str\033[0m"
      exit 2
    else
      $sh_c "$k3s_run_str $suf"
      if [ $? != 0 ]; then
        log "\033[31mFailed to start k3s service, please rerun this script with --verbose to see details info\033[0m"
        exit 1
      fi
    fi
    sleep 10
    log "Successfully installed k3s"
    $sh_c "mkdir ~/.kube -p && ln /etc/rancher/k3s/k3s.yaml ~/.kube/config && chmod 600 ~/.kube/config $suf"
    log "Successfully added k3s to the PATH"
    k_loc=$master_name
    if [ $kilo_location ]; then k_loc=$kilo_location; fi
    $sh_c "k3s kubectl annotate node $master_name kilo.squat.ai/location=$k_loc $suf"
    $sh_c "k3s kubectl annotate node $master_name kilo.squat.ai/force-endpoint=$ip:51820 $suf"
    $sh_c "k3s kubectl annotate node $master_name kilo.squat.ai/persistent-keepalive=20 $suf"
    log "Successfully added kilo annotates"
    $sh_c "k3s kubectl apply -f $RAW_URL/squat/kilo/main/manifests/crds.yaml $suf"
    $sh_c "k3s kubectl apply -f $RAW_URL/squat/kilo/main/manifests/kilo-k3s.yaml $suf"
    log "Successfully applied kilo manifests"
    log "Waiting for k3s to be ready"
    waitNodeReady $master_name
  fi
}

do_start() {
  set_var
  install_k3s_server
}

do_start
