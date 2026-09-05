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
# Version: 2026-07-11
# ====================================================

set -euo pipefail
umask 077

# Optional, embedded color initialization: this script remains standalone.
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
        CYAN=$'\033[36m'; MAGENTA=$'\033[35m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
    else
        CYAN=''; MAGENTA=''; BOLD=''; RESET=''
    fi
}
init_colors


LOG_FILE="${LOG_FILE:-/var/log/nginx/access.log}"
TOP_N="${TOP_N:-10}"
MAX_LINES="${MAX_LINES:-50000}"
WINDOW_MINUTES="${WINDOW_MINUTES:-0}"
BUCKET_MINUTES="${BUCKET_MINUTES:-0}"
WEBHOOK_URL="${WEBHOOK_URL:-${WECHAT_WEBHOOK_URL:-}}"

WORK_DIR=""
REPORT_FILE=""
SAMPLE_FILE=""
SAMPLE_LINES=0

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
  WINDOW_MINUTES    🕒 仅分析最近 N 分钟（0 表示全部，默认 0）
  BUCKET_MINUTES    🪣 按 N 分钟时间桶统计请求（0 表示关闭，默认 0）
  WEBHOOK_URL       📣 企业微信 webhook，可选
  WECHAT_WEBHOOK_URL 📣 企业微信 webhook，可选
EOF
}

