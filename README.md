# 🚀 Shell_Tools 脚本工具箱

> 🎯 集中管理 Linux 运维、网络诊断、Nginx、SSL、FRP、GeoIP 与浏览器字体优化工具。

[![Shell Tools Lint](https://github.com/BuBuXSY/Shell_Tools/actions/workflows/shell-tools-lint.yml/badge.svg)](https://github.com/BuBuXSY/Shell_Tools/actions/workflows/shell-tools-lint.yml)
[![Tools](https://img.shields.io/badge/工具数量-18-blue.svg)](README.md)
[![Platform](https://img.shields.io/badge/平台-Linux%20%7C%20OpenWrt%20%7C%20Edge-green.svg)](README.md)
[![License](https://img.shields.io/badge/许可证-MIT-orange.svg)](LICENSE)

## 🎪 工具总览

| 🔧 文件 | 🎯 用途 | ⚠️ 运行特性 |
| --- | --- | --- |
| `Auto_Upgrade_Nginx.sh` | 🌐 源码编译安装 / 升级 Nginx | root；官方验签；失败事务回滚 |
| `collect_repeat_dns.sh` | 🧠 分析 mosdns 重复查询域名 | 原子更新规则；不清空源日志 |
| `disk_usage_analyzer.sh` | 💽 磁盘空间占用分析 | 只读；支持多目录 |
| `enhanced-doh-test.sh` | 🧪 测试 DoH 节点延迟和能力 | 表格 / JSON / CSV |
| `install_cert.sh` | 🔐 申请、续期、部署 SSL 证书 | root；固定校验 acme.sh 来源 |
| `kernel_optimization.sh` | ⚙️ Linux 内核与网络参数优化 | root；多种服务器场景 |
| `nginx_access_analyzer.sh` | 📊 Nginx 访问日志分析 | 只读；可推送企业微信 |
| `search_ip.sh` | 🔍 分析 Nginx 高频 DNS 访问 IP | IP 缓存；可推送企业微信 |
| `server_security_audit.sh` | 🛡️ 服务器安全巡检 | 只读；支持严格退出码 |
| `server_status_report.sh` | 📊 服务器状态报告 | 支持 `--dry-run` |
| `shell_tools_lint.sh` | 🧪 仓库脚本自检 | ShellCheck + userscript 冒烟测试 |
| `ssl_cert_monitor.sh` | 🔐 SSL 证书有效期巡检 | GNU / BSD 日期兼容 |
| `system_config_backup.sh` | 💾 系统关键配置备份 | 权限 `600`；SHA-256 校验 |
| `update_Country.sh` | 🌏 更新 GeoIP Country.mmdb | 条件下载；原子替换 |
| `update_frp.sh` | 🚇 安装、更新、卸载 FRP | OpenWrt / Linux；首装不启动 |
| `Mactype助手增强版 (Edge优化)-1.0.0.user.js` | ✨ Edge 字体渲染增强 | Tampermonkey / Violentmonkey |
| `junyaoairwebsite-intranet-optimization1.0.user.js` | 🛫 吉祥航空内网页面字体优化 | `document-start` 安全注入 |
| `VPS_nginx_CDN_伪装网址.conf` | 🧱 HTTPS 伪装与反向代理模板 | 使用前替换域名、证书和端口 |

## ⚡ 快速开始

```bash
git clone https://github.com/BuBuXSY/Shell_Tools.git
cd Shell_Tools
chmod +x ./*.sh
./shell_tools_lint.sh
```

查看任一脚本的参数：

```bash
./script_name.sh --help
```

## 🛠️ 常用命令

### 系统变更类

这些脚本会修改系统配置或服务，建议先在测试机执行。

```bash
# 安装 / 升级 Nginx
sudo ./Auto_Upgrade_Nginx.sh --channel stable

# 按服务器场景优化内核
sudo ./kernel_optimization.sh --scene vps

# 交互式申请或续期证书
sudo ./install_cert.sh

# 安装 FRP 客户端
sudo ./update_frp.sh --action install --role frpc

# 更新 GeoIP Country.mmdb
sudo ./update_Country.sh

# 备份系统关键配置
sudo ./system_config_backup.sh
```

### 只读巡检类

```bash
# 磁盘 Top 占用
TARGETS="/ /var/www /opt" TOP_N=20 ./disk_usage_analyzer.sh

# 安全巡检；发现风险时返回 1
EXIT_ON_WARNING=1 ./server_security_audit.sh

# 证书巡检；30 天内过期即告警
WARN_DAYS=30 EXIT_ON_WARNING=1 ./ssl_cert_monitor.sh

# 服务器报告预览，不推送
./server_status_report.sh --dry-run

# Nginx 访问日志分析
LOG_FILE=/var/log/nginx/access.log TOP_N=20 ./nginx_access_analyzer.sh
```

### 网络与 DNS 类

```bash
# 测试 DoH 节点并输出机器可读 JSON
./enhanced-doh-test.sh -d example.com -t 5 -f json

# 分析高频 DNS 访问 IP，不执行推送
./search_ip.sh --log-file /var/log/nginx/access.log --no-push

# 使用指定 mosdns 监控配置
./collect_repeat_dns.sh --config ./dns_monitor.conf
```

## ⚙️ 配置方式

脚本优先使用命令行参数；批量部署或定时任务可使用环境变量。

| 脚本 | 常用环境变量 |
| --- | --- |
| `collect_repeat_dns.sh` | `DNS_MONITOR_CONFIG` |
| `disk_usage_analyzer.sh` | `TARGETS`、`TOP_N`、`MAX_DEPTH` |
| `nginx_access_analyzer.sh` | `LOG_FILE`、`TOP_N`、`MAX_LINES` |
| `search_ip.sh` | `NGINX_LOG_FILE`、`NALI_CACHE_FILE`、`WEBHOOK_URL` |
| `server_security_audit.sh` | `EXIT_ON_WARNING` |
| `server_status_report.sh` | `WEBHOOK_URL`、`SERVER_STATUS_CACHE_FILE`、`SERVER_STATUS_LOG_FILE` |
| `ssl_cert_monitor.sh` | `WARN_DAYS`、`CERT_DIRS`、`EXIT_ON_WARNING` |
| `system_config_backup.sh` | `BACKUP_DIR`、`EXTRA_PATHS`、`KEEP_DAYS` |
| 推送类脚本 | `WEBHOOK_URL` 或 `WECHAT_WEBHOOK_URL` |

企业微信 webhook 建议只通过环境变量传入，避免把密钥提交到 Git：

```bash
export WEBHOOK_URL="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx"
```

`TARGETS`、`CERT_DIRS` 和 `EXTRA_PATHS` 当前使用空格分隔，因此路径本身不能包含空格。

## 🧷 关键运行语义

- `install_cert.sh` 默认从官方 tag 下载 `acme.sh 3.1.3`，并校验 SHA-256 `efd12b265252f8875269960b6b31830731ccce2b3e6ff8e7ecfbee21fde35ab4`。覆盖 `ACME_SH_VERSION` 时必须同时提供对应的 `ACME_SH_SHA256`，否则拒绝安装。
- `Auto_Upgrade_Nginx.sh` 会校验 Nginx 官方源码签名及签名者固定指纹；ngx_brotli、GeoIP2 模块和 OpenSSL 使用固定完整 commit，PCRE2 与 zlib 使用固定发布包 SHA-256。更新这些依赖时必须同步复核版本、commit 或摘要。
- `update_frp.sh` 首次安装会生成权限为 `0600` 的本地回环占位配置并注册服务，但不会 enable/start。请先更换 token 或 OIDC、核对地址和端口、执行 `frpc verify -c /etc/frp/frpc.toml` 或 `frps verify -c /etc/frp/frps.toml`，再手动启动；升级已有安装时保留原服务启用/运行状态，失败则回滚事务。
- `update_Country.sh` 只有在本地 MMDB 的结构检查与上次保存的 SHA-256 同时匹配时才发送 ETag / Last-Modified 条件请求；替换和失败回滚都在目标目录内暂存后原子切换。
- `collect_repeat_dns.sh` 只轮转自身的监控日志，不会截断、覆盖或删除 MosDNS 正在写入的源查询日志。旧配置中的 `TRUNCATE_SOURCE_LOG=true` 已停用，仅产生告警；源日志请交给 MosDNS 或 `logrotate` 管理。
- `server_security_audit.sh` 的 `EXIT_ON_WARNING=1` 会在发现安全风险或检查不完整时返回 `1`；默认模式仍输出告警，但返回 `0`。
- `ssl_cert_monitor.sh` 的 `EXIT_ON_WARNING=1` 会在证书即将过期、已过期、无法解析、目录扫描不完整或未找到证书时返回 `1`；证书按 SHA-256 指纹去重后统计。
- `server_status_report.sh` 和 `search_ip.sh` 在正常推送模式下缺少 webhook 或推送失败都会返回 `1`。只有显式使用 `--dry-run` 或 `--no-push` 才按本地预览模式成功退出。

## 🚦 退出码

多数脚本遵循以下约定：

| 状态码 | 含义 |
| --- | --- |
| `0` | 执行成功，或只读检查未启用严格告警退出 |
| `1` | 运行失败、网络 / 服务失败，或严格模式发现告警 |
| `2` | 参数错误；`system_config_backup.sh` 也用它表示部分备份成功 |

自动化任务应同时检查进程退出码和企业微信接口返回的 `errcode`。

## 🔐 安全设计

- 下载内容先进入独立临时目录，并按来源校验固定 SHA-256、官方签名、固定 commit、文件类型和归档路径后再安装。
- Nginx、FRP、GeoIP 和备份更新使用暂存文件与原子替换，降低中断后留下半成品的风险。
- Nginx / FRP 服务启动失败时保留或恢复升级前二进制。
- `install_cert.sh` 不再使用 `curl | sh`，远程安装器会先保存到临时文件再执行。
- 日志分析与 webhook 推送会清理控制字符、转义 JSON，并检查企业微信应用层状态。
- 备份脚本拒绝根目录和路径穿越输入，归档默认权限为 `600`。

## 🌐 Nginx 模板

`VPS_nginx_CDN_伪装网址.conf` 是一份完整配置模板。使用前至少修改：

1. `user nginx`；Debian / Ubuntu 软件包安装通常改为 `user www-data`。
2. `example.com` 与 `/etc/nginx/ssl` 下的证书路径。
3. `camouflage_host` 伪装站域名。
4. `xray_backend`、`xui_backend` 的端口和分流路径。
5. `resolver`，按服务器实际 DNS 环境调整。

部署前必须验证：

```bash
sudo nginx -t -c /path/to/VPS_nginx_CDN_伪装网址.conf
```

## 🧩 Userscript

两个 `.user.js` 文件可通过 Tampermonkey 或 Violentmonkey 安装。当前实现处理了：

- `document-start` 阶段 `<head>` 尚未创建的情况。
- Edge 首次运行和快捷预设未打开设置面板时的空节点访问。
- DPI 变化检测、字间距关闭后的无效 CSS，以及关闭设置时恢复未保存预览。
- 吉祥航空页面内联字体权重检查由全 DOM 扫描收窄为仅扫描含 `style` 的元素。

## 🧪 开发与验证

完整本地检查：

```bash
sudo apt-get install shellcheck
./shell_tools_lint.sh
node ./tests/userscript_smoke_test.js
git diff --check
```

`shell_tools_lint.sh` 会检查：

- Shell 语法与 shebang 对应的解释器。
- ShellCheck warning 级问题（本机已安装时）。
- 统一脚本头部、emoji / 彩色输出和可执行权限。
- Userscript metadata、JavaScript 语法与 `document-start` 冒烟测试。

GitHub Actions 会安装 ShellCheck 后执行同一套检查。

## 🧭 兼容性

- Shell 工具主要面向 Linux；`update_frp.sh` 额外兼容 OpenWrt BusyBox `ash`。
- `kernel_optimization.sh` 支持 VPS、低配 VPS、旁路由、主路由、单板机和裸机场景。
- `ssl_cert_monitor.sh` 兼容 GNU 与 BSD 风格 `date`。
- `search_ip.sh` 如需显示 IP 归属地，建议安装 `nali`。

## 📜 License

本项目使用 [MIT License](LICENSE)。
