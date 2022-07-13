#! /bin/bash

clear
echo
echo "###################################################################"
echo "#                                                                 #"
echo "# Centos 7.x fast install K3S                                     #"
echo "# Author: AliuQ                                                   #"
echo "#                                                                 #"
echo "###################################################################"
echo

# Colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

version_lt() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; }

update_yum() { yum update -y }

echo_title() {
  echo
  echo "======================= 🧡 $1 ======================="
  echo
}

update_kernel() {
  echo_title Update Kernel
  rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
}
