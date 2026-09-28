#!/usr/bin/env bash
# ====================================================
# MIT License
# Copyright (c) 2025 BuBuXSY
# See LICENSE for full text.
# ====================================================
# 🧹 系统垃圾与缓存清理工具
# 功能：预览/清理临时文件、缓存和超大旧日志，可交互写入 cron
# By: BuBuXSY
# Version: 2026-09-29
# ====================================================

set -euo pipefail
umask 077

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
if [[ -r "$SCRIPT_DIR/lib/shell_tools_ui.sh" ]]; then
    # shellcheck source=lib/shell_tools_ui.sh
    source "$SCRIPT_DIR/lib/shell_tools_ui.sh"
    st_ui_init
else
    ST_UI_CYAN=''; ST_UI_BOLD=''; ST_UI_RESET=''
    st_info() { printf '[INFO] %s\n' "$1" >&2; }
    st_warn() { printf '[WARN] %s\n' "$1" >&2; }
    st_error() { printf '[ERROR] %s\n' "$1" >&2; }
fi

MODE=plan
KEEP_DAYS=${KEEP_DAYS:-7}
MAX_SIZE=${MAX_SIZE:-100M}
MAX_TOTAL=${MAX_TOTAL:-1G}
MAX_FILES=${MAX_FILES:-100}
CRON_SCHEDULE=${CRON_SCHEDULE:-'30 3 * * *'}
CRON_TAG='shell_tools_cleanup_junk'
PATHS_RAW=${CLEANUP_PATHS:-}
PLAN_COUNT=0
PLAN_BYTES=0

usage() {
    cat <<'EOF'
🧹 系统垃圾与缓存清理

用法:
  ./cleanup_junk.sh                         预览候选文件（默认，不删除）
  ./cleanup_junk.sh --run --yes             按规则清理
  ./cleanup_junk.sh --interactive           交互选择规则并可写入 cron
  ./cleanup_junk.sh --install-cron          安装默认 cron 清理任务
  ./cleanup_junk.sh --remove-cron           移除本工具写入的 cron 任务
  ./cleanup_junk.sh --plan --json           输出机器可读预览

选项:
  --run                 执行删除（仍会跳过受保护路径）
  --plan                只预览候选文件（默认）
  --interactive         交互设置保留天数、大小和 cron
  --yes                 跳过删除确认，仅用于自动化
  --days N              删除超过 N 天的候选文件（默认 7）
  --max-size SIZE       只处理达到该大小的文件（默认 100M）
  --max-total SIZE      每轮最多删除多少数据（默认 1G）
  --max-files N         每轮最多删除多少文件（默认 100）
  --paths "A B"          覆盖扫描目录（默认 /tmp /var/tmp 和用户缓存）
  --schedule "M H * * *" cron 表达式（默认 30 3 * * *）
  --install-cron        写入当前用户 crontab
  --remove-cron         删除本工具写入的 crontab
  --json                预览时输出 JSON
  -h, --help            显示帮助

安全规则：拒绝 /、/etc、/usr、/bin、/sbin、/var/lib、符号链接目录；默认只删除
临时文件、缓存文件和压缩日志，不清理未知扩展名或最近修改的文件。
EOF
}

has() { command -v "$1" >/dev/null 2>&1; }
die() { st_error "$1"; return 2; }

parse_size() {
    local input number unit multiplier=1
    input=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')
    [[ "$input" =~ ^([0-9]+)(KB|MB|GB|TB|K|M|G|T)?$ ]] || return 1
    number=${BASH_REMATCH[1]}; unit=${BASH_REMATCH[2]:-B}
    case "$unit" in
        K|KB) multiplier=1024 ;; M|MB) multiplier=$((1024 * 1024)) ;;
        G|GB) multiplier=$((1024 * 1024 * 1024)) ;; T|TB) multiplier=$((1024 * 1024 * 1024 * 1024)) ;;
    esac
    printf '%s\n' "$((10#$number * multiplier))"
}

