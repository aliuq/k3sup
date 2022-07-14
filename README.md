# k3sup

[WIP] 快速安装跨云厂商K3S集群

## 安装

```bash
# master
sh <(curl -fsSL https://raw.githubusercontent.com/aliuq/k3sup/master/scripts/setup.sh) --hostname master --verbose

# 等待 master 安装完成后，复制控制台打印的命令，进入 node 节点，进行安装
sh <(curl -fsSL https://raw.githubusercontent.com/aliuq/k3sup/master/scripts/setup1.sh) --verbose --agent --k3s_url $master_url --k3s_token $master_token --hostname <New Node Name>

# node 节点安装后，需要进入 master 节点，添加下面注解
kubectl annotate nodes <node> flannel.alpha.coreos.com/public-ip-overwrite=<node_pub_ip>
```

## 参考链接

+ [跨云厂商部署 k3s 集群](https://icloudnative.io/posts/deploy-k3s-cross-public-cloud)

## License

[MIT](./LICENSE)
