#!/usr/bin/env bash
# 🩹 Shell_Tools 故障自愈助手脚本工具
# 功能：诊断常见资源故障并生成安全修复建议
# By: BuBuXSY
# Version: 2026-09-30
set -euo pipefail
usage(){ printf '🩹 故障自愈助手\n用法: %s [--plan] [--format text|json]\n' "$0"; }
# shellcheck disable=SC2034
GREEN=''; YELLOW=''; CYAN=''; : "${GREEN}${YELLOW}${CYAN}"
format=text
while [[ $# -gt 0 ]]; do case "$1" in --plan) shift;; --format) format="${2:-}"; shift 2;; -h|--help) usage; exit 0;; *) echo "未知参数: $1" >&2; exit 2;; esac; done
[[ "$format" == text || "$format" == json ]] || { echo '无效输出格式' >&2; exit 2; }
load=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo unknown)
disk=$(df -P / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}' || echo unknown)
mem=$(free -m 2>/dev/null | awk '/Mem:/{print $3 "/" $2 "MB"}' || echo unavailable)
load_int=$(awk -v value="$load" 'BEGIN{printf "%d", value+0}' 2>/dev/null || echo 0)
severity=ok; recommendation='系统资源暂未发现明显风险'; failed_services=0
if [[ "$disk" =~ ^[0-9]+$ && "$disk" -ge 90 ]]; then severity=critical; recommendation='根分区使用率达到 90% 以上，建议先预览清理缓存并检查大文件'; fi
if (( load_int >= 4 )); then severity=warning; recommendation='系统负载偏高，建议检查 CPU 占用进程和异常服务'; fi
if command -v systemctl >/dev/null 2>&1; then
  failed_services=$( { systemctl --failed --no-legend --plain 2>/dev/null || true; } | awk 'NF{count++} END{print count+0}' )
  if [[ "$failed_services" -gt 0 ]]; then severity=warning; recommendation="检测到 ${failed_services} 个失败服务，建议执行 systemctl --failed 查看"; fi
fi
if [[ "$format" == json ]]; then
  printf '{"severity":"%s","load":"%s","root_disk_percent":"%s","memory":"%s","failed_services":%s,"recommendation":"%s","mutations":"none"}\n' "$severity" "$load" "$disk" "$mem" "$failed_services" "$recommendation"
else
  printf '🩹 故障自愈检查 ✅\n📈 负载: %s\n💽 根分区: %s%%\n💾 内存: %s\n🚦 风险等级: %s\n🧭 建议: %s\n🔒 当前仅诊断和生成建议，不会删除文件或重启服务。\n' "$load" "$disk" "$mem" "$severity" "$recommendation"
fi
