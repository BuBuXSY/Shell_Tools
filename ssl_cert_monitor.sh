#!/usr/bin/env bash
# ====================================================
# MIT License
#
# Copyright (c) 2025 BuBuXSY
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ====================================================
# 🔐 SSL 证书有效期巡检脚本
# 功能：扫描本机证书文件，显示过期时间、剩余天数，并可选推送企业微信
# By: BuBuXSY
# Version: 2026-07-11
# ====================================================

set -euo pipefail

# Optional embedded UI; the script remains standalone when the shared library is absent.
COLOR_MODE="${COLOR_MODE:-auto}"
init_colors() {
    local mode="$COLOR_MODE"
    case "$mode" in auto|always|never) ;; *) mode=auto ;; esac
    case "$mode" in
        always) COLOR_ENABLED=1 ;;
        auto)
            if [[ -t 2 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then COLOR_ENABLED=1; else COLOR_ENABLED=0; fi
            ;;
        never) COLOR_ENABLED=0 ;;
    esac
    if [[ "$COLOR_ENABLED" == 1 ]]; then
        GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; BLUE=$'\033[36m'; CYAN=$'\033[36m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
    else GREEN=''; YELLOW=''; RED=''; BLUE=''; CYAN=''; BOLD=''; RESET=''; fi
}
init_colors

WARN_DAYS="${WARN_DAYS:-15}"
CERT_DIRS="${CERT_DIRS:-/etc/nginx/ssl /etc/nginx/cert_file /etc/letsencrypt/live /etc/x-ui}"
WEBHOOK_URL="${WEBHOOK_URL:-${WECHAT_WEBHOOK_URL:-}}"
EXIT_ON_WARNING="${EXIT_ON_WARNING:-0}"
REMOTE_HOST="${REMOTE_HOST:-}"
REMOTE_PORT="${REMOTE_PORT:-443}"
REMOTE_TIMEOUT="${REMOTE_TIMEOUT:-5}"

TOTAL=0
WARN_COUNT=0
EXPIRED_COUNT=0
INVALID_COUNT=0
SCAN_FAILURES=0
REPORT_LINES=()
CERT_PATHS=()
CERT_FILES=()
TEMP_FILES=()

