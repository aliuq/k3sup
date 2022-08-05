# k3sup

[WIP] 快速安装跨云厂商 K3S 集群

## 安装

```bash
# 安装 k3s server
sh <(curl -fsSL https://raw.githubusercontent.com/aliuq/k3sup/master/scripts/start.sh) install \
--ip $(curl -fsSL ip.llll.host) --node-name master
# 添加 K3S 节点
sh <(curl -fsSL https://raw.githubusercontent.com/aliuq/k3sup/master/scripts/start.sh) join \
--ip <Node Public IP> --server-ip $(curl -fsSL ip.llll.host) --node-name node-1 --password <Node Password>

# === 国内安装 ===

# 安装 k3s server
sh <(curl -fsSL https://raw.llll.host/aliuq/k3sup/master/scripts/start.sh) install \
--ip $(curl -fsSL ip.llll.host) --node-name master --mirror
# 添加 K3S 节点
sh <(curl -fsSL https://raw.llll.host/aliuq/k3sup/master/scripts/start.sh) join \
--ip <Node Public IP> --server-ip $(curl -fsSL ip.llll.host) \
--node-name node-1 --password <Node Password> --mirror
```

## Options

### install options

* `--ip`: 节点 IP
* `--node-name`: (可选)节点名称
* `--kernel`: (可选)内核版本, 默认为 `ml` 版本
* `--k3s-version`: (可选)k3s 版本, 默认为标准版本
* `--kilo-location`: (可选)kilo 区域, 默认为 `node-name`
* `--mirror`: (可选)使用镜像
* `--disable-cri-dockerd`: (可选)禁用 cri-dockerd，使用该选项时，必须指定 `--k3s-version` 且需要小于 v1.24 版本
* `--disable-docker`: (可选)禁用 docker
* `--verbose`: (可选)显示详细信息
* `-y`: (可选)确认所有选项

### join options

* `--ip`: 节点 IP
* `--node-name`: 节点名称
* `--server-ip`: k3s 服务器 IP
* `--password`: 节点密码
* `--user`: (可选)节点用户名，默认为 `root`
* `--ssh-key`: (可选)使用 ssh key
* `--kernel`: (可选)内核版本, 默认为 `ml` 版本
* `--k3s-version`: (可选)k3s 版本, 默认为标准版本
* `--mirror`: (可选)使用镜像
* `--disable-cri-dockerd`: (可选)禁用 cri-dockerd，使用该选项时，必须指定 `--k3s-version` 且需要小于 v1.24 版本
* `--disable-docker`: (可选)禁用 docker
* `--verbose`: (可选)显示详细信息
* `-y`: (可选)确认所有选项

## FAQ

安装过程根据网络情况，可能会花费一定时间，5~10分钟左右为正常现象，如果超过这个时间，请退出安装程序，并添加 `--verbose` 查看详细信息，如果确有错误信息，请提交 issue

由于国内网络问题，在使用默认命令安装后，截止到2022/08/05，当前稳定版本已经切换到`v1.24.3+k3s1`，该版本无法拉取镜像`k8s.gcr.io/pause:xxx`，所以会导致安装命令一直在等待中，此时推荐在等待10s之后关闭安装程序，然后执行以下命令

```bash
# 首先需要知道是哪个版本的镜像无法拉取
kubectl get pod -n kube-system | grep kilo- | awk '{print $1}' | xargs kubectl describe -n kube-system pod | grep 'failed pulling image'
# 出现下面的错误，则说明镜像拉取失败，需要手动拉取镜像，保证版本一致
# error: code = Unknown desc = failed pulling image "k8s.gcr.io/pause:3.6"

# 利用镜像拉取 pause
docker pull registry.aliyuncs.com/google_containers/pause:3.6
# 镜像重命名
docker tag registry.aliyuncs.com/google_containers/pause:3.6 k8s.gcr.io/pause:3.6
# 删除旧镜像
docker rmi registry.aliyuncs.com/google_containers/pause:3.6
```

如果指定 k3s 版本在 v1.24 以下，则不需要考虑这点，因为 rancher 提供了镜像，但 v1.24 版本以上还未使用，同时也不需要考虑 cri-dockerd，因为从 v1.24 开始才弃用 docker，以 v1.23.9 为例

```bash
# 安装 k3s server
sh <(curl -fsSL https://raw.llll.host/aliuq/k3sup/master/scripts/start.sh) install \
--ip $(curl -fsSL ip.llll.host) --node-name master --mirror \
--k3s-version "v1.23.9+k3s1" --disable-cri-dockerd
# 添加 K3S 节点
sh <(curl -fsSL https://raw.llll.host/aliuq/k3sup/master/scripts/start.sh) join \
--ip <Node Public IP> --server-ip $(curl -fsSL ip.llll.host) \
--node-name node-1 --password <Node Password> --mirror \
--k3s-version "v1.23.9+k3s1" --disable-cri-dockerd
```

## 参考链接

* [跨云厂商部署 k3s 集群](https://icloudnative.io/posts/deploy-k3s-cross-public-cloud)
* [基于 K3S+WireGuard+Kilo 搭建跨多云的统一 K8S 集群](https://cloud.tencent.com/developer/article/1985806)

## License

[MIT](./LICENSE)