normalize_paths() {
    local item resolved
    local -a requested=()
    if [[ -n "$PATHS_RAW" ]]; then
        read -r -a requested <<< "$PATHS_RAW"
    else
        requested=(/tmp /var/tmp "${TMPDIR:-}" "${XDG_CACHE_HOME:-}" "$HOME/.cache")
    fi
    SCAN_PATHS=()
    for item in "${requested[@]}"; do
        [[ -n "$item" && -d "$item" ]] || continue
        [[ ! -L "$item" ]] || { st_warn "跳过符号链接目录: $item"; continue; }
        resolved=$(cd "$item" 2>/dev/null && pwd -P) || continue
        case "$resolved" in
            /|/etc|/etc/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/var/lib|/var/lib/*)
                st_warn "跳过受保护目录: $resolved" ;;
            *) SCAN_PATHS+=("$resolved") ;;
        esac
    done
    ((${#SCAN_PATHS[@]} > 0)) || { st_error '没有可扫描的安全目录'; return 1; }
}

validate() {
    [[ "$KEEP_DAYS" =~ ^[0-9]+$ ]] || { st_error '--days 必须是非负整数'; return 2; }
    SIZE_BYTES=$(parse_size "$MAX_SIZE") || { st_error '--max-size 格式无效，例如 100M'; return 2; }
    TOTAL_BYTES=$(parse_size "$MAX_TOTAL") || { st_error '--max-total 格式无效，例如 1G'; return 2; }
    [[ "$MAX_FILES" =~ ^[1-9][0-9]*$ ]] || { st_error '--max-files 必须是正整数'; return 2; }
    [[ "$CRON_SCHEDULE" =~ ^[0-9*,/-]+[[:space:]][0-9*,/-]+[[:space:]][0-9*,/-]+[[:space:]][0-9*,/-]+[[:space:]][0-9*,/-]+$ ]] \
        || { st_error 'cron 表达式必须是五个数字/范围字段'; return 2; }
    has find || { st_error '缺少 find 命令'; return 1; }
    has awk || { st_error '缺少 awk 命令'; return 1; }
    normalize_paths
}

candidate_find() {
    local path=$1
    local -a find_prefix=(find) find_device=(-xdev)
    if [[ "$(uname -s)" == Darwin ]]; then find_prefix=(find -x); find_device=(); fi
    "${find_prefix[@]}" "$path" "${find_device[@]}" -type f ! -type l -mtime "+$KEEP_DAYS" -size "+${SIZE_BYTES}c" \
        \( -name '*.tmp' -o -name '*.temp' -o -name '*.cache' -o -name '*.bak' -o -name '*.old' \
        -o -name '*.log.*' -o -name 'core.*' \) -print0 2>/dev/null || true
}

collect_candidates() {
    local path file size existing duplicate
    CANDIDATES=()
    PLAN_COUNT=0; PLAN_BYTES=0
    for path in "${SCAN_PATHS[@]}"; do
        while IFS= read -r -d '' file; do
            [[ -n "$file" ]] || continue
            duplicate=0
            for existing in "${CANDIDATES[@]}"; do [[ "$existing" != "$file" ]] || { duplicate=1; break; }; done
            ((duplicate == 0)) || continue
            ((PLAN_COUNT < MAX_FILES)) || continue
            size=$(wc -c < "$file" 2>/dev/null || printf 0)
            [[ "$size" =~ ^[0-9]+$ ]] || size=0
            ((PLAN_BYTES + size <= TOTAL_BYTES)) || continue
            CANDIDATES+=("$file")
            PLAN_COUNT=$((PLAN_COUNT + 1)); PLAN_BYTES=$((PLAN_BYTES + size))
        done < <(candidate_find "$path")
    done
}

human_bytes() {
    awk -v bytes="$1" 'BEGIN {split("B KB MB GB TB",u); i=1; while(bytes>=1024 && i<5){bytes/=1024;i++} printf "%.1f %s",bytes,u[i]}'
}

json_escape() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    printf '%s' "$value"
}

show_plan() {
    local file
    if [[ "${JSON_OUTPUT:-0}" == 1 ]]; then
        printf '{"mode":"%s","keep_days":%s,"max_size":"%s","count":%s,"bytes":%s,"paths":[' "$MODE" "$KEEP_DAYS" "$MAX_SIZE" "$PLAN_COUNT" "$PLAN_BYTES"
        local i=0
        for file in "${SCAN_PATHS[@]}"; do ((i++ > 0)) && printf ','; printf '"%s"' "$(json_escape "$file")"; done
        printf ']}\n'
        return 0
    fi
    printf '%s%s🧹 垃圾清理预览%s\n' "$ST_UI_CYAN" "$ST_UI_BOLD" "$ST_UI_RESET"
    printf '模式: %s | 保留: %s 天 | 最小文件: %s | 上限: %s 文件 / %s | 预计: %s 个 / %s\n' \
        "$MODE" "$KEEP_DAYS" "$MAX_SIZE" "$MAX_FILES" "$MAX_TOTAL" "$PLAN_COUNT" "$(human_bytes "$PLAN_BYTES")"
    printf '目录: %s\n' "${SCAN_PATHS[*]}"
    for file in "${CANDIDATES[@]}"; do printf '  🗑️  %s\n' "$file"; done
    ((PLAN_COUNT > 0)) || st_info '没有符合条件的候选文件。'
}

cron_marker() { printf '# %s\n' "$CRON_TAG"; }

install_cron() {
    has crontab || { st_error '未找到 crontab；OpenWrt 请先安装/启用 cron，macOS 可使用系统 crontab'; return 1; }
    [[ "$SCRIPT_DIR" =~ ^[A-Za-z0-9_./-]+$ ]] || { st_error '脚本目录包含 cron 不安全字符'; return 2; }
    [[ -z "$PATHS_RAW" ]] || st_warn 'cron 使用默认扫描目录；自定义 --paths 仅对本次运行生效'
    local line="${CRON_SCHEDULE} ${SCRIPT_DIR}/cleanup_junk.sh --run --yes --days ${KEEP_DAYS} --max-size ${MAX_SIZE} --max-total ${MAX_TOTAL} --max-files ${MAX_FILES}"
    local existing filtered
    existing=$(crontab -l 2>/dev/null || true)
    filtered=$(printf '%s\n' "$existing" | awk -v tag="# $CRON_TAG" '$0 == tag {skip=1; next} skip {skip=0; next} {print}')
    { printf '%s\n' "$filtered"; cron_marker; printf '%s\n' "$line"; } | crontab -
    st_ok "已写入 cron: $line"
}

remove_cron() {
    has crontab || { st_error '未找到 crontab'; return 1; }
    local existing
    existing=$(crontab -l 2>/dev/null || true)
    printf '%s\n' "$existing" | awk -v tag="# $CRON_TAG" '$0 == tag {skip=1; next} skip {skip=0; next} {print}' | crontab -
    st_ok '已移除本工具的 cron 任务'
}

run_cleanup() {
    local file removed=0 failed=0
    for file in "${CANDIDATES[@]}"; do
        [[ -f "$file" && ! -L "$file" ]] || { failed=$((failed + 1)); continue; }
        if rm -f -- "$file"; then removed=$((removed + 1)); else failed=$((failed + 1)); fi
    done
    st_ok "清理完成：删除 $removed 个文件"
    ((failed == 0)) || st_warn "有 $failed 个文件删除失败"
    ((failed == 0))
}

main() {
    JSON_OUTPUT=0; ASSUME_YES=0; INTERACTIVE=0; INSTALL_CRON=0; REMOVE_CRON=0
    while (($#)); do
        case "$1" in
            --run) MODE=run; shift ;; --plan) MODE=plan; shift ;; --yes|-y) ASSUME_YES=1; shift ;;
            --interactive) INTERACTIVE=1; shift ;; --install-cron) INSTALL_CRON=1; shift ;; --remove-cron) REMOVE_CRON=1; shift ;;
            --json) JSON_OUTPUT=1; shift ;; --days) [[ $# -ge 2 ]] || return 2; KEEP_DAYS=$2; shift 2 ;;
            --max-size) [[ $# -ge 2 ]] || return 2; MAX_SIZE=$2; shift 2 ;;
            --max-total) [[ $# -ge 2 ]] || return 2; MAX_TOTAL=$2; shift 2 ;;
            --max-files) [[ $# -ge 2 ]] || return 2; MAX_FILES=$2; shift 2 ;;
            --paths) [[ $# -ge 2 ]] || return 2; PATHS_RAW=$2; shift 2 ;;
            --schedule) [[ $# -ge 2 ]] || return 2; CRON_SCHEDULE=$2; shift 2 ;; -h|--help) usage; return 0 ;;
            *) st_error "未知参数: $1"; usage >&2; return 2 ;;
        esac
    done
    if ((INTERACTIVE)); then
        [[ -t 0 ]] || { st_error '交互模式需要终端'; return 2; }
        read -r -p "保留天数 [$KEEP_DAYS]: " value || return 2; KEEP_DAYS=${value:-$KEEP_DAYS}
        read -r -p "单文件最小大小 [$MAX_SIZE]: " value || return 2; MAX_SIZE=${value:-$MAX_SIZE}
        printf '定时清理：0 不设置 / 1 每天 03:30 / 2 每周日 03:30 / 3 每月 1 日 03:30\n'
        read -r -p '选择 [0]: ' value || return 2
        case "$value" in
            1) CRON_SCHEDULE='30 3 * * *'; INSTALL_CRON=1 ;;
            2) CRON_SCHEDULE='30 3 * * 0'; INSTALL_CRON=1 ;;
            3) CRON_SCHEDULE='30 3 1 * *'; INSTALL_CRON=1 ;;
            ''|0) ;;
            *) st_error '无效的定时选项'; return 2 ;;
        esac
        read -r -p '现在执行删除？[y/N] ' value || return 2
        [[ "$value" == y || "$value" == Y ]] && MODE=run
    fi
    if ((REMOVE_CRON)); then remove_cron; return $?; fi
    validate || return $?
    ((INSTALL_CRON)) && install_cron
    collect_candidates
    show_plan
    [[ "$MODE" == run ]] || return 0
    ((ASSUME_YES)) || { [[ -t 0 ]] || { st_error '删除模式需要 --yes 或交互终端确认'; return 2; }; read -r -p '确认删除以上候选文件？[y/N] ' value; [[ "$value" == y || "$value" == Y ]] || return 0; }
    run_cleanup
}

main "$@"
