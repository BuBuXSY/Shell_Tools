#!/usr/bin/env bash
# 🌐 Shell_Tools 远程巡检中心脚本工具
# 功能：通过 SSH 批量执行只读健康巡检
# By: BuBuXSY
# Version: 2026-09-30
set -euo pipefail
# shellcheck disable=SC2034
GREEN=''; YELLOW=''; CYAN=''
: "${GREEN}${YELLOW}${CYAN}"
usage(){ printf '🌐 远程巡检中心\n用法: %s --host user@host[,user@host] [--format text|json] [--plan]\n' "$0"; }
hosts=''; plan=0; format=text
json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; :a;N;$!ba;s/\n/\\n/g'; }
while [[ $# -gt 0 ]]; do case "$1" in --host) hosts="${2:-}"; shift 2;; --format) format="${2:-}"; shift 2;; --plan) plan=1; shift;; -h|--help) usage; exit 0;; *) echo "未知参数: $1" >&2; exit 2;; esac; done
[[ "$format" == text || "$format" == json ]] || { echo '无效输出格式' >&2; exit 2; }
if (( plan )); then printf '远程巡检预览\n目标: %s\n仅执行 SSH 只读命令，不写入远端。\n' "${hosts:-交互指定}"; exit 0; fi
[[ -n "$hosts" ]] || { echo '--host 不能为空' >&2; exit 2; }
IFS=',' read -r -a targets <<< "$hosts"; failed=0
for host in "${targets[@]}"; do
 output=''; ok=true
 if ! output=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" 'printf "主机: "; hostname; printf "内核: "; uname -r; uptime; df -h /; free -m' 2>&1); then failed=$((failed+1)); ok=false; fi
 if [[ "$format" == json ]]; then printf '{"host":"%s","ok":%s,"output":"%s"}\n' "$(json_escape "$host")" "$ok" "$(json_escape "$output")"; else printf '🌐 %s %s\n%s\n' "$host" "$([[ "$ok" == true ]] && echo ✅ || echo ❌)" "$output"; fi
done
(( failed == 0 ))
