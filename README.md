# 🚀 各类一键脚本 — 把复杂的东西简单化  

## ⚙️ 智能化的Linux内核参数优化工具 - 安全、高效、易用

### ✨ 主要特性

- 🧙‍♂️ **智能配置向导** - 根据系统自动推荐最优参数
- 🎯 **多工作负载支持** - Web、数据库、缓存、容器、通用服务器
- 🛡️ **安全增强** - 修复代码注入风险，严格输入验证
- 💾 **完整备份回滚** - 自动备份，一键回滚
- 👁️ **预览模式** - 先预览后应用，安全可控
- 🧪 **性能测试** - 内置基准测试和健康检查

####  下载和运行

```bash
# 下载脚本
chmod +x kernel_optimization.sh

# 交互式运行（推荐）
sudo ./kernel_optimization.sh

# 快速优化（使用默认设置）
sudo ./kernel_optimization.sh --quick

# 预览模式（查看效果不实际应用）
sudo ./kernel_optimization.sh --preview
```

##### 系统要求

- **操作系统**: Ubuntu, Debian, CentOS, RHEL, Fedora, Arch 等主流发行版
- **内核版本**: 3.10+ (推荐 4.4+)
- **内存**: 512MB+ (推荐 1GB+)
- **权限**: Root 或 sudo

#### 📖 基本使用

##### 主要功能

| 功能 | 说明 |
|------|------|
| 🧙‍♂️ **智能配置向导** | 引导式配置，适合所有用户 |
| ⚡ **快速优化** | 一键应用推荐设置 |
| 👁️ **预览效果** | 查看优化参数对比 |
| 🔄 **配置回滚** | 恢复到之前状态 |
| 🧪 **性能测试** | 基准测试和健康检查 |
| 💾 **配置管理** | 备份、导出、导入 |

##### 工作负载类型

- **🌐 Web服务器** - Nginx, Apache 高并发优化
- **🗄️ 数据库服务器** - MySQL, PostgreSQL 内存优化
- **🚀 缓存服务器** - Redis, Memcached 网络优化
- **🐳 容器主机** - Docker, K8s 资源管理优化
- **🏢 通用服务器** - 平衡性能优化

##### 优化级别

- **🛡️ 保守模式** - 最小风险，适合生产环境
- **⚖️ 平衡模式** - 性能与稳定性兼顾（推荐）
- **🚀 激进模式** - 最大性能，适合高性能计算

##### 命令行选项

```bash
sudo ./kernel_optimization.sh [选项]

选项:
  --help, -h     显示帮助信息
  --version      显示版本信息
  --quick        快速优化（平衡+通用）
  --preview      预览模式
  --check        系统健康检查
  --rollback     回滚到最近备份
  --test         运行性能测试
```

## ⚠️ 重要提醒

#### 使用前必读

- ✅ **测试环境验证** - 建议先在测试环境中验证效果
- ✅ **自动备份** - 脚本会自动备份原始配置
- ✅ **监控系统** - 优化后请监控系统性能和稳定性
- ✅ **容器限制** - 容器环境中某些参数可能无法修改

##### 文件位置

```
/var/log/kernel_optimization.log              # 操作日志
/var/backups/kernel_optimization/             # 配置备份
/etc/kernel_optimization/versions/            # 版本控制
/var/log/kernel_optimization/benchmarks/      # 测试结果
```

##### 🔧 故障排除

**Q: 参数应用失败**
```bash
# 检查内核版本和系统兼容性
uname -r
sudo ./kernel_optimization.sh --check
```

**Q: 优化后性能下降**
```bash
# 立即回滚配置
sudo ./kernel_optimization.sh --rollback
```

**Q: 容器环境限制**
```bash
# 在容器主机上运行，而非容器内部
```

##### 日志检查

```bash
# 查看操作日志
tail -f /var/log/kernel_optimization.log

# 查看系统日志
journalctl -xe
```

### 📝 示例

#### 基本优化流程

