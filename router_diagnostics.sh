#!/usr/bin/env bash
# 🛜 Shell_Tools 软路由诊断器脚本工具
# 功能：检查转发、conntrack、默认路由与路径 MTU
# By: BuBuXSY
# Version: 2026-09-30
set -euo pipefail
# shellcheck disable=SC2034
GREEN=''; YELLOW=''; CYAN=''
: "${GREEN}${YELLOW}${CYAN}"
usage(){ printf '🛜 软路由诊断器\n用法: %s [--format text|json] [--plan]\n' "$0"; }
format=text; plan=0
while [[ $# -gt 0 ]]; do
 case "$1" in
  --format) format="${2:-}"; shift 2;; --plan) plan=1; shift;;
  -h|--help) usage; exit 0;; *) echo "未知参数: $1" >&2; exit 2;;
 esac
done
[[ "$format" == text || "$format" == json ]] || { echo '无效输出格式' >&2; exit 2; }
if (( plan )); then printf '软路由诊断预览\n检查: IPv4/IPv6 转发、conntrack、默认路由、路径 MTU\n只读，不修改网络配置。\n'; exit 0; fi
fwd=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo unknown)
fwd6=$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo unknown)
ct=$(sysctl -n net.netfilter.nf_conntrack_count 2>/dev/null || echo unavailable)
ctm=$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo unavailable)
route=$(ip route show default 2>/dev/null | head -n1 || true); route=${route:-unavailable}
mtu=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* mtu \([0-9]*\).*/\1/p' | head -n1 || true); mtu=${mtu:-unknown}
severity=ok; recommendation='转发和网络基础状态未发现明显风险'
if [[ "$fwd" != 1 ]]; then severity=warning; recommendation='IPv4 转发未开启；如果这是网关，请先确认 net.ipv4.ip_forward=1'; fi
if [[ "$route" == unavailable || -z "$route" ]]; then severity=critical; recommendation='未检测到默认路由，请检查网卡、DHCP 或上游网关'; fi
if [[ "$ct" =~ ^[0-9]+$ && "$ctm" =~ ^[0-9]+$ && "$ctm" -gt 0 && $((ct * 100 / ctm)) -ge 90 ]]; then severity=warning; recommendation='conntrack 使用率已超过 90%，建议提升上限并检查连接泄漏'; fi
if [[ "$format" == json ]]; then printf '{"severity":"%s","ipv4_forwarding":"%s","ipv6_forwarding":"%s","conntrack_count":"%s","conntrack_max":"%s","default_route":"%s","path_mtu":"%s","recommendation":"%s"}\n' "$severity" "$fwd" "$fwd6" "$ct" "$ctm" "$route" "$mtu" "$recommendation"; else printf '🛜 软路由诊断 ✅\n🚦 风险等级: %s\n🔀 IPv4 转发: %s\n🌐 IPv6 转发: %s\n🧱 conntrack: %s / %s\n🛣️ 默认路由: %s\n📦 路径 MTU: %s\n🧭 建议: %s\n' "$severity" "$fwd" "$fwd6" "$ct" "$ctm" "$route" "$mtu" "$recommendation"; fi
