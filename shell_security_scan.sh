#!/usr/bin/env bash
# 🛡️ Shell_Tools Shell 安全扫描器脚本工具
# 功能：检查危险删除、动态执行与下载执行风险
# By: BuBuXSY
# Version: 2026-09-30
set -euo pipefail
# shellcheck disable=SC2034
GREEN=''; YELLOW=''; CYAN=''
: "${GREEN}${YELLOW}${CYAN}"
usage(){ printf '🛡️ Shell 安全扫描器\n用法: %s [目录] [--format text|json]\n' "$0"; }
root=.; format=text
while [[ $# -gt 0 ]]; do
 case "$1" in
  --format) format="${2:-}"; shift 2;; -h|--help) usage; exit 0;; --) shift; break;;
  -*) echo "未知参数: $1" >&2; exit 2;; *) root="$1"; shift;;
 esac
done
[[ "$format" == text || "$format" == json ]] || { echo '无效输出格式' >&2; exit 2; }
total=0; risky=0; report=''
for file in $(find "$root" -type f -name '*.sh' -print 2>/dev/null | sort); do
 total=$((total+1))
 if rg -n '(^|[^[:alnum:]_])rm[[:space:]]+-rf[[:space:]]+(/|"/|\$HOME)|eval[[:space:]]+|curl[^\n]*\|[[:space:]]*(ba)?sh' "$file" >/dev/null 2>&1; then risky=$((risky+1)); report+="$file\n"; fi
done
if [[ "$format" == json ]]; then printf '{"files":%s,"risky_files":%s,"report":"%s"}\n' "$total" "$risky" "${report//$'\n'/\\n}"; else printf '🛡️ Shell 安全扫描\n📁 文件数: %s\n⚠️ 风险文件: %s\n%b' "$total" "$risky" "$report"; fi
(( risky == 0 ))