```bash
# 1. 系统检查
sudo ./kernel_optimization.sh --check

# 2. 预览效果
sudo ./kernel_optimization.sh --preview

# 3. 应用优化
sudo ./kernel_optimization.sh

# 4. 性能测试
sudo ./kernel_optimization.sh --test
```

#### Web服务器优化

```bash
# 使用预设参数优化Web服务器
sudo ./kernel_optimization.sh --web --balanced
```
**⚡ 让您的Linux系统性能飞起来！** 🚀
***

## 🦄 Debian 系自动更新 Nginx（支持 QUIC、Brotli、OCSP、GEOIP2、KTLS）
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/Auto_Upgrade_Nginx.sh)
```

***

## 🌍 更新 Country.mmdb 供 Nginx GEOIP2 使用
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/update_Country.sh)
```
- 提示：
- 默认路径：/usr/share/GeoIP（请提前 mkdir -p /usr/share/GeoIP）
- 支持企业微信推送（需替换脚本内 webhook Key）
- 可通过 crontab -e 添加定时任务，如：
- 0 4 * * * /root/update_Country.sh（每日凌晨4点执行）

***

## 🔍 查询访问服务器 IP 并显示地理位置（防刷 DNS）
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/search_ip.sh
)
```
#### 依赖：

- 需要安装 nali

- 确保 Nginx 开启了 access.log 功能

- 支持企业微信推送（替换 webhook Key）

***

## 🔐 服务器证书申请与安装（默认 ECC，支持多 CA，限 Nginx）
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/install_cert.sh
)
```
- 自动化证书申请，简化流程，一键搞定！

***

## ⏰ 定时收集 MOSDNS 重复查询域名，优化查询压力
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/collect_repeat_dns.sh
)
```
### ✨ 功能特性
- 搭配 MOSDNS 使用，开启 mosdns.log info 级别，默认路径 /etc/mosdns/mosdns.log。
- 🔍 自动分析 mosdns 日志文件
- 📊 统计域名查询频率
- 🚫 生成重复域名TTL规则（mosdns可用）
- 📱 企业微信/邮件通知
- 📈 历史数据记录
- ⚙️ 灵活的配置管理

#### 🚀 快速开始

##### 1. 下载脚本

```bash
# 下载脚本文件
wget https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/collect_repeat_dns.sh
chmod +x collect_repeat_dns.sh
```

##### 2. 首次运行

```bash
# 直接运行，会自动生成配置文件
./collect_repeat_dns.sh
```

脚本会自动创建配置文件 `dns_monitor.conf`，请根据需要修改。

##### 3. 配置企业微信通知

编辑配置文件：

```bash
vim dns_monitor.conf
```

修改以下配置：

```bash
# 替换为你的企业微信机器人 Webhook URL
WECHAT_WEBHOOK_URL="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=你的KEY"

# 调整阈值（默认500次）
THRESHOLD=500
```

##### ⚙️ 主要配置选项

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `DOMAIN_FILE` | mosdns 日志文件路径 | `/etc/mosdns/mosdns.log` |
| `OUTPUT_FILE` | 输出规则文件路径 | `/etc/mosdns/rules/repeat_domain.txt` |
| `THRESHOLD` | 重复查询阈值 | `500` |
| `WECHAT_WEBHOOK_URL` | 企业微信通知地址 | 需要配置 |
| `BLACKLIST_DOMAINS` | 域名黑名单 | `("localhost" "*.local" "*.test")` |

##### 🕐 设置定时任务

###### 方法一：使用 crontab

```bash
# 编辑定时任务
crontab -e

# 添加以下行（每小时执行一次）
0 * * * * /path/to/collect_repeat_dns.sh >/dev/null 2>&1

# 或者每天凌晨 2 点执行
0 2 * * * /path/to/collect_repeat_dns.sh >/dev/null 2>&1
```

###### 方法二：使用 systemd timer

创建服务文件：

```bash
# /etc/systemd/system/collect_repeat_dns.service
[Unit]
Description=Collect repeat DNS
After=network.target

[Service]
Type=oneshot
ExecStart=/path/to/collect_repeat_dns.sh
User=root

