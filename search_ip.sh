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
# Version: 2025-07-16
# ====================================================

set -euo pipefail

# ===== 🎨 色彩输出 =====
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

log_info() { echo -e "${BLUE}ℹ️  $1${RESET}"; }
log_ok() { echo -e "${GREEN}✅ $1${RESET}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${RESET}"; }
log_error() { echo -e "${RED}❌ $1${RESET}"; }

file_path="/var/log/nginx/access.log"
webhook_url="${WEBHOOK_URL:-${WECHAT_WEBHOOK_URL:-}}"
cache_file="/tmp/nali_cache.txt"

if [[ -z "$webhook_url" || "$webhook_url" == *"你的KEY"* ]]; then
    webhook_url=""
fi

if [[ ! -f "$file_path" ]]; then
    log_error "📄 日志文件不存在：$file_path"
    exit 1
fi

mkdir -p "$(dirname "$cache_file")"
touch "$cache_file"

log_info "📊🔍 提取包含 'dns' 的 IP 并统计频率..."

ip_list=$(grep -E "dns" "$file_path" | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | awk '!/0\.0\.0/ { ips[$0]++ } END { for (ip in ips) print ip, ips[ip] }' || true)

if [[ -z "$ip_list" ]]; then
    log_warn "🫥 没有找到包含 'dns' 的 IP 记录。"
    exit 0
fi

sorted_ips=$(echo "$ip_list" | sort -k2 -nr)
readarray -t ip_array <<< "$sorted_ips"

log_info "📋🚀 以下为 DNS 查询频次较高的 IP："
message="📊 *高频 DNS 查询 IP 报告*\n🕒 时间：$(date '+%F %T')"

for ip in "${ip_array[@]}"; do
    ip_address=$(echo "$ip" | awk '{print $1}')
    count=$(echo "$ip" | awk '{print $2}')

    log_info "🔎 正在查询 IP：$ip_address"

    location=$(awk -F '\t' -v ip="$ip_address" '$1 == ip { $1=""; sub(/^\t/, ""); print; exit }' "$cache_file" || true)
    if [[ -z "$location" ]]; then
        if command -v nali >/dev/null 2>&1; then
            location=$(nali "$ip_address" 2>/dev/null || true)
            if [[ -n "$location" ]]; then
                location=$(echo "$location" | sed -E 's/^.*\[(.*)\].*$/\1/')
            fi
        fi

        [[ -z "$location" ]] && location="未知"
        printf '%s\t%s\n' "$ip_address" "$location" >> "$cache_file"
    fi

    log_ok "📍 IP: $ip_address 频次: $count 位置: $location"
    message+="\n📌 ${ip_address}（$location） - $count 次"
done

if [[ -z "$webhook_url" ]]; then
    log_warn "📣 未配置 webhook，已输出本地报告，未执行推送。"
    exit 0
fi

log_info "📤🚀 推送报告到企业微信..."
safe_message=$(echo "$message" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
json="{\"msgtype\":\"text\",\"text\":{\"content\":\"【DNS 查询高频 IP 报告】\\n$safe_message\"}}"

if curl -fsS -X POST "$webhook_url" -H 'Content-Type: application/json' -d "$json" >/dev/null; then
    log_ok "🎉 推送成功！"
else
    log_error "🔥 推送失败，请检查 webhook！"
    exit 1
fi