usage() {
    cat <<EOF
🔐 SSL 证书有效期巡检

用法:
  ./ssl_cert_monitor.sh
  ./ssl_cert_monitor.sh --remote-host example.invalid --remote-port 443
  WARN_DAYS=30 ./ssl_cert_monitor.sh
  CERT_DIRS="/etc/nginx/ssl /etc/letsencrypt/live" ./ssl_cert_monitor.sh

环境变量:
  WARN_DAYS          ⚠️  剩余天数小于等于该值时告警，默认 15
  CERT_DIRS          📁  证书扫描目录，多个目录用空格分隔
  WEBHOOK_URL        📣 企业微信 webhook，可选
  WECHAT_WEBHOOK_URL 📣 企业微信 webhook，可选
  EXIT_ON_WARNING    🚦 设为 1 时，证书告警或解析失败后以状态码 1 退出
  REMOTE_HOST        🌐 可选远程 TLS 主机；仅在显式设置时连接
  REMOTE_PORT        🔌 远程 TLS 端口，默认 443
  REMOTE_TIMEOUT     ⏱️ 远程 TLS 连接超时秒数，默认 5

选项：--remote-host HOST [--remote-port PORT] [--remote-timeout SECONDS]
EOF
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

banner() { printf '%b⚡ NOC // SSL 证书有效期巡检%b
' "$CYAN$BOLD" "$RESET"; }
log_info() { printf '%b[ℹ] %s%b
' "$BLUE" "$1" "$RESET"; }
log_ok() { printf '%b[✓] %s%b
' "$GREEN" "$1" "$RESET"; }
log_warn() { printf '%b[!] %s%b
' "$YELLOW" "$1" "$RESET"; }
log_error() { printf '%b[×] %s%b
' "$RED" "$1" "$RESET" >&2; }

add_report_line() {
    REPORT_LINES+=("$1")
}

validate() {
    while (( $# )); do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            --remote-host) [[ $# -ge 2 && -n ${2:-} ]] || { log_error "参数 $1 缺少主机"; exit 2; }; REMOTE_HOST=$2; shift 2 ;;
            --remote-host=*) REMOTE_HOST=${1#*=}; shift ;;
            --remote-port) [[ $# -ge 2 ]] || { log_error "参数 $1 缺少端口"; exit 2; }; REMOTE_PORT=$2; shift 2 ;;
            --remote-port=*) REMOTE_PORT=${1#*=}; shift ;;
            --remote-timeout) [[ $# -ge 2 ]] || { log_error "参数 $1 缺少超时"; exit 2; }; REMOTE_TIMEOUT=$2; shift 2 ;;
            --remote-timeout=*) REMOTE_TIMEOUT=${1#*=}; shift ;;
            *) log_error "未知参数：$1"; usage >&2; exit 2 ;;
        esac
    done
    [[ "$WARN_DAYS" =~ ^[0-9]+$ ]] || { log_error "WARN_DAYS 必须是大于等于 0 的整数"; exit 2; }
    [[ "$EXIT_ON_WARNING" == 0 || "$EXIT_ON_WARNING" == 1 ]] || { log_error "EXIT_ON_WARNING 只能是 0 或 1"; exit 2; }
    [[ "$REMOTE_PORT" =~ ^[0-9]+$ ]] && (( REMOTE_PORT >= 1 && REMOTE_PORT <= 65535 )) || { log_error "REMOTE_PORT 必须是 1-65535 的整数"; exit 2; }
    [[ "$REMOTE_TIMEOUT" =~ ^[1-9][0-9]*$ ]] && (( REMOTE_TIMEOUT <= 300 )) || { log_error "REMOTE_TIMEOUT 必须是 1-300 的整数"; exit 2; }
    if [[ -n "$REMOTE_HOST" && ! "$REMOTE_HOST" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ && ! "$REMOTE_HOST" =~ ^[A-Za-z0-9]$ ]]; then log_error "REMOTE_HOST 无效"; exit 2; fi
    local cmd
    for cmd in openssl date find awk sed mktemp; do has_cmd "$cmd" || { log_error "缺少必要命令：$cmd"; exit 1; }; done
    read -r -a CERT_PATHS <<< "$CERT_DIRS"
}

collect_remote_cert() {
    [[ -n "$REMOTE_HOST" ]] || return 0
    local cert_file
    cert_file=$(mktemp "${TMPDIR:-/tmp}/ssl-remote-cert.XXXXXX") || { log_warn "无法创建远程证书临时文件"; SCAN_FAILURES=$((SCAN_FAILURES + 1)); return; }
    TEMP_FILES+=("$cert_file")
    if ! timeout "$REMOTE_TIMEOUT" openssl s_client -connect "${REMOTE_HOST}:${REMOTE_PORT}" -servername "$REMOTE_HOST" -showcerts </dev/null 2>/dev/null | openssl x509 -outform PEM > "$cert_file" 2>/dev/null; then
        log_warn "远程 TLS 连接或证书读取失败：${REMOTE_HOST}:${REMOTE_PORT}"
        SCAN_FAILURES=$((SCAN_FAILURES + 1)); return
    fi
    CERT_FILES+=("$cert_file")
    log_info "已读取远程 TLS 证书：${REMOTE_HOST}:${REMOTE_PORT}"
}

collect_cert_files() {
    local -A seen=()
    local dir
    local cert_file
    local fingerprint
    local dedupe_key
    local find_output
    local find_status
    for dir in "${CERT_PATHS[@]}"; do
        if [[ ! -d "$dir" ]]; then
            continue
        fi
        if [[ ! -r "$dir" || ! -x "$dir" ]]; then
            log_warn "跳过不可读取的证书目录：$dir"
            SCAN_FAILURES=$((SCAN_FAILURES + 1))
            continue
        fi

        find_output=$(mktemp "${TMPDIR:-/tmp}/ssl-cert-monitor.XXXXXX") || {
            log_warn "无法创建证书扫描临时文件：$dir"
            SCAN_FAILURES=$((SCAN_FAILURES + 1))
            continue
        }
        TEMP_FILES+=("$find_output")
        find_status=0
        find -L "$dir" -xdev -type f \( -iname "*.pem" -o -iname "*.crt" -o -iname "*.cer" \) \
            ! -iname "*key*" ! -iname "*priv*" -print0 > "$find_output" 2>/dev/null \
            || find_status=$?
        while IFS= read -r -d '' cert_file; do
            fingerprint=$(openssl x509 -noout -fingerprint -sha256 -in "$cert_file" 2>/dev/null \
                | awk -F= 'NF >= 2 {gsub(/:/, "", $2); print tolower($2); exit}' || true)
            if [[ -n "$fingerprint" ]]; then
                dedupe_key="fingerprint:$fingerprint"
            else
                dedupe_key="path:$cert_file"
            fi
            if [[ -z "${seen[$dedupe_key]+x}" ]]; then
                CERT_FILES+=("$cert_file")
                seen["$dedupe_key"]=1
            fi
        done < "$find_output"
        rm -f -- "$find_output"
        if [[ "$find_status" -ne 0 ]]; then
            SCAN_FAILURES=$((SCAN_FAILURES + 1))
            log_warn "证书目录扫描不完整：$dir"
        fi
    done
}

date_to_epoch() {
    local value="$1"
    if has_cmd gdate && gdate -d "$value" +%s 2>/dev/null; then
        return 0
    fi
    if date -d "$value" +%s 2>/dev/null; then
        return 0
    fi
    date -j -f '%b %e %T %Y %Z' "$value" +%s 2>/dev/null
}

format_epoch() {
    local epoch="$1"
    if date -d "@$epoch" '+%F %T' 2>/dev/null; then
        return 0
    fi
    date -r "$epoch" '+%F %T' 2>/dev/null || printf '%s' "$epoch"
}

format_subject() {
    local cert_file="$1"
    openssl x509 -noout -subject -in "$cert_file" 2>/dev/null \
        | sed -E 's/^subject=//; s/.*CN[ =]+([^,/]+).*/\1/' \
        | awk 'NF {print; exit}'
}

check_cert() {
    local cert_file="$1"
    local end_date
    local end_epoch
    local now_epoch
    local days_left
    local subject
    local status
    local end_line

    if ! end_line=$(openssl x509 -noout -enddate -in "$cert_file" 2>/dev/null) || [[ "$end_line" != notAfter=* ]]; then
        log_warn "跳过无法解析的证书：$cert_file"
        INVALID_COUNT=$((INVALID_COUNT + 1))
        add_report_line "⚠️ 无法解析 | $cert_file"
        return 0
    fi
    end_date=${end_line#notAfter=}

    if ! end_epoch=$(date_to_epoch "$end_date"); then
        log_warn "跳过无法解析过期时间的证书：$cert_file"
        INVALID_COUNT=$((INVALID_COUNT + 1))
        add_report_line "⚠️ 日期解析失败 | $cert_file | $end_date"
        return 0
    fi

    now_epoch=$(date +%s)
    if (( end_epoch <= now_epoch )); then
        days_left=$(( -((now_epoch - end_epoch + 86399) / 86400) ))
        (( days_left == 0 )) && days_left=-1
    else
        days_left=$(( (end_epoch - now_epoch + 86399) / 86400 ))
    fi
    subject=$(format_subject "$cert_file" || true)
    [[ -z "$subject" ]] && subject="$(basename "$cert_file")"

    TOTAL=$((TOTAL + 1))

    if (( end_epoch <= now_epoch )); then
        EXPIRED_COUNT=$((EXPIRED_COUNT + 1))
        status="❌ 已过期"
        log_error "$status | $subject | ${days_left} 天 | $cert_file"
    elif (( days_left <= WARN_DAYS )); then
        WARN_COUNT=$((WARN_COUNT + 1))
        status="⚠️ 即将过期"
        log_warn "$status | $subject | 剩余 ${days_left} 天 | $cert_file"
    else
        status="✅ 正常"
        log_ok "$status | $subject | 剩余 ${days_left} 天 | $cert_file"
    fi

    add_report_line "$status | $subject | 剩余 ${days_left} 天 | $(format_epoch "$end_epoch")"
}

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    value=${value//$'\b'/\\b}
    value=${value//$'\f'/\\f}
    printf '%s' "$value"
}

send_wechat() {
    [[ -n "$WEBHOOK_URL" && "$WEBHOOK_URL" != *"你的"* ]] || return 0

    if [[ ! "$WEBHOOK_URL" =~ ^https://[^[:space:][:cntrl:]]+$ ]]; then
        log_warn "Webhook URL 必须使用 https://，已跳过推送"
        return 1
    fi

    if ! has_cmd curl; then
        log_warn "已配置 WEBHOOK_URL，但缺少 curl，跳过企业微信推送"
        return 0
    fi

    local content
    local lines
    lines=$(printf '%s\n' "${REPORT_LINES[@]}")
    content="🔐 SSL 证书有效期巡检
🕒 时间：$(date '+%F %T')
📊 总数：$TOTAL，告警：$WARN_COUNT，已过期：$EXPIRED_COUNT，无法解析：$INVALID_COUNT，扫描不完整：$SCAN_FAILURES

$lines"

    local json
    json="{\"msgtype\":\"text\",\"text\":{\"content\":\"$(json_escape "$content")\"}}"

    local response
    if ! response=$(curl --fail-with-body --silent --show-error --proto '=https' --proto-redir '=https' --connect-timeout 5 --max-time 15 -X POST \
        -H 'Content-Type: application/json' --data-binary "$json" -- "$WEBHOOK_URL"); then
        log_warn "📣 企业微信推送失败，巡检结果已在本地输出"
    elif [[ "$response" =~ \"errcode\"[[:space:]]*:[[:space:]]*0[[:space:]]*([,}]) ]]; then
        log_ok "📣 企业微信推送成功"
    else
        log_warn "📣 企业微信接口返回异常：${response:0:200}"
    fi
}

main() {
    validate "$@"

    banner

    log_info "📁 扫描目录：$CERT_DIRS"
    log_info "⏰ 告警阈值：剩余 ${WARN_DAYS} 天及以内"

    collect_cert_files
    collect_remote_cert
    if [[ "${#CERT_FILES[@]}" -eq 0 ]]; then
        log_warn "未找到证书文件，请通过 CERT_DIRS 指定扫描目录"
        [[ "$EXIT_ON_WARNING" == "1" ]] && exit 1
        exit 0
    fi

    echo
    local cert_file
    for cert_file in "${CERT_FILES[@]}"; do
        check_cert "$cert_file"
    done

    echo
    if (( EXPIRED_COUNT > 0 )); then
        log_error "📌 巡检完成：共 $TOTAL 张有效证书，$EXPIRED_COUNT 张已过期，$WARN_COUNT 张即将过期，$INVALID_COUNT 个文件无法解析，$SCAN_FAILURES 个目录扫描不完整"
    elif (( WARN_COUNT > 0 || INVALID_COUNT > 0 || SCAN_FAILURES > 0 )); then
        log_warn "📌 巡检完成：共 $TOTAL 张有效证书，$WARN_COUNT 张即将过期，$INVALID_COUNT 个文件无法解析，$SCAN_FAILURES 个目录扫描不完整"
    else
        log_ok "🎉 巡检完成：共 $TOTAL 张证书，全部在安全有效期内"
    fi

    send_wechat

    if [[ "$EXIT_ON_WARNING" == "1" && $((EXPIRED_COUNT + WARN_COUNT + INVALID_COUNT + SCAN_FAILURES)) -gt 0 ]]; then
        return 1
    fi
}

cleanup() {
    if (( ${#TEMP_FILES[@]} > 0 )); then
        rm -f -- "${TEMP_FILES[@]}"
    fi
    return 0
}

trap cleanup EXIT
main "$@"
