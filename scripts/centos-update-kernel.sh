#! /bin/bash
set -e
#
# Update kernel version
#

log() {
  echo -e "[INFO] [$(date "+%Y-%m-%d %H:%M:%S")] $1"
}

version_lt() {
  test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1";
}

KERNEL_LIMIT_VERSION=5.4.205
kernel_ver=$(uname -r | grep -oP "^[\d.]+")
if version_lt $kernel_ver $KERNEL_LIMIT_VERSION; then
  log "The current version v$kernel_ver is less than v$KERNEL_LIMIT_VERSION"
  log "Start to update kernel"
  rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
  rpm -Uvh https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
  yum --disablerepo=\* --enablerepo=elrepo-kernel repolist
  yum --disablerepo=\"*\" --enablerepo=\"elrepo-kernel\" list available
  yum --disablerepo=\* --enablerepo=elrepo-kernel install kernel-ml -y
  sed -i \"s/GRUB_DEFAULT=saved/GRUB_DEFAULT=0/g\" /etc/default/grub
  grub2-mkconfig -o /boot/grub2/grub.cfg
  yum remove -y kernel-tools-libs.x86_64 kernel-tools.x86_64
  yum --disablerepo=\* --enablerepo=elrepo-kernel install -y kernel-ml-tools.x86_64
  reboot
else
  log "The current version v$kernel_ver is greater than v$KERNEL_LIMIT_VERSION"
  log "No need to update kernel"
fi
