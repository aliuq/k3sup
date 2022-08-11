# k3sup

[WIP] 快速安装跨云厂商 K3S 集群

## 安装

默认 K3S 安装版本为 `v1.23.9+k3s1`

```bash
# 安装 k3s server
sh <(curl -fsSL https://raw.githubusercontent.com/aliuq/k3sup/master/scripts/start.sh) install \
--node-name server1 --verbose
# 添加 K3S 节点 agent
sh <(curl -fsSL https://raw.githubusercontent.com/aliuq/k3sup/master/scripts/start.sh) join \
--ip <Node Public IP> --node-name node1 --password <Node Password> --verbose
# 添加 K3S 节点 server
sh <(curl -fsSL https://raw.githubusercontent.com/aliuq/k3sup/master/scripts/start.sh) join \
--server --ip <Node Public IP> --node-name server2 --password <Node Password> --verbose

# === 国内安装 ===

# 安装 k3s server
sh <(curl -fsSL https://raw.llll.host/aliuq/k3sup/master/scripts/start.sh) install \
--node-name server1 --mirror --verbose
# 添加 K3S 节点 agent
sh <(curl -fsSL https://raw.llll.host/aliuq/k3sup/master/scripts/start.sh) join \
--ip <Node Public IP> --node-name node1 --password <Node Password> --mirror --verbose
# 添加 K3S 节点 server
sh <(curl -fsSL https://raw.llll.host/aliuq/k3sup/master/scripts/start.sh) join \
--server --ip <Node Public IP> --node-name server2 --password <Node Password> --mirror --verbose
```

## Options

### install options

* `--ip`: (可选)节点 IP
* `--node-name`: (可选)节点名称
* `--kernel`: (可选)内核版本, 默认为 `ml` 版本
* `--k3s-version`: (可选)k3s 版本, 默认为标准版本
* `--kilo-location`: (可选)kilo 区域, 默认为 `node-name`
* `--mirror`: (可选)使用镜像
* `--cri-dockerd`: (可选)启用 cri-dockerd，使用该选项时，需指定 `--k3s-version` 且需要大于 v1.24.0 版本
* `--disable-docker`: (可选)禁用 docker
* `--verbose`: (可选)显示详细信息
* `--dry-run`: (可选)仅打印 k3s 安装命令
* `-y`: (可选)确认所有选项

### join options

* `--ip`: 节点 IP
* `--node-name`: 节点名称
* `--password`: 节点密码
* `--server-ip`: (可选)k3s 服务器 IP
* `--user`: (可选)节点用户名，默认为 `root`
* `--ssh-key`: (可选)使用 ssh key
* `--kernel`: (可选)内核版本, 默认为 `ml` 版本
* `--k3s-version`: (可选)k3s 版本, 默认为标准版本
* `--mirror`: (可选)使用镜像
* `--server`: (可选)将节点作为 k3s server
* `--cri-dockerd`: (可选)启用 cri-dockerd，使用该选项时，需指定 `--k3s-version` 且需要大于 v1.24.0 版本
* `--disable-docker`: (可选)禁用 docker
* `--verbose`: (可选)显示详细信息
* `--dry-run`: (可选)仅打印 k3s 安装命令
* `-y`: (可选)确认所有选项

## FAQ

安装过程根据网络情况，可能会花费一定时间，5~10分钟左右为正常现象，如果超过这个时间，请退出安装程序，并添加 `--verbose` 查看详细信息，如果确有错误信息，请提交 issue

由于国内网络问题，截止到2022/08/05，如果使用 `v1.24` 以上版本，此后的版本无法拉取镜像`k8s.gcr.io/pause:xxx`，所以会导致安装命令一直在等待中，此时推荐在等待10s之后关闭安装程序，然后执行以下命令

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

## 参考链接

* [跨云厂商部署 k3s 集群](https://icloudnative.io/posts/deploy-k3s-cross-public-cloud)
* [基于 K3S+WireGuard+Kilo 搭建跨多云的统一 K8S 集群](https://cloud.tencent.com/developer/article/1985806)

## License

[MIT](./LICENSE)
