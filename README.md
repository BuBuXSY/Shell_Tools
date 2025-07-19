# 🚀 Linux 运维工具集
> 把复杂的东西简单化 - 一键脚本工具集合

## 📋 工具列表

### 🛠️ 系统优化

#### Linux内核参数优化工具
智能化的内核参数优化，支持多种工作负载场景
```bash
# 快速下载运行
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/kernel_optimization.sh)
```
# 常用参数
--quick     # 快速优化（推荐新手）
--preview   # 预览模式，查看效果不实际应用
--rollback  # 回滚到最近备份
--test      # 运行性能测试
```

**特色功能：**
- 🧙‍♂️ 智能配置向导，自动推荐最优参数
- 🎯 支持 Web服务器/数据库/缓存/容器 等场景
- 🛡️ 安全增强，完整备份回滚
- 🧪 内置性能测试和健康检查

---

### 🌐 Web服务

#### Nginx 自动更新（支持现代特性）
支持 QUIC、Brotli、OCSP、GEOIP2、KTLS
```bash
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/Auto_Upgrade_Nginx.sh)
```

#### GeoIP2 数据库更新
更新 Country.mmdb 供 Nginx GEOIP2 使用
```bash
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/update_Country.sh)
```
💡 默认路径：`/usr/share/GeoIP`，支持企业微信推送

#### SSL证书自动申请
支持多CA，默认ECC证书
```bash
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/install_cert.sh)
```

---

### 🔍 监控分析

#### IP访问分析（防刷DNS）
查询访问服务器IP并显示地理位置
```bash
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/search_ip.sh)
```
📋 需要：安装 nali + 开启 Nginx access.log

#### 服务器状态推送
定时推送服务器运行状态
```bash
curl -L -o server_status_report.sh https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/server_status_report.sh
chmod +x server_status_report.sh
# 记得修改脚本中的webhook key
```

#### MOSDNS 重复域名收集
优化DNS查询压力，生成TTL规则
```bash
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/collect_repeat_dns.sh)
```

**配置要点：**
- 📝 开启 mosdns info级别日志
- ⚙️ 自动生成配置文件 `dns_monitor.conf`
- 📱 支持企业微信通知
- 🕐 建议配置定时任务：`0 * * * * /path/to/collect_repeat_dns.sh`

---

### 🚀 网络工具

#### Frp 自动安装更新
支持 amd64 和 arm64 架构
```bash
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Shell_Tools/main/update_frp.sh)
```

#### DoH 服务器测试工具
全面测试 DNS-over-HTTPS 服务器性能
```bash
curl -L -o enhanced-doh-test.sh https://raw.githubusercontent.com/BuBuXSY/Shell_Tools/refs/heads/main/enhanced-doh-test.sh
chmod +x enhanced-doh-test.sh
```

**功能亮点：**
- 🌍 覆盖国内外主流DoH服务商
- ✅ 自动检测 HTTP/3、EDNS、DNSSEC、IPv6
- 📊 多种输出格式：表格/JSON/CSV
- 🎯 智能推荐最佳服务器

**使用示例：**
```bash
./enhanced-doh-test.sh -d example.com     # 测试指定域名
./enhanced-doh-test.sh -f json            # JSON格式输出
./enhanced-doh-test.sh --diagnosis        # 网络诊断
```

---

## ⚠️ 使用须知

### 系统要求
- **操作系统**：主流 Linux 发行版
- **权限**：Root 或 sudo
- **网络**：稳定的互联网连接

### 安全提醒
- ✅ **测试优先**：生产环境前请先测试
- 📦 **自动备份**：脚本会自动备份原配置
- 📊 **监控系统**：优化后请观察系统表现
- 🔄 **快速回滚**：遇到问题可立即回滚

### 故障排除
```bash
# 查看系统日志
journalctl -xe

# 检查脚本日志
tail -f /var/log/kernel_optimization.log

# 立即回滚配置
sudo ./kernel_optimization.sh --rollback
```

---

## 🤝 贡献与支持

- 📋 遇到问题请提交 Issue
- 🔧 欢迎提交 Pull Request
- ⭐ 觉得有用请点个 Star

---
*让Linux运维更简单！* 🎉
