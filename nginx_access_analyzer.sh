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
# 📊 Nginx 访问日志分析脚本
# 功能：统计状态码、Top IP、Top URL、Top UA、可疑访问，并可选推送企业微信
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

LOG_FILE="${LOG_FILE:-/var/log/nginx/access.log}"
TOP_N="${TOP_N:-10}"
MAX_LINES="${MAX_LINES:-50000}"
WEBHOOK_URL="${WEBHOOK_URL:-${WECHAT_WEBHOOK_URL:-}}"

REPORT_FILE=""

usage() {
    cat <<EOF
📊 Nginx 访问日志分析

用法:
  ./nginx_access_analyzer.sh
  LOG_FILE=/var/log/nginx/access.log TOP_N=20 ./nginx_access_analyzer.sh

环境变量:
  LOG_FILE          📄 Nginx access.log 路径，默认 /var/log/nginx/access.log
  TOP_N             🔢 Top 列表数量，默认 10
  MAX_LINES         📚 最多分析最后多少行，默认 50000
  WEBHOOK_URL       📣 企业微信 webhook，可选
  WECHAT_WEBHOOK_URL 📣 企业微信 webhook，可选
EOF
}

banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║        📊 Nginx 访问日志分析                 ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

section() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" | tee -a "$REPORT_FILE"
    echo -e "${BOLD}🔎 $1${RESET}" | tee -a "$REPORT_FILE"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" | tee -a "$REPORT_FILE"
}

info() {
    echo -e "${BLUE}ℹ️  $1${RESET}" | tee -a "$REPORT_FILE"
}

ok() {
    echo -e "${GREEN}✅ $1${RESET}" | tee -a "$REPORT_FILE"
}

warn() {
    echo -e "${YELLOW}⚠️  $1${RESET}" | tee -a "$REPORT_FILE"
}

error() {
    echo -e "${RED}❌ $1${RESET}" | tee -a "$REPORT_FILE"
}

cleanup() {
    [[ -n "$REPORT_FILE" && -f "$REPORT_FILE" ]] && rm -f "$REPORT_FILE"
    return 0
}
trap cleanup EXIT

prepare_report() {
    REPORT_FILE=$(mktemp /tmp/nginx_access_report_XXXXXX.txt)
}

validate() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    if [[ ! -f "$LOG_FILE" ]]; then
        error "日志文件不存在：$LOG_FILE"
        exit 1
    fi

    if [[ ! "$TOP_N" =~ ^[0-9]+$ || "$TOP_N" -lt 1 ]]; then
        error "TOP_N 必须是大于 0 的数字"
        exit 1
    fi

    if [[ ! "$MAX_LINES" =~ ^[0-9]+$ || "$MAX_LINES" -lt 1 ]]; then
        error "MAX_LINES 必须是大于 0 的数字"
        exit 1
    fi
}

sample_log() {
    tail -n "$MAX_LINES" "$LOG_FILE"
}

show_overview() {
    section "基础信息"
    local total
    total=$(sample_log | wc -l | awk '{print $1}')
    info "📄 日志文件：$LOG_FILE"
    info "📚 分析范围：最后 $MAX_LINES 行"
    info "🧾 实际行数：$total"
    info "🕒 分析时间：$(date '+%F %T')"
}

show_status_codes() {
    section "HTTP 状态码分布"
    sample_log | awk '{code=$9; if (code ~ /^[0-9][0-9][0-9]$/) count[code]++} END {for (code in count) print count[code], code}' \
        | sort -nr \
        | head -n "$TOP_N" \
        | awk '{printf "   📌 %-6s %s 次\n", $2, $1}' \
        | tee -a "$REPORT_FILE"

    local err_count
    err_count=$(sample_log | awk '$9 ~ /^[45][0-9][0-9]$/ {count++} END {print count+0}')
    if [[ "$err_count" -gt 0 ]]; then
        warn "发现 $err_count 条 4xx/5xx 记录，请关注异常请求或后端错误"
    else
        ok "未发现明显 4xx/5xx 异常"
    fi
}

show_top_ips() {
    section "Top IP"
    sample_log | awk '{ip=$1; if (ip != "") count[ip]++} END {for (ip in count) print count[ip], ip}' \
        | sort -nr \
        | head -n "$TOP_N" \
        | awk '{printf "   🌍 %-18s %s 次\n", $2, $1}' \
        | tee -a "$REPORT_FILE"
}

show_top_urls() {
    section "Top URL"
    sample_log | awk '{url=$7; if (url != "") count[url]++} END {for (url in count) print count[url], url}' \
        | sort -nr \
        | head -n "$TOP_N" \
        | awk '{count=$1; $1=""; sub(/^ /, ""); printf "   🔗 %-6s %s\n", count "次", $0}' \
        | tee -a "$REPORT_FILE"
}

show_top_user_agents() {
    section "Top User-Agent"
    sample_log | awk -F'"' 'NF >= 6 {ua=$6; if (ua != "") count[ua]++} END {for (ua in count) print count[ua] "\t" ua}' \
        | sort -nr \
        | head -n "$TOP_N" \
        | awk -F'\t' '{printf "   🧭 %-6s %s\n", $1 "次", $2}' \
        | tee -a "$REPORT_FILE"
}

show_suspicious() {
    section "可疑访问线索"
    local patterns='wp-admin|wp-login|\.env|/etc/passwd|phpmyadmin|\.git|/boaform|HNAP1|cgi-bin|eval\(|base64|select.+from|union.+select'
    local hits
    hits=$(sample_log | grep -Eia "$patterns" | tail -n "$TOP_N" || true)

    if [[ -z "$hits" ]]; then
        ok "未命中常见扫描 / 注入 / 敏感路径特征"
    else
        warn "发现疑似扫描或攻击请求，最近 $TOP_N 条如下："
        printf '%s\n' "$hits" | sed 's/^/   🚨 /' | tee -a "$REPORT_FILE"
    fi
}

send_wechat() {
    [[ -n "$WEBHOOK_URL" && "$WEBHOOK_URL" != *"你的"* ]] || return 0

    local clean_content
    clean_content=$(sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' "$REPORT_FILE" \
        | sed ':a;N;$!ba;s/\n/\\n/g' \
        | sed 's/"/\\"/g')

    local json
    json="{\"msgtype\":\"text\",\"text\":{\"content\":\"📊 Nginx 访问日志分析\\n$clean_content\"}}"

    if curl -fsS -X POST "$WEBHOOK_URL" -H 'Content-Type: application/json' -d "$json" >/dev/null; then
        ok "📣 企业微信推送成功"
    else
        warn "📣 企业微信推送失败，分析结果已在本地输出"
    fi
}

main() {
    prepare_report
    validate "$@"
    banner
    show_overview
    show_status_codes
    show_top_ips
    show_top_urls
    show_top_user_agents
    show_suspicious
    send_wechat
}

main "$@"
