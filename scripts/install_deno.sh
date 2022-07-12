#! /bin/bash

ldd=$(ldd --version | grep 'ldd (GNU libc) ' | head -n 1)
lddver=${ldd:15}

function version_lt() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; }

if version_lt $lddver '2.18'; then
  mkdir /temp_down -p && cd /temp_down
  wget https://ftp.gnu.org/gnu/glibc/glibc-2.18.tar.gz
  tar -zxvf glibc-2.18.tar.gz

  cd glibc-2.18 && mkdir build
  cd build
  ../configure --prefix=/usr --disable-profile --enable-add-ons --with-headers=/usr/include --with-binutils=/usr/bin
  make && make install

  cd ~
  rm -rf /temp_down
fi

# curl -fsSL https://deno.land/x/install/install.sh | sh
curl -fsSL https://x.deno.js.cn/install.sh | sh

export DENO_INSTALL="/root/.deno"
export PATH="$DENO_INSTALL/bin:$PATH"
