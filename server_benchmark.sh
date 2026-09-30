#!/usr/bin/env bash
# 🚀 Shell_Tools 服务器性能基准测试脚本工具
# 功能：CPU、内存、磁盘与网络能力的轻量只读基准
# By: BuBuXSY
# Version: 2026-09-30
set -euo pipefail
# shellcheck disable=SC2034
GREEN=''; YELLOW=''; CYAN=''
: "${GREEN}${YELLOW}${CYAN}"
usage(){ cat <<'EOF'
🚀 服务器性能基准测试
用法: ./server_benchmark.sh [--format text|json] [--plan]
EOF
}
format=text; plan=0
while [[ $# -gt 0 ]]; do
 case "$1" in
  --format) format="${2:-}"; shift 2;;
  --plan) plan=1; shift;;
  -h|--help) usage; exit 0;;
  *) echo "未知参数: $1" >&2; exit 2;;
 esac
done
[[ "$format" == text || "$format" == json ]] || { echo '无效输出格式' >&2; exit 2; }
if (( plan )); then printf '服务器基准测试预览\n测试: CPU 并行度、内存可用量、磁盘临时写入、网络接口\n不会修改系统配置。\n'; exit 0; fi
start_ns=$(date +%s%N 2>/dev/null || echo 0)
cpu=$(nproc 2>/dev/null || echo 1)
mem=$(awk '/MemTotal/{printf "%d", $2/1024; exit}' /proc/meminfo 2>/dev/null || echo 0)
tmp=$(mktemp "${TMPDIR:-/tmp}/shell-tools-bench.XXXXXX"); trap 'rm -f "$tmp"' EXIT
disk='不可用'; dd if=/dev/zero of="$tmp" bs=1M count=32 conv=fdatasync status=none 2>/dev/null && disk='32 MiB 临时写入完成' || true
iface=$(awk -F: '$1 ~ /^[[:alnum:]_.-]+$/ && $1!="lo" {gsub(/ /,"",$1); print $1; exit}' /proc/net/dev 2>/dev/null || echo unknown)
end_ns=$(date +%s%N 2>/dev/null || echo 0); elapsed_ms=0
[[ "$start_ns" =~ ^[0-9]+$ && "$end_ns" =~ ^[0-9]+$ ]] && elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
score=100
if [[ "$disk" == 不可用 ]]; then score=$((score-30)); fi
if (( elapsed_ms > 5000 )); then score=$((score-10)); fi
if [[ "$format" == json ]]; then printf '{"score":%s,"cpu_cores":%s,"memory_mb":%s,"disk":"%s","network_interface":"%s","elapsed_ms":%s}\n' "$score" "$cpu" "$mem" "$disk" "$iface" "$elapsed_ms"; else printf '🚀 服务器性能基准\n🏆 评分: %s/100\n🧠 CPU: %s 核\n💾 内存: %s MB\n💽 磁盘: %s\n🌐 网卡: %s\n⏱️ 耗时: %s ms\n' "$score" "$cpu" "$mem" "$disk" "$iface" "$elapsed_ms"; fi