# /etc/systemd/system/collect_repeat_dns.timer
[Unit]
Description=Run Collect repeat DNS hourly
Requires=collect_repeat_dns.service

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
```

启用定时器：

```bash
systemctl daemon-reload
systemctl enable collect_repeat_dns.timer
systemctl start collect_repeat_dns.timer
```
###### 🔍 查看运行状态

```bash
# 查看最近的运行日志
tail -f /var/log/dns_monitor.log

# 查看生成的规则文件
cat /etc/mosdns/rules/repeat_domain.txt

# 查看历史统计
cat /var/log/dns_monitor_history.json | jq '.'
```

***

## 🚀 Frp 最新版自动安装与更新（支持 amd64 和 arm64）
```shell
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/update_frp.sh
)
```
- 脚本自动判断系统架构，自动安装最新版 frps 或 frpc，升级无须选择。

***

## 🤠 服务器状态推送脚本
```shell
curl -L -o server_status_report.sh https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/server_status_report.sh
```
- 别忘记下载下来之后给予脚本权限并将文中的key改为自己的key哦 再通过crontab -e 来填写需要推送的周期 例：0 */3 * * * /bin/bash /root/server_status_report.sh

***

## 🌟 全面型 DoH 服务器测试脚本
- 这个增强版脚本提供了一个全面的方式来测试各种 DNS-over-HTTPS (DoH) 服务器，包括广泛的全球服务提供商，并能检测现代 DNS 特性。
```shell
curl -L -o enhanced-doh-test.sh https://raw.githubusercontent.com/BuBuXSY/Shell_Tools/refs/heads/main/enhanced-doh-test.sh
```
> 功能特性
- 🔧 1. 丰富的 DoH 服务器列表
> 脚本包含了广泛的 DoH 服务器选择，便于识别：

> 国际主流： Cloudflare、Google、Quad9、OpenDNS、AdGuard、NextDNS

> 国内服务商： 阿里、腾讯、360、百度、DNSPod、RubyFish、233py

> 专业服务： Mullvad、LibreDNS、BlahDNS、CleanBrowsers、ControlD

> 特殊功能： 隐私保护、广告拦截、恶意软件防护、家庭过滤

- ✅  2. 特性检测功能
> 它自动检测并验证关键的 DNS 特性：

> HTTP/3 支持： 检测并自动使用 HTTP/3。

> EDNS 支持： 检测扩展 DNS (EDNS) 功能。

> DNSSEC 支持： 检测 DNS 安全扩展 (DNSSEC)。

> IPv6 支持： 执行 IPv6 地址测试。

> 功能标签： 识别具有广告拦截、隐私保护、无日志、恶意软件防护等功能的服务器。

- ✅  3. 增强的输出格式
> 选择最适合您需求的输出格式：

> 表格格式： 清晰易读的表格显示（默认）。

> JSON 格式： 便于程序处理。

> CSV 格式： 适用于数据分析。

> 颜色显示： 更好的视觉效果。

- ✅  4. 统计和推荐
> 脚本提供有价值的洞察：

> 测试成功率统计： 分析查询的成功率。

> 最佳服务器推荐： 根据地区和用途推荐最佳服务器。

> 特性分类推荐： 根据特定需求（例如隐私、广告拦截、安全）推荐服务器。

- ✅  5. 健壮的错误处理和依赖检查
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
##### JSON 格式输出
```shell
./enhanced-doh-test.sh -f json > results.json 
```
##### 网络诊断
```shell
./enhanced-doh-test.sh --diagnosis
```
##### 调试模式
```shell
./enhanced-doh-test.sh --debug
```
##### 设置超时时间（秒）
```shell
./enhanced-doh-test.sh -t 5
```
#### 使用示例
前提条件
- 📥 请确保已安装 q 用于解析结果。如果尚未安装，可以使用 Go 进行安装：
```shell
go install github.com/natesales/q@latest
```
- ▶️ 运行脚本
首先，使脚本可执行：
```shell
chmod +x enhanced-doh-test.sh
```
然后，运行它：
```shell
./enhanced-doh-test.sh
```
