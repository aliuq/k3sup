/**
 * Centos 7.x Update kernel
 * 
 * Command:
 * 
 * `deno run --allow-all update-centos-7.x-kernel.ts`
 */

import { yellow, red, green } from "https://deno.land/std@0.147.0/fmt/colors.ts";
import { exec, execr } from "https://deno.land/x/liuq@v0.0.1/exec.ts";

const kernel = await execr("uname -r");
console.log('\nCurrent kernel version: ' + yellow(kernel as string));

const ensureUpdate = prompt('Are you sure to update kernel? (y/n)');
if (!ensureUpdate || ensureUpdate.toLowerCase() !== 'y') {
  log('Goodbye!')
  Deno.exit(0)
}

// Update yum source repo
log('Update yum source repo')
await exec('yum -y update')

// Load the public key of the ELRepo
log('Load the public key of the ELRepo')
await exec('rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org')

// Install or update ELRepo
try {
  await exec('yum --disablerepo="*" --enablerepo="elrepo-kernel" list available')
  log('\nPreparing install ELRepo')
  await exec('yum install -y https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm')
} catch (_e: unknown) {
  log('\nPreparing udpate ELRepo')
  await exec('rpm -Uvh https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm')
}

// Load elrepo-kernel metadata
log('Load elrepo-kernel metadata')
await exec('yum --disablerepo=\* --enablerepo=elrepo-kernel repolist')

// Select kernel LTS or Stable
const kernelVersion = prompt('\nChoose a kernel type install 1)LTS or 2)Stable? (1/2)', '1');
const kernelName = kernelVersion === '1' ? 'kernel-lt' : 'kernel-ml'
const kernelTip = kernelVersion === '1' ? red('LTS') : red('Stable')
log(`Install kernel ${kernelTip}`)
await exec(`yum --disablerepo=\* --enablerepo=elrepo-kernel install ${kernelName} -y`)

// Setup default
log('Setup default')
await exec('sed -i "s/GRUB_DEFAULT=saved/GRUB_DEFAULT=0/g" /etc/default/grub')

// Generate grub file
log('Generate grub file')
await exec('grub2-mkconfig -o /boot/grub2/grub.cfg')

// Remove old kernel tools
log('Remove old kernel tools')
await exec('yum remove -y kernel-tools-libs.x86_64 kernel-tools.x86_64')

// Install newest kernel tools
log('Install newest kernel tools')
await exec('yum --disablerepo=\* --enablerepo=elrepo-kernel install -y kernel-lt-tools.x86_64')

// Reboot
log('Wait for 5 seconds to reboot')
for await (const n of [5, 4, 3, 2, 1]) {
  await sleep(1000)
  console.log(n);
}
log('Reboot now!')
await exec('reboot')

function log(msg: string) {
  console.log(green(msg));
}
function sleep(ms: number) {
  return new Promise(resolve => {
    setTimeout(resolve, ms);
  })
}
