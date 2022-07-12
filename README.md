# k3sup

[WIP]快速安装跨云厂商K3S集群

## Install deno

[官方安装地址](https://deno.land/manual/getting_started/installation)

安装脚本主要是用在 Centos 7.x 版本上，因为 Centos 7.x 版本的系统 libc 的版本为[2.17](https://deno.js.cn/t/topic/611)，而 deno 需要2.18版本以上，下面脚本主要是安装 2.18 版本的 libc，这个过程需要持续很长时间，另一个是采用了[加速 deno 安装的镜像源](https://github.com/denocn/deno_install)。

```bash
source <(curl -fsSL https://raw.githubusercontent.com/aliuq/k3sup/master/scripts/install_deno.sh)
```
