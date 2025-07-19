# 🚀 Linux 脚本工具集

> 🎯 **把复杂的东西简单化**

[![Tools](https://img.shields.io/badge/工具数量-9+-blue.svg)](README.md) [![Platform](https://img.shields.io/badge/平台-Linux-green.svg)](README.md) [![License](https://img.shields.io/badge/许可证-MIT-orange.svg)](LICENSE)

## 🎪 工具概览

| 🔧 工具类型 | 📊 工具数量 | 🎯 主要用途 |
|------------|-----------|-----------|
| 🛠️ 系统优化 | 1个 | 内核参数调优 |
| 🌐 Web服务 | 3个 | Nginx + SSL + GeoIP |
| 🔍 监控分析 | 3个 | IP分析 + 状态监控 + DNS优化 |
| 🚀 网络工具 | 2个 | 内网穿透 + DoH测试 |

---

## 🛠️ 系统优化类

### 🎯 Linux内核参数优化工具

**💡 作用：** 智能化调优系统内核参数，提升服务器性能

```bash
# 🚀 一键运行
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/kernel_optimization.sh)
```

#### 📋 使用方法

```bash
# 🔰 新手推荐：快速优化
./kernel_optimization.sh --quick

# 👀 预览模式：查看效果不实际应用  
./kernel_optimization.sh --preview

# 🔙 回滚配置：恢复到最近备份
./kernel_optimization.sh --rollback

# 🧪 性能测试：验证优化效果
./kernel_optimization.sh --test
```

#### ✨ 特色功能

| 功能 | 图标 | 说明 |
|------|------|------|
| 智能配置向导 | 🧙‍♂️ | 自动推荐最优参数 |
| 多场景支持 | 🎯 | Web服务器/数据库/缓存/容器 |
| 安全增强 | 🛡️ | 完整备份回滚机制 |
| 性能测试 | 🧪 | 内置测试和健康检查 |

---

## 🌐 Web服务类

### 🔧 Nginx 自动更新

**💡 作用：** 自动化安装和升级Nginx，支持源码编译优化

```bash
# 🚀 一键运行
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/Auto_Upgrade_Nginx.sh)
```

#### ⚡ 核心特性

- **🔥 版本选择**：主线版 or 稳定版
- **⚙️ 依赖管理**：自动安装编译依赖
- **🗂️ 备份恢复**：自动备份现有配置
- **⚡ 性能优化**：启用 Brotli + GeoIP2
- **🔧 systemd集成**：自动配置服务
- **🛠️ 错误处理**：详细日志和诊断

#### 📦 内置模块

| 模块 | 功能 | 用途 |
|------|------|------|
| QUIC | HTTP/3支持 | 🚀 下一代协议 |
| Brotli | 压缩算法 | 📦 更高压缩比 |
| OCSP | 证书验证 | 🔒 安全增强 |
| GEOIP2 | 地理位置 | 🌍 IP地理定位 |
| KTLS | 内核TLS | ⚡ 性能优化 |

---

### 🌍 GeoIP2 数据库更新

**💡 作用：** 更新Country.mmdb数据库供Nginx GEOIP2使用

```bash
# 🚀 一键运行
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/update_Country.sh)
```

#### 📍 详细信息

- **📂 默认路径**：`/usr/share/geoip`
- **📱 通知支持**：企业微信推送
- **🔄 更新频率**：建议每月更新
- **💾 自动备份**：保留旧版本数据库

---

### 🔐 SSL证书自动申请

**💡 作用：** 超简单的SSL证书申请工具，支持多CA和自动验证

```bash
# 🚀 一键运行
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/install_cert.sh)
```

#### 🎯 核心功能

| 功能 | 图标 | 说明 |
|------|------|------|
| 申请新证书 | 🆕 | 新域名SSL证书申请 |
| 续期证书 | 🔄 | 快过期证书续命 |
| 强制更新 | 💪 | 重新生成证书 |
| 查看状态 | 👀 | 检查证书健康度 |

#### 🤖 验证方式

**手动验证** 🙋‍♂️
```bash
# 添加DNS TXT记录
📝 记录名称：_acme-challenge.example.com
📋 记录类型：TXT
🔑 记录值：[系统生成]
```

**API自动验证** 🤖
| DNS服务商 | API名称 | 推荐度 |
|-----------|---------|--------|
| 阿里云 ☁️ | dns_ali | ⭐⭐⭐⭐⭐ |
| 腾讯云 🐧 | dns_tencent | ⭐⭐⭐⭐⭐ |
| Cloudflare 🌤️ | dns_cf | ⭐⭐⭐⭐⭐ |
| DNSPod 🌐 | dns_dp | ⭐⭐⭐⭐ |

#### 📂 证书文件位置

```
📁 /etc/nginx/cert_file/
├── 📄 domain.cert.pem      # 证书文件
├── 🔐 domain.key.pem       # 私钥文件
└── 📜 domain.fullchain.pem # 完整证书链
```

---

## 🔍 监控分析类

### 🌍 IP访问分析（防刷DNS）

**💡 作用：** 查询访问服务器的IP并显示地理位置

```bash
# 🚀 一键运行
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/search_ip.sh)
```

#### 📋 使用要求

- ✅ **安装nali**：IP地理位置查询工具
- ✅ **开启日志**：Nginx access.log 记录
- 📊 **分析功能**：识别异常访问模式

#### 🎯 适用场景

- 🛡️ **防刷检测**：识别恶意IP
- 📈 **访问统计**：地理分布分析
- 🚫 **黑名单**：生成IP封禁列表

---

### 📊 服务器状态推送

**💡 作用：** 定时推送服务器运行状态到企业微信

```bash
# 📥 下载脚本
curl -L -o server_status_report.sh \
  https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/server_status_report.sh

# ✅ 设置权限
chmod +x server_status_report.sh

# ⚙️ 配置webhook（记得修改脚本中的key）
```

#### 📱 监控内容

| 监控项 | 图标 | 说明 |
|--------|------|------|
| CPU使用率 | 🧠 | 实时CPU负载 |
| 内存占用 | 🧮 | RAM使用情况 |
| 磁盘空间 | 💾 | 存储空间状态 |
| 网络流量 | 🌐 | 带宽使用情况 |
| 系统负载 | ⚡ | Load Average |

#### ⏰ 定时设置

```bash
# 每小时推送一次状态
0 * * * * /path/to/server_status_report.sh

# 每天9点推送详细报告
0 9 * * * /path/to/server_status_report.sh --detailed
```

---

### 🎯 MOSDNS 重复域名收集

**💡 作用：** 优化DNS查询压力，生成TTL规则配置

```bash
# 🚀 一键运行
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/collect_repeat_dns.sh)
```

#### ⚙️ 配置要点

| 配置项 | 要求 | 说明 |
|--------|------|------|
| 日志级别 | 📝 info级别 | 开启mosdns详细日志 |
| 配置文件 | ⚙️ 自动生成 | `dns_monitor.conf` |
| 通知方式 | 📱 企业微信 | 支持状态推送 |
| 定时任务 | 🕐 每小时 | `0 * * * * /path/to/script` |

#### 🎯 优化效果

- 📉 **减少查询**：缓存热点域名
- ⚡ **提升性能**：优化响应时间
- 📊 **数据分析**：生成访问统计

---

## 🚀 网络工具类

### 🌉 Frp 自动安装更新

**💡 作用：** 自动安装和更新Frp内网穿透工具

```bash
# 🚀 一键运行
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/update_frp.sh)
```

#### 🏗️ 架构支持

| 架构 | 图标 | 支持状态 |
|------|------|----------|
| amd64 | 💻 | ✅ 完全支持 |
| arm64 | 📱 | ✅ 完全支持 |
| armv7 | 🔧 | ⚠️ 部分支持 |

#### 🔧 功能特性

- **📦 自动下载**：获取最新版本
- **🔄 平滑升级**：不中断现有连接
- **⚙️ 配置保留**：保持原有配置
- **🛡️ 安全检查**：验证文件完整性

---

### 🌐 DoH 服务器测试工具

**💡 作用：** 全面测试DNS-over-HTTPS服务器性能

```bash
# 📥 下载脚本
curl -L -o enhanced-doh-test.sh \
  https://raw.githubusercontent.com/BuBuXSY/Shell_Tools/refs/heads/main/enhanced-doh-test.sh

# ✅ 设置权限
chmod +x enhanced-doh-test.sh
```

#### 🎯 测试功能

| 功能 | 图标 | 说明 |
|------|------|------|
| 协议支持 | 🌍 | HTTP/3、EDNS、DNSSEC |
| IPv6测试 | 🔗 | 双栈网络支持 |
| 性能测试 | ⚡ | 延迟和可用性 |
| 智能推荐 | 🧠 | 最佳服务器推荐 |

#### 📊 输出格式

```bash
# 🎯 测试指定域名
./enhanced-doh-test.sh -d example.com

# 📋 JSON格式输出
./enhanced-doh-test.sh -f json

# 🔍 网络诊断模式
./enhanced-doh-test.sh --diagnosis

# 📈 CSV报告输出
./enhanced-doh-test.sh -f csv
```

#### 🌍 覆盖服务商

**国内服务商**
- 🔵 阿里云DNS
- 🐧 腾讯云DNS  
- 🟢 360DNS
- 🔶 百度DNS

**国外服务商**
- 🌤️ Cloudflare
- 🔍 Google DNS
- 🛡️ Quad9
- 🎯 OpenDNS

---

## ⚠️ 使用须知

### 🛡️ 安全提醒

| 建议 | 图标 | 重要性 |
|------|------|--------|
| 测试优先 | ✅ | ⭐⭐⭐⭐⭐ |
| 自动备份 | 📦 | ⭐⭐⭐⭐ |
| 监控系统 | 📊 | ⭐⭐⭐⭐ |
| 快速回滚 | 🔄 | ⭐⭐⭐⭐⭐ |


### 📞 获取帮助

```bash
# 💡 查看脚本帮助
./script_name.sh --help

# 📋 查看详细选项
./script_name.sh --usage

# 🔍 调试模式运行
./script_name.sh --debug
```

---

## 🎯 快速导航

### 🔰 新手推荐路径

1. **🛠️ 系统优化** → Linux内核参数优化（快速模式）
2. **🔐 SSL证书** → 证书申请（手动DNS验证）
3. **📊 状态监控** → 服务器状态推送
4. **🌐 性能测试** → DoH服务器测试

### 🚀 进阶使用路径

1. **🔧 Nginx升级** → 自动更新（包含所有模块）
2. **🤖 自动化SSL** → API自动验证
3. **🎯 DNS优化** → MOSDNS重复域名收集
4. **🌉 内网穿透** → Frp自动部署

### 📈 生产环境建议

1. **📦 备份策略**：所有配置自动备份
2. **📊 监控体系**：状态推送 + IP分析  
3. **🔄 自动化**：SSL自动续期 + 系统自动优化
4. **🛡️ 安全加固**：GeoIP2地理限制 + 防刷检测

---

## 🤝 贡献与支持

### 💖 参与贡献

- **🐛 Bug反馈**：[提交Issue](https://github.com/BuBuxsy/Shell_Tools/issues)
- **💡 功能建议**：[功能请求](https://github.com/BuBuxsy/Shell_Tools/issues/new)
- **🔧 代码贡献**：[Pull Request](https://github.com/BuBuxsy/Shell_Tools/pulls)


### ⭐ 支持项目

觉得有用？给个Star支持一下！⭐

---

**🎉 让Linux运维更简单，让自动化成为习惯！**
