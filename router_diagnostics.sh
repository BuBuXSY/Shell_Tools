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
route=$(ip route show default 2>/dev/null | head -n1 || echo unavailable)
mtu=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* mtu \([0-9]*\).*/\1/p' | head -n1); mtu=${mtu:-unknown}
if [[ "$format" == json ]]; then printf '{"ipv4_forwarding":"%s","ipv6_forwarding":"%s","conntrack_count":"%s","conntrack_max":"%s","default_route":"%s","path_mtu":"%s"}\n' "$fwd" "$fwd6" "$ct" "$ctm" "$route" "$mtu"; else printf '🛜 软路由诊断 ✅\n🔀 IPv4 转发: %s\n🌐 IPv6 转发: %s\n🧱 conntrack: %s / %s\n🛣️ 默认路由: %s\n📦 路径 MTU: %s\n' "$fwd" "$fwd6" "$ct" "$ctm" "$route" "$mtu"; fi
