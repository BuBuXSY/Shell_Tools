#!/usr/bin/env bash
# ====================================================
# MIT License
# Copyright (c) 2025 BuBuXSY
# See LICENSE for full text.
# ====================================================
# 🧰 Shell_Tools 交互式工具台脚本 🧪
# 功能：集中浏览、配置并运行仓库中的运维脚本
# By: BuBuXSY
# Version: 2026-09-29
# ====================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
if [[ -r "$SCRIPT_DIR/lib/shell_tools_ui.sh" ]]; then
    # shellcheck source=lib/shell_tools_ui.sh
    source "$SCRIPT_DIR/lib/shell_tools_ui.sh"
    st_ui_init
else
    ST_UI_CYAN=''; ST_UI_BOLD=''; ST_UI_RESET=''; ST_UI_RED=''; ST_UI_GREEN=''
fi

SCRIPTS=(
    Auto_Upgrade_Nginx.sh collect_repeat_dns.sh disk_usage_analyzer.sh
    enhanced-doh-test.sh install_cert.sh kernel_optimization.sh
    nginx_access_analyzer.sh search_ip.sh server_security_audit.sh
    server_status_report.sh shell_tools_lint.sh ssl_cert_monitor.sh
    system_config_backup.sh system_health_snapshot.sh platform_check.sh cleanup_junk.sh update_Country.sh update_frp.sh
    server_benchmark.sh router_diagnostics.sh shell_security_scan.sh system_self_heal.sh remote_inspection.sh
)
CATEGORIES=(
    system network inspect network system system inspect inspect inspect
    inspect inspect inspect system inspect inspect system network system
    inspect network inspect system network
)
RISKS=(
    change change read read change change read read read read read read change read read change change change
    read read read read read
)
LABELS=(
    '升级 Nginx' '分析重复 DNS' '磁盘空间分析' 'DoH 节点测试'
    '申请/续期证书' '内核参数优化' 'Nginx 访问分析' '高频 IP 分析'
    '安全巡检' '服务器状态报告' '仓库自检' '证书有效期巡检'
    '系统配置备份' '系统健康快照' '平台适配检查' '垃圾缓存清理' '更新 GeoIP 数据库' 'FRP 安装/升级'
    '性能基准测试' '软路由诊断' 'Shell 安全扫描' '故障自愈助手' '远程巡检中心'
)

usage() {
    cat <<'EOF'
🧰 Shell_Tools 工具台

用法:
  ./shell_tools.sh                    打开交互式工具台（需要终端）
  ./shell_tools.sh --list             列出全部工具
  ./shell_tools.sh --dashboard [--format text|json|markdown]  查看健康总览
  ./shell_tools.sh --watch [秒数]                实时刷新仪表盘
  ./shell_tools.sh --run SCRIPT -- [ARGS...]
  ./shell_tools.sh --help

--run 直接传递参数给指定脚本，适合自动化；只接受本仓库登记的脚本名。
EOF
}

find_script() {
    local wanted=$1 i
    for i in "${!SCRIPTS[@]}"; do
        if [[ "${SCRIPTS[$i]}" == "$wanted" ]]; then
            printf '%s\n' "$i"
            return 0
        fi
    done
    return 1
}

list_scripts() {
    local i
    for i in "${!SCRIPTS[@]}"; do
        printf '%s\t%s\t%s\t%s\n' "${CATEGORIES[$i]}" "${RISKS[$i]}" "${SCRIPTS[$i]}" "${LABELS[$i]}"
    done
}

dashboard() {
    local load mem disk kernel score=100
    load=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo '?')
    mem=$(awk '/MemAvailable/{printf "%d", $2/1024; exit}' /proc/meminfo 2>/dev/null || echo '?')
    disk=$(df -P / 2>/dev/null | awk 'NR==2{print $5; exit}' || echo '?')
    kernel=$(uname -r 2>/dev/null || echo '?')
    [[ "$disk" =~ ^([89][0-9]|100)%$ ]] && score=$((score-25))
    printf '\n%s╔══════════════════════════════════════════════════════╗%s\n' "$ST_UI_CYAN$ST_UI_BOLD" "$ST_UI_RESET"
    printf '%s║ 🚀  Shell_Tools 超级运维控制台                    ║%s\n' "$ST_UI_CYAN$ST_UI_BOLD" "$ST_UI_RESET"
    printf '%s╠══════════════════════════════════════════════════════╣%s\n' "$ST_UI_CYAN" "$ST_UI_RESET"
    printf '║ 🧠 负载 %-8s 💾 可用内存 %-8s 💽 根盘 %-8s ║\n' "$load" "${mem}MB" "$disk"
    printf '║ 🐧 内核 %-42s ║\n' "$kernel"
    printf '║ 💚 健康评分 %-3s/100   🧰 工具模块 %-3s 个          ║\n' "$score" "${#SCRIPTS[@]}"
    printf '%s╚══════════════════════════════════════════════════════╝%s\n' "$ST_UI_CYAN" "$ST_UI_RESET"
}

