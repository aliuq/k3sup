/**
 * Deploy a k3sup cluster
 */
import { yellow, green, cyan, bold, red } from "https://deno.land/std@0.147.0/fmt/colors.ts";
import { exec, execr } from "https://deno.land/x/liuq@v0.0.2-beta.1/exec.ts"
import { wrapPrompt } from "https://deno.land/x/liuq@v0.0.2-beta.1/utils.ts"


interface Options {
  force?: boolean
  agent?: boolean
}
const options: Options = {}

Deno.args.map(s => {
  if (['--force', '-y'].includes(s)) {
    options.force = true
  }
  if (['--agent'].includes(s)) {
    options.agent = true
  }
})

const apps: Record<string, { path?: string, version?: string }> = {
  docker: {},
  kubectl: {},
  helm: {}
}

for await (const app of Object.keys(apps)) {
  const path = await execr(`which ${app}`)
  if (path) {
    let version = ''
    if (app === 'docker') {
      const ver = await execr('docker --version') as string
      version = 'v' + ver.match(/Docker version ([\d.]+)/)?.[1]
    } else if (app === 'kubectl') {
      const ver = await execr('kubectl version --client --output=yaml') as string
      version = 'v' + ver.match(/gitVersion: v(.*?)\r?\n/)?.[1]
    } else if (app === 'helm') {
      const ver = await execr('helm version') as string
      version = 'v' + ver.match(/Version:"v([\d.]+)"/)?.[1]
    }
    apps[app] = { path, version }
  } else {
    apps[app] = { path: '', version: '' }
  }
}

console.log(yellow('\nPrepare Info'))
console.table(apps)

const log = (msg: string) => console.log(green(msg))
const logTitle = (msg: string) => console.log(cyan(`----------------- ${msg} -----------------`))

const isChina = await checkInChina()

// ----------------- Hostname -----------------
logTitle('Hostname')
const hostname = await wrapPrompt('\nSet a hostname, it will be used as a node name:')
console.log(`Set hostname to ${green(hostname)}`)
await exec(`hostnamectl set-hostname ${hostname}`)

// ----------------- Docker -----------------
logTitle('Docker')
let enableRemoveDocker = true
if (apps.docker?.version) {
  const removeDocker = prompt('Are you sure to remove the old docker version? [y/n]')
  enableRemoveDocker = (removeDocker && removeDocker.toLowerCase() === 'y') as boolean
}

if (enableRemoveDocker) {
  log(' - Remove existing docker')
  await exec('yum -y remove docker-*')

  log(' - Install docker (Need a little time)')
  if (isChina) {
    await exec('curl -sSL https://get.daocloud.io/docker | sh')
  } else {
    await exec('curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun')
  }

  log(' - Setup startup')
  await exec('systemctl enable --now docker')
}
  
log(' - Check')
await exec('docker ps')
 
logTitle('Kubectl')
const kubectlLatest = await execr('curl -fsSL https://dl.k8s.io/release/stable.txt')
console.log(yellow(`Kubectl stable version is ${kubectlLatest}`));
let updateKubectl = 'y'
if (apps.kubectl?.path) {
  updateKubectl = prompt('Are you sure to udpate kubectl to the latest version? [y/n]') as string
}
if (updateKubectl && updateKubectl.toLowerCase() === 'y') {
  log(' - Install kubectl binary')
  await exec(`curl -fsSLO "https://dl.k8s.io/release/${kubectlLatest}/bin/linux/amd64/kubectl"`)
  log(' - Validate the binary')
  await exec(`curl -fsSLO "https://dl.k8s.io/${kubectlLatest}/bin/linux/amd64/kubectl.sha256"`)
  const validResult = await execr('echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check')
  log(validResult + '\n')
  log(' - Install kubectl')
  await exec('sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl')
  await exec('kubectl version --output=yaml')
}

logTitle('Wireguard')
await exec('yum update -y')
await exec('yum install epel-release https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm -y')
await exec('yum install yum-plugin-elrepo -y')
await exec('yum install kmod-wireguard wireguard-tools -y')

logTitle('K3S')
let ipv4 = await execr('curl -L https://api.ipify.org')
if (options.agent) {
  console.log(yellow(bold(`In agent, needs K3S_URL and K3S_TOKEN variable`)))
  console.log(yellow('Tips:\n'))
  console.log(cyan('K3S_URL is your master address, e.g. https://xx.xx.xx.xx:6443'))
  console.log(cyan('K3S_TOKEN is from your master'))
  // curl -sfL https://rancher-mirror.oss-cn-beijing.aliyuncs.com/k3s/k3s-install.sh | INSTALL_K3S_MIRROR=cn K3S_URL="https://xx.xx.xx.xx:6443" K3S_TOKEN="xxxx::server:xxxx" sh -s - --docker
  if (isChina) {
    await exec('curl -fsSL https://rancher-mirror.oss-cn-beijing.aliyuncs.com/k3s/k3s-install.sh | INSTALL_K3S_MIRROR=cn sh -s - --docker')
  } else {
    await exec('curl -sfL https://get.k3s.io | sh -s - --docker')
  }
} else {
  const realIP = prompt(`\nGot IP ${green(ipv4 as string)}, if it's wrong, please enter the correct IP:`)
  if (realIP) {
    ipv4 = realIP
  }
  if (isChina) {
    await exec('curl -fsSL https://rancher-mirror.oss-cn-beijing.aliyuncs.com/k3s/k3s-install.sh | INSTALL_K3S_MIRROR=cn sh -s - --docker')
  } else {
    await exec('curl -sfL https://get.k3s.io | sh -s - --docker')
  }
  log('Write configuation to [/etc/systemd/system/k3s.service]')
  await Deno.writeTextFile('/etc/systemd/system/k3s.service', `
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
  --tls-san ${ipv4} \
  --node-ip ${ipv4} \
  --node-external-ip ${ipv4} \
  --no-deploy servicelb \
  --flannel-backend wireguard \
  --kube-proxy-arg "proxy-mode=ipvs" "masquerade-all=true" \
  --kube-proxy-arg "metrics-bind-address=0.0.0.0"
  `)
  await exec('systemctl enable k3s --now')
  log('Overwrite public IP')
  await exec(`kubectl annotate nodes ${hostname} flannel.alpha.coreos.com/public-ip-overwrite=${ipv4}`)
  log('View [wireguard] connection status')
  await exec('wg show flannel.1')
}

// ------------------------- Functions -------------------------
async function checkInChina() {
  try {
    const ipFetch = await fetch('http://ip-api.com/json/')
    const ip = await ipFetch.json()
    return ip.countryCode === 'CN'
  // deno-lint-ignore no-explicit-any
  } catch (_e: any) {
    return true
  }
}
