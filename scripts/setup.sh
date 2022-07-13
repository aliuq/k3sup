#! /bin/bash

source <(curl -fsSL https://raw.githubusercontent.com/aliuq/k3sup/master/scripts/install_deno.sh)

deno --version

sleep 2

deno run --allow-all https://raw.githubusercontent.com/aliuq/k3sup/master/src/update-centos-7.x-kernel.ts

# yum update -y && yum install git -y

function version_lt() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; }