dashboard_json() {
    local load mem disk kernel score=100 disk_num
    load=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo unknown)
    mem=$(awk '/MemAvailable/{printf "%d", $2/1024; exit}' /proc/meminfo 2>/dev/null || echo 0)
    disk=$(df -P / 2>/dev/null | awk 'NR==2{print $5; exit}' || echo unknown)
    kernel=$(uname -r 2>/dev/null || echo unknown)
    disk_num=${disk%%%}
    [[ "$disk_num" =~ ^[0-9]+$ && "$disk_num" -ge 90 ]] && score=$((score-25))
    printf '{"health_score":%s,"load":"%s","memory_available_mb":%s,"root_disk":"%s","kernel":"%s","modules":%s}\n' \
        "$score" "$load" "${mem:-0}" "$disk" "$kernel" "${#SCRIPTS[@]}"
}

dashboard_markdown() {
    local load mem disk kernel score=100 disk_num
    load=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo unknown)
    mem=$(awk '/MemAvailable/{printf "%d", $2/1024; exit}' /proc/meminfo 2>/dev/null || echo 0)
    disk=$(df -P / 2>/dev/null | awk 'NR==2{print $5; exit}' || echo unknown)
    kernel=$(uname -r 2>/dev/null || echo unknown)
    disk_num=${disk%%%}
    [[ "$disk_num" =~ ^[0-9]+$ && "$disk_num" -ge 90 ]] && score=$((score-25))
    printf '| 指标 | 当前值 |\n| --- | --- |\n| 💚 健康评分 | %s/100 |\n| 🧠 负载 | %s |\n| 💾 可用内存 | %s MB |\n| 💽 根分区 | %s |\n| 🐧 内核 | `%s` |\n| 🧰 工具模块 | %s |\n' "$score" "$load" "$mem" "$disk" "$kernel" "${#SCRIPTS[@]}"
}

watch_dashboard() {
    local interval="${1:-2}"
    [[ "$interval" =~ ^[1-9][0-9]*$ ]] || { printf '刷新间隔必须是正整数秒\n' >&2; return 2; }
    [[ -t 1 ]] || { printf '--watch 需要终端；可使用 --dashboard --format json 做自动化采集。\n' >&2; return 2; }
    while :; do
        printf '\033[H\033[2J'
        dashboard
        printf '\n%s⏱️ 每 %ss 刷新；按 Ctrl-C 退出%s\n' "$ST_UI_YELLOW" "$interval" "$ST_UI_RESET"
        sleep "$interval"
    done
}

read_value() {
    local prompt=$1 default=$2 value
    if ! read -r -p "$prompt [$default]: " value; then return 1; fi
    printf '%s' "${value:-$default}"
}

