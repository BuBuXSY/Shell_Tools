# 🚀 各类一键脚本 — 把复杂的东西简单化  
*(以下均在 Debian 系和 OpenWrt 系统上测试，其他系统需自行调整)*

---

### ⚙️ Linux 系统性能优化  
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/kernel_optimization.sh)


### 🦄 Debian 系自动更新 Nginx（支持 QUIC、Brotli、OCSP、GEOIP2、KTLS）
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/Auto_Upgrade_Nginx.sh)

### 🌍 更新 Country.mmdb 供 Nginx GEOIP2 使用
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/update_Country.sh)
提示：

默认路径：/usr/share/GeoIP（请提前 mkdir -p /usr/share/GeoIP）

支持企业微信推送（需替换脚本内 webhook Key）

可通过 crontab -e 添加定时任务，如：
0 4 * * * /root/update_Country.sh（每日凌晨4点执行）

### 🔍 查询访问服务器 IP 并显示地理位置（防刷 DNS）
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/search_ip.sh
)

依赖：

需要安装 nali

确保 Nginx 开启了 access.log 功能

支持企业微信推送（替换 webhook Key）

### 🔐 服务器证书申请与安装（默认 ECC，支持多 CA，限 Nginx）
命令：
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/install_cert.sh
)

自动化证书申请，简化流程，一键搞定！

### 🌐 测试 DNS 服务器是否支持 EDNS（默认用 AdGuard 推荐列表）
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/EDNS_TEST.sh
)

依赖 q，脚本会自动检测并安装。支持 Debian、RedHat、OpenWrt、MacOS。

### ⏰ 定时收集 MOSDNS 重复查询域名，优化查询压力
···shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/collect_repeat_dns.sh
)

搭配 MOSDNS 使用，开启 mosdns.log info 级别，默认路径 /etc/mosdns/mosdns.log。
建议定时任务示例：
0 */12 * * * /etc/mosdns/collect_repeat_dns.sh
脚本会自动清理日志，无需担心日志文件过大。

### 🚀 Frp 最新版自动安装与更新（支持 amd64 和 arm64）
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/update_frp.sh
)

脚本自动判断系统架构，自动安装最新版 frps 或 frpc，升级无须选择。
