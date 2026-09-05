#!/usr/bin/env bash
# ====================================================
# 🩺 只读系统健康快照工具
# 功能：汇总运行时间、负载、内存、磁盘、inode、监听端口和服务状态；不修改系统或发送网络请求
# By: BuBuXSY
# Version: 2026-09-05
# ====================================================
set -u -o pipefail

FORMAT=text
STRICT=false
COLOR_MODE=${COLOR_MODE:-auto}
PROC_ROOT=${ST_HEALTH_PROC_ROOT:-/proc}
WARNINGS=()

usage() {
    cat <<'EOF'
只读系统健康快照

用法: ./system_health_snapshot.sh [--format text|json] [--strict] [--no-color] [--color=auto|always|never]

选项:
  -f, --format FORMAT     输出 text（默认）或 json
      --strict            有缺失数据或检查失败时返回 1
      --no-color          禁用 ANSI 颜色
      --color=MODE        auto、always 或 never
  -h, --help              显示帮助

所有快照数据均为本机只读采集；JSON 始终只写 stdout。
EOF
}

while (($#)); do
    case "$1" in
        -f|--format) [[ $# -ge 2 ]] || { printf '参数 %s 缺少格式\n' "$1" >&2; exit 2; }; FORMAT=$2; shift 2 ;;
        --format=*) FORMAT=${1#*=}; shift ;;
        --strict) STRICT=true; shift ;;
        --no-color) COLOR_MODE=never; shift ;;
        --color=*) COLOR_MODE=${1#*=}; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf '未知参数: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done
case "$FORMAT" in text|json) ;; *) printf '无效输出格式: %s\n' "$FORMAT" >&2; exit 2;; esac
case "$COLOR_MODE" in auto|always|never) ;; *) printf '无效颜色模式: %s\n' "$COLOR_MODE" >&2; exit 2;; esac

if [[ -r "${BASH_SOURCE[0]%/*}/lib/shell_tools_ui.sh" ]]; then
    # shellcheck source=lib/shell_tools_ui.sh
    source "${BASH_SOURCE[0]%/*}/lib/shell_tools_ui.sh"
    st_ui_init "$COLOR_MODE"
else
    st_info() { :; }; st_warn() { printf '[WARN] %s\n' "$1" >&2; }; st_error() { printf '[ERROR] %s\n' "$1" >&2; }
fi
warn() { WARNINGS+=("$1"); [[ "$FORMAT" == text ]] && st_warn "$1" || true; }
json_escape() { local v=$1; v=${v//\\/\\\\}; v=${v//\"/\\\"}; v=${v//$'\n'/\\n}; v=${v//$'\r'/\\r}; v=${v//$'\t'/\\t}; printf '%s' "$v"; }
read_first() { [[ -r "$1" ]] && IFS= read -r REPLY < "$1" || return 1; }

uptime_seconds=null; load1=null; load5=null; load15=null; mem_total_kb=null; mem_available_kb=null
if read_first "$PROC_ROOT/uptime"; then uptime_seconds=${REPLY%% *}; else warn "无法读取 $PROC_ROOT/uptime"; fi
if read_first "$PROC_ROOT/loadavg"; then read -r load1 load5 load15 _ <<< "$REPLY"; else warn "无法读取 $PROC_ROOT/loadavg"; fi
if [[ -r "$PROC_ROOT/meminfo" ]]; then
    mem_total_kb=$(grep -m1 '^MemTotal:' "$PROC_ROOT/meminfo" | tr -s ' ' | cut -d' ' -f2 || true)
    mem_available_kb=$(grep -m1 '^MemAvailable:' "$PROC_ROOT/meminfo" | tr -s ' ' | cut -d' ' -f2 || true)
    [[ "$mem_total_kb" =~ ^[0-9]+$ && "$mem_available_kb" =~ ^[0-9]+$ ]] || { mem_total_kb=null; mem_available_kb=null; warn "无法解析内存数据"; }
else warn "无法读取 $PROC_ROOT/meminfo"; fi

disk=$(df -P -x tmpfs -x devtmpfs 2>/dev/null | tail -n +2 || true)
inodes=$(df -Pi -x tmpfs -x devtmpfs 2>/dev/null | tail -n +2 || true)
[[ -n "$disk" ]] || warn "无法采集磁盘使用率"
[[ -n "$inodes" ]] || warn "无法采集 inode 使用率"
ports=''
if command -v ss >/dev/null 2>&1; then ports=$(ss -H -ltn 2>/dev/null | wc -l | tr -d ' ' || true); else warn "缺少 ss，跳过监听端口统计"; fi
services=''
if command -v systemctl >/dev/null 2>&1; then services=$(systemctl --no-legend --state=failed --type=service 2>/dev/null | wc -l | tr -d ' ' || true); else warn "缺少 systemctl，跳过失败服务统计"; fi

if [[ "$FORMAT" == json ]]; then
    printf '{"uptime_seconds":%s,"load":{"1m":%s,"5m":%s,"15m":%s},"memory_kb":{"total":%s,"available":%s},"listening_tcp_ports":%s,"failed_services":%s,"warnings":[' "$uptime_seconds" "$load1" "$load5" "$load15" "$mem_total_kb" "$mem_available_kb" "${ports:-null}" "${services:-null}"
    for i in "${!WARNINGS[@]}"; do (( i )) && printf ','; printf '"%s"' "$(json_escape "${WARNINGS[i]}")"; done
    printf ']}\n'
else
    st_info "只读系统健康快照"
    printf '运行时间（秒）: %s\n负载（1/5/15m）: %s / %s / %s\n内存（KiB，总计/可用）: %s / %s\n监听 TCP 端口: %s\n失败 systemd 服务: %s\n' "$uptime_seconds" "$load1" "$load5" "$load15" "$mem_total_kb" "$mem_available_kb" "${ports:-未知}" "${services:-未知}"
    printf '\n磁盘使用率:\n%s\n\nInode 使用率:\n%s\n' "${disk:-未知}" "${inodes:-未知}"
fi
if [[ "$STRICT" == true && ${#WARNINGS[@]} -gt 0 ]]; then
    exit 1
fi
exit 0
