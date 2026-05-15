# 🚀 Shell_Tools 脚本工具箱

> 🎯 把常用 Linux 运维、网络诊断、Nginx、SSL、FRP、GeoIP 和浏览器字体优化脚本集中管理。

[![Tools](https://img.shields.io/badge/工具数量-18+-blue.svg)](README.md)
[![Platform](https://img.shields.io/badge/平台-Linux%20%7C%20OpenWrt-green.svg)](README.md)
[![License](https://img.shields.io/badge/许可证-MIT-orange.svg)](LICENSE)

## 🎪 工具总览

| 🔧 文件 | 🎯 用途 | ⚠️ 备注 |
| --- | --- | --- |
| `Auto_Upgrade_Nginx.sh` | 🌐 源码编译安装 / 升级 Nginx | 🔐 需要 root |
| `collect_repeat_dns.sh` | 🧠 分析 mosdns 重复查询域名 | 📄 支持 `dns_monitor.conf` |
| `disk_usage_analyzer.sh` | 💽 磁盘空间占用分析 | 👀 只读检查，不删文件 |
| `enhanced-doh-test.sh` | 🧪 测试 DoH 节点延迟和能力 | 📦 需要 `curl` |
| `install_cert.sh` | 🔐 申请、续期、部署 SSL 证书 | 🌍 支持 DNS API |
| `kernel_optimization.sh` | ⚙️ Linux 内核 / 网络参数优化 | 🔐 需要 root |
| `nginx_access_analyzer.sh` | 📊 Nginx 访问日志分析 | 📣 可推送企业微信 |
| `search_ip.sh` | 🔍 分析 Nginx 高频 DNS 访问 IP | 📣 可推送企业微信 |
| `server_status_report.sh` | 📊 推送服务器状态报告 | 📣 可推送企业微信 |
| `server_security_audit.sh` | 🛡️ 服务器安全巡检 | 👀 只读检查，不改配置 |
| `shell_tools_lint.sh` | 🧪 仓库脚本自检 | ✅ 检查语法、头部、权限 |
| `ssl_cert_monitor.sh` | 🔐 SSL 证书有效期巡检 | 📣 可推送企业微信 |
| `system_config_backup.sh` | 💾 系统关键配置备份 | 🧰 适合升级前快照 |
| `update_Country.sh` | 🌏 更新 GeoIP Country.mmdb | 💾 支持缓存和备份 |
| `update_frp.sh` | 🚇 安装、更新、卸载 FRP | 🐧 支持 OpenWrt / Linux |
| `Mactype助手增强版 (Edge优化)-1.0.0.user.js` | ✨ Edge 字体渲染增强 | 🧩 Userscript |
| `junyaoairwebsite-intranet-optimization1.0.user.js` | 🛫 吉祥航空内网页面字体优化 | 🧩 Userscript |
| `VPS_nginx_CDN_伪装网址.conf` | 🧱 Nginx 反代配置模板 | 📝 使用前改域名和端口 |

---

## ⚡ 快速开始

```bash
git clone https://github.com/BuBuXSY/Shell_Tools.git
cd Shell_Tools
chmod +x *.sh
```

### 🛠️ 常用命令

```bash
# ⚙️ VPS / 代理服务器内核优化
sudo ./kernel_optimization.sh --proxy

# 🌐 编译安装或升级 Nginx
sudo ./Auto_Upgrade_Nginx.sh

# 🚇 安装 / 更新 FRP
sudo ./update_frp.sh

# 🧪 测试 DoH 节点
./enhanced-doh-test.sh

# 🛡️ 只读安全巡检
./server_security_audit.sh

# 🔐 SSL 证书有效期巡检
./ssl_cert_monitor.sh

# 📊 Nginx 访问日志分析
./nginx_access_analyzer.sh

# 💾 系统关键配置备份
sudo ./system_config_backup.sh

# 💽 磁盘空间占用分析
./disk_usage_analyzer.sh

# 🧪 仓库脚本自检
./shell_tools_lint.sh
```

---

## 📣 企业微信推送配置

推送类脚本建议用环境变量传入 webhook，避免把密钥写死在脚本里。

```bash
export WEBHOOK_URL="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx"
export WECHAT_WEBHOOK_URL="$WEBHOOK_URL"
```

适用脚本：

- 📊 `server_status_report.sh`
- 📊 `nginx_access_analyzer.sh`
- 🔍 `search_ip.sh`
- 🔐 `ssl_cert_monitor.sh`
- 🌏 `update_Country.sh`
- 🧠 `collect_repeat_dns.sh`

---

## 📥 单文件下载示例

```bash
# 🚇 FRP 管理脚本
curl -fsSL https://raw.githubusercontent.com/BuBuXSY/Shell_Tools/main/update_frp.sh -o update_frp.sh
chmod +x update_frp.sh

# 🌏 GeoIP 数据库更新脚本
curl -fsSL https://raw.githubusercontent.com/BuBuXSY/Shell_Tools/main/update_Country.sh -o update_Country.sh
chmod +x update_Country.sh
```

---

## 🧭 使用建议

- 🧪 会修改系统配置、证书、Nginx 或内核参数的脚本，建议先在测试机验证。
- 🔐 `install_cert.sh`、`Auto_Upgrade_Nginx.sh`、`kernel_optimization.sh` 通常需要 root 权限。
- 🔍 `search_ip.sh` 如需显示 IP 归属地，建议安装 `nali`。
- 🧩 `.user.js` 文件需要通过 Tampermonkey、Violentmonkey 等 userscript 管理器安装。
- 📜 本项目使用 MIT License，详见 `LICENSE`。

---

## 🧰 维护状态

- ✅ 已补齐 `LICENSE`
- ✅ 已统一 GitHub 地址大小写为 `BuBuXSY/Shell_Tools`
- ✅ 已将 webhook 配置改为优先读取环境变量
- ✅ 已保留脚本原本的中文 + emoji 输出风格
- ✅ 已新增只读安全巡检脚本 `server_security_audit.sh`
- ✅ 已优化 `collect_repeat_dns.sh` 临时文件生成，降低并发运行互相覆盖风险
- ✅ 已新增 `.gitignore`，避免误提交本地配置、日志、缓存和备份文件
- ✅ 已修复 `server_security_audit.sh` 在 nftables 不可读时提前退出的问题
- ✅ 已新增 SSL 证书有效期巡检脚本 `ssl_cert_monitor.sh`
- ✅ 已新增 Nginx 访问日志分析脚本 `nginx_access_analyzer.sh`
- ✅ 已新增系统关键配置备份脚本 `system_config_backup.sh`
- ✅ 已修复新增脚本 cleanup trap 可能影响退出码的问题
- ✅ 已新增只读磁盘空间分析脚本 `disk_usage_analyzer.sh`
- ✅ 已统一所有 `.sh` 脚本开头格式：emoji 脚本名、功能说明、`By: BuBuXSY`、`Version`
- ✅ 已补齐 `search_ip.sh`、`server_status_report.sh` 的彩色终端输出
- ✅ 已统一 `.user.js` 头部 metadata：emoji 名称、日期、署名和描述风格
- ✅ 已新增仓库自检脚本 `shell_tools_lint.sh`
- ✅ 已新增 GitHub Actions：推送和 PR 时自动运行仓库自检
