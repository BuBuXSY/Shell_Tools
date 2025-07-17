# 🚀 各类一键脚本 — 把复杂的东西简单化  
*(以下均在 Debian 系和 OpenWrt 系统上测试，其他系统需自行调整)*


### ⚙️ Linux 系统性能优化  

```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/kernel_optimization.sh)
```

### 🦄 Debian 系自动更新 Nginx（支持 QUIC、Brotli、OCSP、GEOIP2、KTLS）

```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/Auto_Upgrade_Nginx.sh)
```
### 🌍 更新 Country.mmdb 供 Nginx GEOIP2 使用
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/update_Country.sh)
```
- 提示：
- 默认路径：/usr/share/GeoIP（请提前 mkdir -p /usr/share/GeoIP）
- 支持企业微信推送（需替换脚本内 webhook Key）
- 可通过 crontab -e 添加定时任务，如：
- 0 4 * * * /root/update_Country.sh（每日凌晨4点执行）

### 🔍 查询访问服务器 IP 并显示地理位置（防刷 DNS）
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/search_ip.sh
)
```
#### 依赖：

- 需要安装 nali

- 确保 Nginx 开启了 access.log 功能

- 支持企业微信推送（替换 webhook Key）

### 🔐 服务器证书申请与安装（默认 ECC，支持多 CA，限 Nginx）
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/install_cert.sh
)
```
- 自动化证书申请，简化流程，一键搞定！

### 🌐 测试 DNS 服务器是否支持 EDNS（默认用 AdGuard 推荐列表）
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/EDNS_TEST.sh
)
```
- 依赖 q，脚本会自动检测并安装。支持 Debian、RedHat、OpenWrt、MacOS。

### ⏰ 定时收集 MOSDNS 重复查询域名，优化查询压力
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/collect_repeat_dns.sh
)
```
- 搭配 MOSDNS 使用，开启 mosdns.log info 级别，默认路径 /etc/mosdns/mosdns.log。
- 建议定时任务示例：
- 0 */12 * * * /etc/mosdns/collect_repeat_dns.sh
- 脚本会自动清理日志，无需担心日志文件过大。

### 🚀 Frp 最新版自动安装与更新（支持 amd64 和 arm64）
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/update_frp.sh
)
```
- 脚本自动判断系统架构，自动安装最新版 frps 或 frpc，升级无须选择。

### 🤠 服务器状态推送脚本
```shell
curl -L -o server_status_report.sh https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/server_status_report.sh
```
- 别忘记下载下来之后给予脚本权限并将文中的key改为自己的key哦 再通过crontab -e 来填写需要推送的周期 例：0 */3 * * * /bin/bash /root/server_status_report.sh

### 全面型 DoH 服务器测试脚本
- 这个增强版脚本提供了一个全面的方式来测试各种 DNS-over-HTTPS (DoH) 服务器，包括广泛的全球服务提供商，并能检测现代 DNS 特性。

> 功能特性
- 1. 丰富的 DoH 服务器列表
> 脚本包含了广泛的 DoH 服务器选择，便于识别：

> 国际主流： Cloudflare、Google、Quad9、OpenDNS、AdGuard、NextDNS

> 国内服务商： 阿里、腾讯、360、百度、DNSPod、RubyFish、233py

> 专业服务： Mullvad、LibreDNS、BlahDNS、CleanBrowsers、ControlD

> 特殊功能： 隐私保护、广告拦截、恶意软件防护、家庭过滤

- 2. 特性检测功能
> 它自动检测并验证关键的 DNS 特性：

> HTTP/3 支持： 检测并自动使用 HTTP/3。

> EDNS 支持： 检测扩展 DNS (EDNS) 功能。

> DNSSEC 支持： 检测 DNS 安全扩展 (DNSSEC)。

> IPv6 支持： 执行 IPv6 地址测试。

> 功能标签： 识别具有广告拦截、隐私保护、无日志、恶意软件防护等功能的服务器。

- 3. 增强的输出格式
> 选择最适合您需求的输出格式：

> 表格格式： 清晰易读的表格显示（默认）。

> JSON 格式： 便于程序处理。

> CSV 格式： 适用于数据分析。

> 颜色显示： 更好的视觉效果。

- 4. 统计和推荐
> 脚本提供有价值的洞察：

> 测试成功率统计： 分析查询的成功率。

> 最佳服务器推荐： 根据地区和用途推荐最佳服务器。

> 特性分类推荐： 根据特定需求（例如隐私、广告拦截、安全）推荐服务器。

- 5. 健壮的错误处理和依赖检查
> 通过内置检查确保平稳运行：

> 自动依赖检查： 验证必要工具（例如 q、curl）是否存在。

> 超时处理和错误恢复： 管理超时并尝试从错误中恢复。

> 详细状态显示： 提供清晰的测试过程反馈。

#### 命令行参数
##### 基本用法
```shell
./enhanced-doh-test.sh
```
##### 测试指定域名
``` shell
./enhanced-doh-test.sh -d example.com
```
##### 详细输出
``` shell
./enhanced-doh-test.sh -v
```
##### JSON 格式输出
```shell
./enhanced-doh-test.sh -f json
```
##### 显示特性测试
```shell
./enhanced-doh-test.sh -F
```
##### 设置超时时间（秒）
```shell
./enhanced-doh-test.sh -t 5
```
#### 使用示例
前提条件
请确保已安装 q 用于解析结果。如果尚未安装，可以使用 Go 进行安装：
```shell
go install github.com/natesales/q@latest
```
运行脚本
首先，使脚本可执行：
```shell
chmod +x enhanced-doh-test.sh
```
然后，运行它：
```shell
./enhanced-doh-test.sh
```
特定测试场景
使用详细输出和特性检测测试 www.baidu.com：
``` shell

./enhanced-doh-test.sh -d www.baidu.com -v -F
```
将结果以 JSON 格式保存到文件：
``` shell
./enhanced-doh-test.sh -f json > results.json 
```
