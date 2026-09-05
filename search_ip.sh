#!/bin/bash
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
# 🔍 Nginx 高频 DNS 访问 IP 分析脚本
# 功能：从 Nginx access.log 中提取高频 DNS 访问 IP，查询归属地并可选推送企业微信
# By: BuBuXSY
# Version: 2026-07-11
# ====================================================

set -euo pipefail

# ===== 🎨 色彩输出 =====
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

log_info() { echo -e "${BLUE}ℹ️  $1${RESET}"; }
log_ok() { echo -e "${GREEN}✅ $1${RESET}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${RESET}"; }
log_error() { echo -e "${RED}❌ $1${RESET}"; }

file_path="${NGINX_LOG_FILE:-/var/log/nginx/access.log}"
webhook_url="${WEBHOOK_URL:-${WECHAT_WEBHOOK_URL:-}}"
cache_file="${NALI_CACHE_FILE:-/tmp/nali_cache.txt}"
push_enabled=true

show_help() {
    cat <<EOF
Nginx 高频 DNS 访问 IP 分析脚本

用法: $0 [选项]

选项:
  --log-file FILE       Nginx access.log 路径
  --cache-file FILE     IP 归属地缓存路径
  --webhook-url URL     企业微信机器人 Webhook
  --no-push             仅输出本地报告，不推送
  -h, --help            显示帮助信息

也可通过 NGINX_LOG_FILE、NALI_CACHE_FILE、WEBHOOK_URL 环境变量配置。
EOF
}

require_value() {
    local option="$1"
    local value="${2:-}"
    if [[ -z "$value" ]]; then
        log_error "参数 $option 缺少值"
        exit 2
    fi
}

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

append_cache() {
    local ip_address="$1"
    local location="$2"

    if command -v flock >/dev/null 2>&1; then
        {
            flock -x 9
            printf '%s\t%s\n' "$ip_address" "$location" >&9
        } 9>> "$cache_file"
    else
        printf '%s\t%s\n' "$ip_address" "$location" >> "$cache_file"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --log-file)
            require_value "$1" "${2:-}"
            file_path="$2"
            shift 2
            ;;
        --cache-file)
            require_value "$1" "${2:-}"
            cache_file="$2"
            shift 2
            ;;
        --webhook-url)
            require_value "$1" "${2:-}"
            webhook_url="$2"
            shift 2
            ;;
        --no-push)
            push_enabled=false
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "未知参数: $1"
            show_help
            exit 2
            ;;
    esac
done

if [[ -z "$webhook_url" || "$webhook_url" == *"你的"* ]]; then
    webhook_url=""
fi

if [[ "$push_enabled" == true && -n "$webhook_url" && ! "$webhook_url" =~ ^https://[^[:space:][:cntrl:]]+$ ]]; then
    log_error "Webhook URL 格式无效，必须使用 https:// 且不能包含空白或控制字符。"
    exit 2
fi

if [[ "$push_enabled" == true && -n "$webhook_url" ]] && ! command -v curl >/dev/null 2>&1; then
    log_error "执行推送需要 curl 命令。"
    exit 1
fi

if [[ ! -r "$file_path" ]]; then
    log_error "📄 日志文件不存在或不可读：$file_path"
    exit 1
fi

umask 077
mkdir -p "$(dirname "$cache_file")"
if [[ -L "$cache_file" ]]; then
    log_error "缓存文件不能是符号链接：$cache_file"
    exit 1
fi
touch "$cache_file"

log_info "📊🔍 提取包含 'dns' 的 IP 并统计频率..."

ip_list=$(awk '
    function valid_ipv4(ip, octets, count, i) {
        count = split(ip, octets, ".")
        if (count != 4 || ip == "0.0.0.0") return 0
        for (i = 1; i <= 4; i++) {
            if (octets[i] !~ /^[0-9]+$/ || octets[i] < 0 || octets[i] > 255) return 0
        }
        return 1
    }
    index($0, "dns") {
        for (i = 1; i <= NF; i++) {
            candidate = $i
            gsub(/^[^0-9]+|[^0-9.]+$/, "", candidate)
            if (valid_ipv4(candidate)) {
                ips[candidate]++
                break
            }
        }
    }
    END {
        for (ip in ips) print ip, ips[ip]
    }
' "$file_path")

if [[ -z "$ip_list" ]]; then
    log_warn "🫥 没有找到包含 'dns' 的 IP 记录。"
    exit 0
fi

sorted_ips=$(printf '%s\n' "$ip_list" | sort -k2,2nr -k1,1)
readarray -t ip_array <<< "$sorted_ips"

log_info "📋🚀 以下为 DNS 查询频次较高的 IP："
message="📊 高频 DNS 查询 IP 报告"$'\n'"🕒 时间：$(date '+%F %T')"

for ip in "${ip_array[@]}"; do
    read -r ip_address count _ <<< "$ip"

    log_info "🔎 正在查询 IP：$ip_address"

    location=$(awk -v ip="$ip_address" '$1 == ip { $1=""; sub(/^[[:space:]]+/, ""); print; exit }' "$cache_file" || true)
    if [[ -z "$location" ]]; then
        if command -v nali >/dev/null 2>&1; then
            if command -v timeout >/dev/null 2>&1; then
                location=$(timeout 10s nali "$ip_address" 2>/dev/null || true)
            else
                location=$(nali "$ip_address" 2>/dev/null || true)
            fi
            if [[ "$location" =~ \[([^][]+)\] ]]; then
                location="${BASH_REMATCH[1]}"
            fi
        fi

        [[ -z "$location" ]] && location="未知"
        location=${location//$'\n'/ }
        location=${location//$'\t'/ }
        append_cache "$ip_address" "$location"
    fi

    log_ok "📍 IP: $ip_address 频次: $count 位置: $location"
    message+=$'\n'"📌 ${ip_address}（$location） - $count 次"
done

if [[ "$push_enabled" == false ]]; then
    log_warn "📣 已选择仅输出本地报告，未执行推送。"
    exit 0
fi

if [[ -z "$webhook_url" ]]; then
    log_error "📣 未配置 webhook，无法推送。请设置 WEBHOOK_URL，或使用 --no-push 仅输出本地报告。"
    exit 1
fi

log_info "📤🚀 推送报告到企业微信..."
safe_message=$(json_escape "$message")
json="{\"msgtype\":\"text\",\"text\":{\"content\":\"$safe_message\"}}"
response=""

if response=$(curl --fail-with-body --silent --show-error --proto '=https' --proto-redir '=https' --connect-timeout 5 --max-time 15 -X POST "$webhook_url" \
    -H 'Content-Type: application/json' -d "$json") && \
    [[ "$response" =~ \"errcode\"[[:space:]]*:[[:space:]]*0 ]]; then
    log_ok "🎉 推送成功！"
else
    log_error "🔥 推送失败，请检查 webhook！${response:+ 服务端响应: $response}"
    exit 1
fi
