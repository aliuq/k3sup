/**
 * Deploy a k3sup cluster
 */
import { yellow, green, cyan } from "https://deno.land/std@0.147.0/fmt/colors.ts";
import { exec, execr } from "https://deno.land/x/liuq@v0.0.1/exec.ts"

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
const hostname = prompt('\nEnter a hostname:')
if (hostname) {
  console.log(`Set hostname to ${green(hostname)}`)
  await exec(`hostnamectl set-hostname ${hostname}`)
}

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

// log('Prepare K3S')
// await exec('curl -fsSL https://rancher-mirror.oss-cn-beijing.aliyuncs.com/k3s/k3s-install.sh | INSTALL_K3S_MIRROR=cn sh -s - --docker')
 

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