banner() { printf '%b⚡ NOC // Nginx 访问日志分析%b
' "$CYAN$BOLD" "$RESET"; }
section() { printf '
◆ %s
' "$1" | tee -a "$REPORT_FILE"; printf '%b◆ %s%b
' "$MAGENTA$BOLD" "$1" "$RESET" >&2; }
info() { printf '[ℹ] %s
' "$1" | tee -a "$REPORT_FILE"; }
ok() { printf '[✓] %s
' "$1" | tee -a "$REPORT_FILE"; }
warn() { printf '[!] %s
' "$1" | tee -a "$REPORT_FILE"; }
error() { printf '[×] %s
' "$1" | tee -a "$REPORT_FILE" >&2; }

cleanup() {
    [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf -- "$WORK_DIR"
    return 0
}
trap cleanup EXIT

prepare_report() {
    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nginx_access_analyzer.XXXXXX") || {
        printf '❌ 无法创建临时目录\n' >&2
        exit 1
    }
    REPORT_FILE="$WORK_DIR/report.txt"
    SAMPLE_FILE="$WORK_DIR/sample.log"
    : > "$REPORT_FILE"
}

validate() {
    case "$#" in
        0) ;;
        1)
            if [[ "$1" == "-h" || "$1" == "--help" ]]; then
                usage
                exit 0
            fi
            error "未知参数：$1"
            usage >&2
            exit 2
            ;;
        *)
            error "参数过多，本脚本通过环境变量接收配置"
            usage >&2
            exit 2
            ;;
    esac

    if [[ ! -f "$LOG_FILE" ]]; then
        error "日志文件不存在：$LOG_FILE"
        exit 1
    fi

    if [[ ! -r "$LOG_FILE" ]]; then
        error "日志文件不可读取：$LOG_FILE"
        exit 1
    fi

    if [[ ! "$TOP_N" =~ ^[0-9]+$ || "$TOP_N" -lt 1 ]]; then
        error "TOP_N 必须是大于 0 的数字"
        exit 2
    fi

    if [[ ! "$MAX_LINES" =~ ^[0-9]+$ || "$MAX_LINES" -lt 1 ]]; then
        error "MAX_LINES 必须是大于 0 的数字"
        exit 2
    fi
    for value in "$WINDOW_MINUTES" "$BUCKET_MINUTES"; do
        [[ "$value" =~ ^[0-9]+$ ]] || { error "WINDOW_MINUTES 和 BUCKET_MINUTES 必须是非负整数"; exit 2; }
    done

    local cmd
    for cmd in tail awk sort head grep sed tee date tr perl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "缺少必要命令：$cmd"
            exit 1
        fi
    done
}

snapshot_log() {
    if ! tail -n "$MAX_LINES" -- "$LOG_FILE" \
        | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177' > "$SAMPLE_FILE"; then
        error "读取日志失败：$LOG_FILE"
        exit 1
    fi
    if (( WINDOW_MINUTES > 0 )); then
        local cutoff
        cutoff=$(date -d "-${WINDOW_MINUTES} minutes" +%s 2>/dev/null) || { error "无法计算时间窗口"; exit 1; }
        perl -MTime::Piece -e 'my $cutoff = shift; while (<>) { if (/\[([^]]+)\]/) { my $epoch = eval { Time::Piece->strptime($1, "%d/%b/%Y:%H:%M:%S %z")->epoch }; print if defined $epoch && $epoch >= $cutoff; } }' "$cutoff" "$SAMPLE_FILE" > "$SAMPLE_FILE.window" || { error "无法按时间窗口筛选日志"; exit 1; }
        mv -- "$SAMPLE_FILE.window" "$SAMPLE_FILE"
    fi
    SAMPLE_LINES=$(awk 'END {print NR + 0}' "$SAMPLE_FILE")
}

show_overview() {
    section "基础信息"
    info "📄 日志文件：$LOG_FILE"
    info "📚 分析范围：最后 $MAX_LINES 行"
    info "🧾 实际行数：$SAMPLE_LINES"
    (( WINDOW_MINUTES > 0 )) && info "🕒 时间窗口：最近 ${WINDOW_MINUTES} 分钟"
    (( BUCKET_MINUTES > 0 )) && info "🪣 时间桶：${BUCKET_MINUTES} 分钟"
    info "🕒 分析时间：$(date '+%F %T')"
}

show_time_buckets() {
    (( BUCKET_MINUTES > 0 )) || return 0
    section "时间桶请求量"
    local output
    output=$(perl -MTime::Piece -e 'my $minutes = shift; my %count; while (<>) { if (/\[([^]]+)\]/) { my $epoch = eval { Time::Piece->strptime($1, "%d/%b/%Y:%H:%M:%S %z")->epoch }; $count{int($epoch / ($minutes * 60)) * $minutes * 60}++ if defined $epoch; } } print "$_ $count{$_}\n" for sort { $a <=> $b } keys %count' "$BUCKET_MINUTES" "$SAMPLE_FILE" | while read -r bucket count; do printf "   %s %s 次\n" "$(date -d "@$bucket" '+%F %H:%M' 2>/dev/null || printf '%s' "$bucket")" "$count"; done)
    [[ -n "$output" ]] && printf '%s\n' "$output" | tee -a "$REPORT_FILE" || warn "未解析到可用于时间桶的 Nginx 时间戳"
}

show_status_codes() {
    section "HTTP 状态码分布"
    local output
    output=$(awk '{code=$9; if (code ~ /^[0-9][0-9][0-9]$/) count[code]++} END {for (code in count) print count[code], code}' "$SAMPLE_FILE" \
        | sort -nr \
        | head -n "$TOP_N" \
        | awk '{printf "   📌 %-6s %s 次\n", $2, $1}' || true)
    if [[ -n "$output" ]]; then
        printf '%s\n' "$output" | tee -a "$REPORT_FILE"
    else
        warn "未解析到标准 Combined/Common 格式的 HTTP 状态码"
    fi

    local err_count
    err_count=$(awk '$9 ~ /^[45][0-9][0-9]$/ {count++} END {print count+0}' "$SAMPLE_FILE")
    if [[ "$err_count" -gt 0 ]]; then
        warn "发现 $err_count 条 4xx/5xx 记录，请关注异常请求或后端错误"
    else
        ok "未发现明显 4xx/5xx 异常"
    fi
}

show_top_ips() {
    section "Top IP"
    local output
    output=$(awk '{ip=$1; if (ip != "") count[ip]++} END {for (ip in count) print count[ip], ip}' "$SAMPLE_FILE" \
        | sort -nr \
        | head -n "$TOP_N" \
        | awk '{printf "   🌍 %-18s %s 次\n", $2, $1}' || true)
    if [[ -n "$output" ]]; then
        printf '%s\n' "$output" | tee -a "$REPORT_FILE"
    else
        warn "未解析到客户端 IP"
    fi
}

show_top_urls() {
    section "Top URL"
    local output
    output=$(awk '{url=$7; if (url != "") count[url]++} END {for (url in count) print count[url], url}' "$SAMPLE_FILE" \
        | sort -nr \
        | head -n "$TOP_N" \
        | awk '{count=$1; $1=""; sub(/^ /, ""); printf "   🔗 %-6s %s\n", count "次", $0}' || true)
    if [[ -n "$output" ]]; then
        printf '%s\n' "$output" | tee -a "$REPORT_FILE"
    else
        warn "未解析到请求 URL"
    fi
}

show_top_user_agents() {
    section "Top User-Agent"
    local output
    output=$(awk -F'"' 'NF >= 6 {ua=$6; if (ua != "") count[ua]++} END {for (ua in count) print count[ua] "\t" ua}' "$SAMPLE_FILE" \
        | sort -nr \
        | head -n "$TOP_N" \
        | awk -F'\t' '{printf "   🧭 %-6s %s\n", $1 "次", $2}' || true)
    if [[ -n "$output" ]]; then
        printf '%s\n' "$output" | tee -a "$REPORT_FILE"
    else
        info "日志格式中未包含可解析的 User-Agent"
    fi
}

show_suspicious() {
    section "可疑访问线索"
    local patterns='wp-admin|wp-login|\.env|/etc/passwd|phpmyadmin|\.git|/boaform|HNAP1|cgi-bin|eval\(|base64|select.+from|union.+select'
    local hits
    hits=$(grep -Eia "$patterns" "$SAMPLE_FILE" | tail -n "$TOP_N" || true)

    if [[ -z "$hits" ]]; then
        ok "未命中常见扫描 / 注入 / 敏感路径特征"
    else
        warn "发现疑似扫描或攻击请求，最近 $TOP_N 条如下："
        printf '%s\n' "$hits" | sed 's/^/   🚨 /' | tee -a "$REPORT_FILE"
    fi
}

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\b'/\\b}
    value=${value//$'\f'/\\f}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

send_wechat() {
    [[ -n "$WEBHOOK_URL" && "$WEBHOOK_URL" != *"你的"* ]] || return 0

    if [[ ! "$WEBHOOK_URL" =~ ^https://[^[:space:][:cntrl:]]+$ ]]; then
        warn "Webhook URL 必须使用 https://，已跳过推送"
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        warn "已配置 WEBHOOK_URL，但缺少 curl，跳过企业微信推送"
        return 0
    fi

    local clean_content
    local escape_char=$'\033'
    clean_content=$(sed -E "s/${escape_char}\\[[0-9;]*[[:alpha:]]//g" "$REPORT_FILE")

    local json
    local content
    content="📊 Nginx 访问日志分析
$clean_content"
    json="{\"msgtype\":\"text\",\"text\":{\"content\":\"$(json_escape "$content")\"}}"

    local response
    if ! response=$(curl --fail-with-body --silent --show-error --proto '=https' --proto-redir '=https' --connect-timeout 5 --max-time 15 -X POST \
        -H 'Content-Type: application/json' --data-binary "$json" -- "$WEBHOOK_URL"); then
        warn "📣 企业微信推送失败，分析结果已在本地输出"
    elif [[ "$response" =~ \"errcode\"[[:space:]]*:[[:space:]]*0([,}]) ]]; then
        ok "📣 企业微信推送成功"
    else
        warn "📣 企业微信接口返回异常：${response:0:200}"
    fi
}

main() {
    prepare_report
    validate "$@"
    banner
    snapshot_log
    show_overview
    if [[ "$SAMPLE_LINES" -eq 0 ]]; then
        warn "日志文件为空，没有可分析的访问记录"
        send_wechat
        return 0
    fi
    show_time_buckets
    show_status_codes
    show_top_ips
    show_top_urls
    show_top_user_agents
    show_suspicious
    send_wechat
}

main "$@"
