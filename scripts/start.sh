#! /bin/bash
set -e

# Deploy k3s script
#

clear

REQUIREMENT_URL=""
K3S_SERVER_URL=""
K3S_AGENT_URL=""
ip=""
mirror=false
node_name=""
user="root"
password=""
server_ip=""
ssh_key=""
k3s_version=""
verbose=false
force=false
kernel="ml"
kilo_location=""
use_docker=true
cri_dockerd=true

command_name=$1
while [ $# -gt 1 ]; do
  case "$2" in
  --mirror) mirror=true ;;
  --verbose) verbose=true ;;
  --kernel) kernel="$3" shift ;;
  --ip) ip="$3" shift ;;
  --server-ip) server_ip="$3" shift ;;
  --user) user="$3" shift ;;
  --password) password="$3" shift ;;
  --ssh-key) ssh_key="$3" ;;
  --k3s-version) k3s_version="$3" shift ;;
  --node-name) node_name="$3" shift ;;
  --kilo-location) kilo_location="$3" shift ;;
  --disable-cri-dockerd) cri_dockerd=false ;;
  --disable-docker) use_docker=false ;;
  -y) force=true ;;
  --*) echo "Illegal option $2" ;;
  esac
  shift $(($# > 1 ? 1 : 0))
done

if $mirror; then
  REQUIREMENT_URL="https://raw.fastgit.org/aliuq/k3sup/master/scripts/requirement.sh"
  K3S_SERVER_URL="https://raw.fastgit.org/aliuq/k3sup/master/scripts/k3s_server.sh"
  K3S_AGENT_URL="https://raw.fastgit.org/aliuq/k3sup/master/scripts/k3s_agent.sh"
else
  REQUIREMENT_URL="https://raw.githubusercontent.com/aliuq/k3sup/master/scripts/requirement.sh"
  K3S_SERVER_URL="https://raw.githubusercontent.com/aliuq/k3sup/master/scripts/k3s_server.sh"
  K3S_AGENT_URL="https://raw.githubusercontent.com/aliuq/k3sup/master/scripts/k3s_agent.sh"
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

do_install() {
  set_var
  if [ $kernel != "ml" ] && [ $kernel != "lt" ]; then kernel="ml"; fi
  requirement_param="--kernel $kernel"
  k3s_param=""
  if $mirror; then
    requirement_param="$requirement_param --mirror"
    k3s_param="$k3s_param --mirror"
  fi
  if $verbose; then
    requirement_param="$requirement_param --verbose"
    k3s_param="$k3s_param --verbose"
  fi
  curl -fsSL $REQUIREMENT_URL | sh -s - $requirement_param
  if [ $? != 0 ]; then
    log "\033[31mFailed to install requirements\033[0m"
    exit 1
  fi
  if ! $use_docker; then k3s_param="$k3s_param --disable-docker"; fi
  if ! $cri_dockerd; then k3s_param="$k3s_param --disable-cri-dockerd"; fi
  if [ $kilo_location ]; then k3s_param="$k3s_param --kilo-location $kilo_location"; fi
  if [ $k3s_version ]; then k3s_param="$k3s_param --k3s-version $k3s_version"; fi
  if [ $node_name ]; then k3s_param="$k3s_param --node-name $node_name"; fi
  if [ $ip ]; then k3s_param="$k3s_param --ip $ip"; fi
  curl -fsSL $K3S_SERVER_URL | sh -s - $k3s_param
  if [ $? != 0 ]; then
    log "\033[31mFailed to start k3s service\033[0m"
    exit 1
  fi
  log "\033[92mDone\033[0m"
}

do_join() {
  set_var
  if [ $kernel != "ml" ] && [ $kernel != "lt" ]; then kernel="ml"; fi

  echo_title "Check sshpass"
  if command_exists sshpass; then
    sshpass_version=$(sshpass -V | grep -oP 'sshpass\s+\K[\d.]+')
    log "sshpass already installed with version v$sshpass_version"
  else
    log "Start installing sshpass"
    $sh_c "yum install sshpass -y $suf"
    log "Successfully installed sshpass"
  fi

  echo_title "Connectcion to $ip"
  if [ ! $ssh_key ]; then
    name=$(echo "$server_ip" | sed s/\\./_/g)
    secrect="$HOME/.ssh/$name"
    if [ -a "$secrect" ]; then
      log "\033[33mThe ssh key $name already exists in $secrect\033[0m"
    else
      log "\033[33mThe ssh key not found and will be generated automatically\033[0m"
      ssh-keygen -t ed25519 -f $secrect -N "" -q
      log "Successfully generated ssh key $name in $secrect"
    fi
  else
    secrect="$ssh_key"
    if [ ! -a "$secrect" ]; then
      log "\033[31mThe ssh key $secrect not found\033[0m"
      exit 1
    fi
  fi

  log "Start copying public key $secrect.pub to $ip"
  option="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
  $sh_c "sshpass -p $password ssh-copy-id -i $secrect.pub $option $user@$ip $suf"
  sed_str="sed -i 's/^#\?PubkeyAuthentication \(yes\|no\)$/PubkeyAuthentication yes/g' /etc/ssh/sshd_config"
  $sh_c "sshpass -p $password ssh $option $user@$ip \"$sed_str && systemctl restart sshd\" $suf"
  sshr="ssh -i $secrect -o ConnectTimeout=60 $option $user@$ip export TERM=xterm-256color;"

  k3s_url="https://$server_ip:6443"
  k3s_token=$(cat /var/lib/rancher/k3s/server/node-token)
  if [ $? != 0 ]; then
    log "\033[31mFailed to get k3s token.\033[0m"
    exit 1
  fi

  requirement_param="--kernel $kernel"
  k3s_param="--k3s-url $k3s_url --k3s-token $k3s_token"
  if $mirror; then
    requirement_param="$requirement_param --mirror"
    k3s_param="$k3s_param --mirror"
  fi
  if $verbose; then
    requirement_param="$requirement_param --verbose"
    k3s_param="$k3s_param --verbose"
  fi

  $sshr "curl -fsSL $REQUIREMENT_URL | sh -s - $requirement_param"
  if [ $? != 0 ]; then
    log "\033[31mFailed to install requirements\033[0m"
    exit 1
  fi
  if ! $use_docker; then k3s_param="$k3s_param --disable-docker"; fi
  if ! $cri_dockerd; then k3s_param="$k3s_param --disable-cri-dockerd"; fi
  if [ $k3s_version ]; then k3s_param="$k3s_param --k3s-version $k3s_version"; fi
  if [ $node_name ]; then k3s_param="$k3s_param --node-name $node_name"; fi
  if [ $ip ]; then k3s_param="$k3s_param --ip $ip"; fi
  $sshr "curl -fsSL $K3S_AGENT_URL | sh -s - $k3s_param"
  if [ $? != 0 ]; then
    log "\033[31mConnection to $ip closed\033[0m"
    exit 1
  fi

  if $use_docker && ! $cri_dockerd; then
    sleep 10
  else
    waitNodeReady $node_name
  fi
  k_loc=$node_name
  if [ $kilo_location ]; then k_loc=$kilo_location; fi
  $sh_c "k3s kubectl annotate node $node_name kilo.squat.ai/location=$k_loc $suf"
  $sh_c "k3s kubectl annotate node $node_name kilo.squat.ai/force-endpoint=$ip:51820 $suf"
  $sh_c "k3s kubectl annotate node $node_name kilo.squat.ai/persistent-keepalive=20 $suf"
  log "Successfully added kilo annotates"
  if $use_docker && ! $cri_dockerd; then
    waitNodeReady $node_name
  fi
  log "\033[92mDone\033[0m"
}

# Need user confirmation to continue
do_confirm() {
  if ! $force; then
    read -p "Do you want to continue? [y/N]" answer
    case "$answer" in
      y|Y) ;;
      *) echo "Aborting."; exit 1 ;;
    esac
  fi
}

# Start install steps
# do_install
case $command_name in
  install) do_confirm; do_install ;;
  join) do_confirm; do_join ;;
  *) echo "Illegal command \033[31m$command_name\033[0m"; exit 1 ;;
esac