configure_command() {
    local name=$1 value
    CMD=("$SCRIPT_DIR/$name")
    ENV_ARGS=()
    case "$name" in
        Auto_Upgrade_Nginx.sh)
            value=$(read_value '版本通道 (stable/mainline)' stable) || return 1
            [[ "$value" == stable || "$value" == mainline ]] || return 2
            CMD+=(--channel "$value") ;;
        collect_repeat_dns.sh)
            value=$(read_value '配置文件' "$SCRIPT_DIR/dns_monitor.conf") || return 1
            CMD+=(--config "$value") ;;
        disk_usage_analyzer.sh)
            value=$(read_value '扫描目录（空格分隔）' '/') || return 1
            ENV_ARGS+=("TARGETS=$value")
            value=$(read_value 'Top 数量' 15) || return 1
            [[ "$value" =~ ^[1-9][0-9]*$ ]] || return 2
            ENV_ARGS+=("TOP_N=$value") ;;
        enhanced-doh-test.sh)
            value=$(read_value '测试域名' www.google.com) || return 1
            CMD+=(--domain "$value") ;;
        install_cert.sh) ;;
        kernel_optimization.sh)
            value=$(read_value '场景 (vps/vps_low/bypass/router/sbc/baremetal)' vps) || return 1
            case "$value" in vps|vps_low|bypass|router|sbc|baremetal) ;; *) return 2 ;; esac
            CMD+=(--scene "$value") ;;
        nginx_access_analyzer.sh)
            value=$(read_value '访问日志' /var/log/nginx/access.log) || return 1
            ENV_ARGS+=("LOG_FILE=$value") ;;
        search_ip.sh)
            value=$(read_value '访问日志' /var/log/nginx/access.log) || return 1
            CMD+=(--log-file "$value" --no-push) ;;
        server_security_audit.sh) ;;
        server_status_report.sh) CMD+=(--dry-run) ;;
        shell_tools_lint.sh) ;;
        ssl_cert_monitor.sh)
            value=$(read_value '远程主机（留空仅检查本地证书）' '') || return 1
            [[ -z "$value" ]] || CMD+=(--remote-host "$value") ;;
        system_config_backup.sh)
            value=$(read_value '备份目录' /var/backups/shell_tools) || return 1
            ENV_ARGS+=("BACKUP_DIR=$value") ;;
        system_health_snapshot.sh)
            value=$(read_value '格式 (text/json)' text) || return 1
            [[ "$value" == text || "$value" == json ]] || return 2
            CMD+=(--format "$value") ;;
        platform_check.sh)
            value=$(read_value '格式 (text/json)' text) || return 1
            [[ "$value" == text || "$value" == json ]] || return 2
            [[ "$value" == json ]] && CMD+=(--json) ;;
        cleanup_junk.sh)
            value=$(read_value '保留天数' 7) || return 1
            [[ "$value" =~ ^[0-9]+$ ]] || return 2
            CMD+=(--plan --days "$value") ;;
        update_Country.sh) ;;
        update_frp.sh)
            value=$(read_value '操作 (install/update/uninstall)' update) || return 1
            case "$value" in install|update|uninstall) ;; *) return 2 ;; esac
            CMD+=(--action "$value")
            value=$(read_value '角色 (frpc/frps)' frpc) || return 1
            [[ "$value" == frpc || "$value" == frps ]] || return 2
            CMD+=(--role "$value") ;;
        server_benchmark.sh) CMD+=(--format text) ;;
        router_diagnostics.sh) CMD+=(--format text) ;;
        shell_security_scan.sh) CMD+=("$SCRIPT_DIR" --format text) ;;
        system_self_heal.sh) CMD+=(--plan) ;;
        remote_inspection.sh)
            value=$(read_value '目标（user@host，逗号分隔）' '') || return 1
            [[ -n "$value" ]] || return 2
            CMD+=(--host "$value" --plan) ;;
    esac
}

run_selected() {
    local i=$1 mode answer status
    printf '\n%s%s%s\n' "$ST_UI_BOLD" "${LABELS[$i]}" "$ST_UI_RESET"
    printf '1) 默认运行   2) 自定义参数   3) 查看帮助   0) 返回\n'
    read -r -p '选择: ' mode || return 0
    case "$mode" in
        0) return 0 ;;
        3) "$SCRIPT_DIR/${SCRIPTS[$i]}" --help; return 0 ;;
        1) CMD=("$SCRIPT_DIR/${SCRIPTS[$i]}"); ENV_ARGS=() ;;
        2) if ! configure_command "${SCRIPTS[$i]}"; then printf '参数无效或已取消\n' >&2; return 0; fi ;;
        *) printf '无效选项\n' >&2; return 0 ;;
    esac
    # Reports with optional webhooks always open in local preview mode.
    if [[ "$mode" == 1 ]]; then
        case "${SCRIPTS[$i]}" in
            search_ip.sh) CMD+=(--no-push) ;;
            server_status_report.sh) CMD+=(--dry-run) ;;
        esac
    fi
    printf '命令: '
    printf '%q ' env "${ENV_ARGS[@]}" "${CMD[@]}"
    printf '\n'
    if [[ "${RISKS[$i]}" == change ]]; then
        read -r -p '此操作会修改系统或文件，确认运行？[y/N] ' answer || return 0
        [[ "$answer" == y || "$answer" == Y ]] || return 0
    fi
    status=0
    if [[ "${SCRIPTS[$i]}" == shell_tools_lint.sh ]] && declare -F st_ui_spinner >/dev/null; then
        local capture_file spinner_pid
        capture_file=$(mktemp "${TMPDIR:-/tmp}/shell-tools-menu.XXXXXX") || return 1
        env "${ENV_ARGS[@]}" "${CMD[@]}" > "$capture_file" 2>&1 &
        spinner_pid=$!
        st_ui_spinner "$spinner_pid" '正在检查仓库' || status=$?
        sed -n '1,$p' "$capture_file"
        rm -f -- "$capture_file"
    else
        env "${ENV_ARGS[@]}" "${CMD[@]}" || status=$?
    fi
    printf '\n退出状态: %s\n' "$status"
    read -r -p '按 Enter 返回工具台...' answer || true
}

