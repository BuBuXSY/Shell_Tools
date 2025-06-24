## 各类一键脚本，把复杂的东西简单化（以下内容都在Debian系和Openwrt系统上进行测试，Centos等红帽系，Arch等其他操作系统部分支持如不支持请自行更改)
### 自建DNS可公益使用，切勿传播，且用且珍惜，华东地区,国内外分流解析 实时监控图

DNS运行状态实时监控 [点击这里](https://grafana.bubujun.top/grafana/d/w-Sdzen4k/mosdns-v4?orgId=1&refresh=5s)
 
#
### 网络性能优化 感谢MapleCool大佬提供 ###
``` shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/kernel_optimization.sh)
``` 
#
### 适用于Debian系的一键自动更新Nginx脚本加入了QUIC Brotli OCSP GEOIP2 KTLS的支持 感谢Zhang Xin提供 并由BuBuXSY进行修改	
``` bash
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/Auto_Upgrade_Nginx.sh)
``` 
#
### 更新Country.mmdb给nginx的GEOIP2模块用
``` shell 
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/update_Country.sh)
```
#### 默认保存的文件地址在/usr/share/GeoIP文件夹内(请先提前创建好文件夹mkdir -p /usr/share/GeoIP)也可将本文件，保存在本地之后利用corntab -e 来执行定时更新运行。 0 4 * * *（每天4点运行一次） /root/update_Country.sh (默认使用的是[LoyalSoldier](https://github.com/Loyalsoldier/geoip)的库)
#
### 用于查询通过Nginx访问服务器的IP的并显示其地理位置，用于辨别恶意刷DNS的 访问次数并进行排列数量多的优先 第一个是查询登陆成功的IP与数量
``` shell 
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/search_ip.sh)
``` 
#### 使用前现需要确定安装 [nali](https://github.com/zu1k/nali) 并且开启nginx的access.log功能
# 
### 服务器证书申请与安装（默认ECC并且可选择CA供应商 仅支持Nginx）
``` shell 
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/install_cert.sh)
``` 
#### 自动化流水线 削减了流程 
# 

### 用来测试常见DNS服务器（默认是Adguard的DNS推荐列表中的DNS）是否支持EDNS
``` shell  
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/EDNS_TEST.sh) 
``` 
#### 本脚本需要 [q](https://github.com/natesales/q) 的支持 脚本运行时会自动判断系统 自动安装 支持Debian系 RedHat系 Openwrt系 MacOS（M1/2）
#
### 定时收集mosdns查询中的重复域名，搭配配置文件将重复域名的TTL时间变成变长从而mosdns的查询压力使用负担并加快查询速度
``` shell 
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/collect_repeat_dns.sh)
``` 
#### 需要搭配 [MOSDNS](https://github.com/IrineSistiana/mosdns) 使用，并开启mosdns.log（建议选择info，并且日志默认位置在/etc/mosdns/mosdns.log，默认规则存放地址为/etc/mosdns/rules/下）使用，如需定时可类似于 0 */12 * * * /etc/mosdns/collect_repeat_dns.sh（mosdns。log的大小不用担心，脚本会定时自动删除mosdns.log）
#
### Frp的更新安装脚本，支持amd64与arm64，脚本会自行进行判断且安装最新版本的frp，用户可选择安装frps还是frpc，升级不需要选择会自行判断
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/update_frp.sh)
```
#





