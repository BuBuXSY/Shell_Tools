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
# Version: 2026-05-16
# ====================================================

set -euo pipefail

GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

WARN_DAYS="${WARN_DAYS:-15}"
CERT_DIRS="${CERT_DIRS:-/etc/nginx/cert_file /etc/letsencrypt/live /etc/x-ui}"
WEBHOOK_URL="${WEBHOOK_URL:-${WECHAT_WEBHOOK_URL:-}}"

TOTAL=0
WARN_COUNT=0
EXPIRED_COUNT=0
REPORT_LINES=()

usage() {
    cat <<EOF
🔐 SSL 证书有效期巡检

用法:
  ./ssl_cert_monitor.sh
  WARN_DAYS=30 ./ssl_cert_monitor.sh
  CERT_DIRS="/etc/nginx/cert_file /etc/letsencrypt/live" ./ssl_cert_monitor.sh

环境变量:
  WARN_DAYS          ⚠️  剩余天数小于等于该值时告警，默认 15
  CERT_DIRS          📁  证书扫描目录，多个目录用空格分隔
  WEBHOOK_URL        📣 企业微信 webhook，可选
  WECHAT_WEBHOOK_URL 📣 企业微信 webhook，可选
EOF
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║        🔐 SSL 证书有效期巡检                 ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${RESET}"
}

log_ok() {
    echo -e "${GREEN}✅ $1${RESET}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $1${RESET}"
}

log_error() {
    echo -e "${RED}❌ $1${RESET}"
}

add_report_line() {
    REPORT_LINES+=("$1")
}

find_cert_files() {
    local dir
    for dir in $CERT_DIRS; do
        [[ -d "$dir" ]] || continue
        find -L "$dir" -type f \( -name "*.pem" -o -name "*.crt" -o -name "*.cer" \) \
            ! -iname "*key*" ! -iname "*priv*" 2>/dev/null || true
    done | sort -u
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

    if ! end_date=$(openssl x509 -noout -enddate -in "$cert_file" 2>/dev/null | cut -d= -f2-); then
        log_warn "跳过无法解析的证书：$cert_file"
        return 0
    fi

    if ! end_epoch=$(date -d "$end_date" +%s 2>/dev/null); then
        log_warn "跳过无法解析过期时间的证书：$cert_file"
        return 0
    fi

    now_epoch=$(date +%s)
    days_left=$(( (end_epoch - now_epoch) / 86400 ))
    subject=$(format_subject "$cert_file")
    [[ -z "$subject" ]] && subject="$(basename "$cert_file")"

    TOTAL=$((TOTAL + 1))

    if (( days_left < 0 )); then
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

    add_report_line "$status | $subject | 剩余 ${days_left} 天 | $(date -d "$end_date" '+%F %T')"
}

send_wechat() {
    [[ -n "$WEBHOOK_URL" && "$WEBHOOK_URL" != *"你的"* ]] || return 0

    local content
    local lines
    lines=$(printf '%s\n' "${REPORT_LINES[@]}" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
    content="🔐 SSL 证书有效期巡检\\n🕒 时间：$(date '+%F %T')\\n📊 总数：$TOTAL，告警：$WARN_COUNT，已过期：$EXPIRED_COUNT\\n\\n$lines"

    local json
    json="{\"msgtype\":\"text\",\"text\":{\"content\":\"$content\"}}"

    if curl -fsS -X POST "$WEBHOOK_URL" -H 'Content-Type: application/json' -d "$json" >/dev/null; then
        log_ok "📣 企业微信推送成功"
    else
        log_warn "📣 企业微信推送失败，巡检结果已在本地输出"
    fi
}

main() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    banner

    if ! has_cmd openssl; then
        log_error "未找到 openssl，无法解析证书"
        exit 1
    fi

    log_info "📁 扫描目录：$CERT_DIRS"
    log_info "⏰ 告警阈值：剩余 ${WARN_DAYS} 天及以内"

    mapfile -t cert_files < <(find_cert_files)
    if [[ "${#cert_files[@]}" -eq 0 ]]; then
        log_warn "未找到证书文件，请通过 CERT_DIRS 指定扫描目录"
        exit 0
    fi

    echo
    local cert_file
    for cert_file in "${cert_files[@]}"; do
        check_cert "$cert_file"
    done

    echo
    if (( EXPIRED_COUNT > 0 )); then
        log_error "📌 巡检完成：共 $TOTAL 张证书，$EXPIRED_COUNT 张已过期，$WARN_COUNT 张即将过期"
    elif (( WARN_COUNT > 0 )); then
        log_warn "📌 巡检完成：共 $TOTAL 张证书，$WARN_COUNT 张即将过期"
    else
        log_ok "🎉 巡检完成：共 $TOTAL 张证书，全部在安全有效期内"
    fi

    send_wechat
}

main "$@"