interactive_menu() {
    local filter=all input i count visible=()
    if [[ ! -t 0 || ! -t 1 ]]; then
        printf '交互式工具台需要终端；自动化可使用 --list 或 --run。\n' >&2
        return 2
    fi
    while :; do
        dashboard
        printf '\n%s%sShell_Tools 工具台%s  分类: %s\n' "$ST_UI_CYAN" "$ST_UI_BOLD" "$ST_UI_RESET" "$filter"
        printf '序号  类型  工具 / 脚本\n'
        visible=()
        count=0
        for i in "${!SCRIPTS[@]}"; do
            [[ "$filter" == all || "${CATEGORIES[$i]}" == "$filter" ]] || continue
            visible+=("$i")
            count=$((count + 1))
            if [[ "${RISKS[$i]}" == change ]]; then
                printf '%2d    %s修改%s  %s · %s\n' "$count" "$ST_UI_RED" "$ST_UI_RESET" "${LABELS[$i]}" "${SCRIPTS[$i]}"
            else
                printf '%2d    %s只读%s  %s · %s\n' "$count" "$ST_UI_GREEN" "$ST_UI_RESET" "${LABELS[$i]}" "${SCRIPTS[$i]}"
            fi
        done
        printf '\n分类: a 全部 | s 系统 | n 网络/DNS | i 只读巡检 | q 退出\n'
        read -r -p '选择序号或分类: ' input || return 0
        case "$input" in
            q|Q) return 0 ;;
            a|A) filter=all; continue ;;
            s|S) filter=system; continue ;;
            n|N) filter=network; continue ;;
            i|I) filter=inspect; continue ;;
        esac
        if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= count )); then
            run_selected "${visible[input-1]}"
        else
            printf '无效选项\n' >&2
        fi
    done
}

main() {
    local index dashboard_format=text
    case "${1:-}" in
        '') interactive_menu ;;
        -h|--help) [[ $# -eq 1 ]] || return 2; usage ;;
        --list) [[ $# -eq 1 ]] || return 2; list_scripts ;;
        --dashboard)
            [[ $# -le 3 ]] || { usage >&2; return 2; }
            if [[ "${2:-}" == --format ]]; then
                dashboard_format="${3:-}"
                [[ "$dashboard_format" == text || "$dashboard_format" == json || "$dashboard_format" == markdown ]] || { printf '无效输出格式: %s\n' "$dashboard_format" >&2; return 2; }
            elif [[ -n "${2:-}" ]]; then
                usage >&2; return 2
            fi
            if [[ "$dashboard_format" == json ]]; then dashboard_json; elif [[ "$dashboard_format" == markdown ]]; then dashboard_markdown; else dashboard; fi
            ;;
        --watch)
            [[ $# -le 2 ]] || { usage >&2; return 2; }
            watch_dashboard "${2:-2}"
            ;;
        --run)
            [[ $# -ge 2 ]] || { usage >&2; return 2; }
            index=$(find_script "$2") || { printf '未知脚本: %s\n' "$2" >&2; return 2; }
            shift 2
            [[ "${1:-}" != -- ]] || shift
            exec "$SCRIPT_DIR/${SCRIPTS[$index]}" "$@" ;;
        *) usage >&2; return 2 ;;
    esac
}

main "$@"
