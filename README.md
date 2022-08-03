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

# 国内镜像
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

## 参考链接

* [跨云厂商部署 k3s 集群](https://icloudnative.io/posts/deploy-k3s-cross-public-cloud)
* [基于 K3S+WireGuard+Kilo 搭建跨多云的统一 K8S 集群](https://cloud.tencent.com/developer/article/1985806)

## License

[MIT](./LICENSE)
