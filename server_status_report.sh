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
# 📊 服务器状态企业微信推送脚本
# 功能：采集 CPU、内存、磁盘、网络、进程和运行时间并推送企业微信
# By: BuBuXSY
# Version: 2025-07-03
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

WEBHOOK_URL="${WEBHOOK_URL:-${WECHAT_WEBHOOK_URL:-}}"
CACHE_FILE="/tmp/server_net_stat.cache"
LOG_FILE="/tmp/server_net_stat.log"
CURRENT_TIME=$(date +"%Y-%m-%d %H:%M:%S")
CACHE_TIMEOUT=3600

log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" >> "$LOG_FILE"
}

if [[ -z "$WEBHOOK_URL" || "$WEBHOOK_URL" == *"你的"* ]]; then
  log "Webhook is not configured. Set WEBHOOK_URL or WECHAT_WEBHOOK_URL."
  log_warn "📣 未配置 webhook，已取消推送。请设置 WEBHOOK_URL 或 WECHAT_WEBHOOK_URL。"
  exit 0
fi

IP_INFO_RAW=$(curl -fsS http://myip.ipip.net 2>/dev/null || true)
PUBLIC_IP=$(echo "$IP_INFO_RAW" | sed -n 's/.*IP：\([0-9\.]*\).*/\1/p')
LOCATION=$(echo "$IP_INFO_RAW" | sed -n 's/.*来自于：\(.*\)$/\1/p')

[[ -z "$PUBLIC_IP" ]] && PUBLIC_IP="未知"
[[ -z "$LOCATION" ]] && LOCATION="未知"

NET_INTERFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}' || true)
[[ -z "$NET_INTERFACE" ]] && NET_INTERFACE="eth0"

RX_NOW=$(cat "/sys/class/net/${NET_INTERFACE}/statistics/rx_bytes" 2>/dev/null || echo 0)
TX_NOW=$(cat "/sys/class/net/${NET_INTERFACE}/statistics/tx_bytes" 2>/dev/null || echo 0)
NOW_EPOCH=$(date +%s)

if [[ -f "$CACHE_FILE" ]]; then
  read -r LAST_EPOCH LAST_RX LAST_TX < "$CACHE_FILE" || true
  LAST_EPOCH="${LAST_EPOCH:-$NOW_EPOCH}"
  LAST_RX="${LAST_RX:-$RX_NOW}"
  LAST_TX="${LAST_TX:-$TX_NOW}"
else
  LAST_EPOCH=$NOW_EPOCH
  LAST_RX=$RX_NOW
  LAST_TX=$TX_NOW
fi

TIME_DIFF=$((NOW_EPOCH - LAST_EPOCH))
if [[ "$TIME_DIFF" -gt "$CACHE_TIMEOUT" ]]; then
  log "Cache expired, refreshing data..."
  RX_RATE=0
  TX_RATE=0
else
  (( TIME_DIFF <= 0 )) && TIME_DIFF=1
  RX_RATE=$(( (RX_NOW - LAST_RX) / TIME_DIFF / 1024 ))
  TX_RATE=$(( (TX_NOW - LAST_TX) / TIME_DIFF / 1024 ))
  (( RX_RATE < 0 )) && RX_RATE=0
  (( TX_RATE < 0 )) && TX_RATE=0
fi

echo "$NOW_EPOCH $RX_NOW $TX_NOW" > "$CACHE_FILE"

read -r CPU1 CPU5 CPU15 <<< "$(uptime | awk -F 'load average:' '{print $2}' | tr -d ',')"

MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
MEM_BUFF_CACHE=$(free -m | awk '/Mem:/ {print $6}')
MEM_AVAILABLE=$(free -m | awk '/Mem:/ {print $7}')
MEM_USAGE=$(( MEM_USED * 100 / MEM_TOTAL ))

DISK_INFO=$(df -h --output=target,pcent | tail -n +2 | awk '{print $1" "$2}' | paste -sd ", " -)

TOP_PROC=$(ps -eo pid,pcpu,comm --sort=-pcpu | head -n 4 | tail -n 3 | \
  awk '{printf "PID:%s CPU:%.1f%% CMD:%s\n", $1,$2,$3}')

UPTIME=$(uptime -p)

PAYLOAD=$(cat <<EOF
{
  "msgtype": "text",
  "text": {
    "content": "🖥️ *服务器状态报告*\n时间: $CURRENT_TIME\n\n📍 服务器地理位置: $LOCATION (公网IP: $PUBLIC_IP)\n\n💡 *CPU 负载* (1m/5m/15m): $CPU1 / $CPU5 / $CPU15\n\n🧠 *内存* (已用/总量/缓存/可用): ${MEM_USED}MB / ${MEM_TOTAL}MB / ${MEM_BUFF_CACHE}MB / ${MEM_AVAILABLE}MB\n内存使用率: ${MEM_USAGE}%\n\n💽 *磁盘使用*:\n$DISK_INFO\n\n🌐 *网络流量* (${NET_INTERFACE} 接口):\n⬇️ 下载速率: ${RX_RATE} KB/s\n⬆️ 上传速率: ${TX_RATE} KB/s\n\n🔥 *Top 3 CPU 占用进程*:\n$TOP_PROC\n\n⏳ 系统运行时间: $UPTIME"
  }
}
EOF
)

if curl -fsS -X POST -H "Content-Type: application/json" -d "$PAYLOAD" "$WEBHOOK_URL" > /dev/null; then
  log "Status report sent successfully."
  log_ok "📡 状态报告发送成功。"
else
  log "Failed to send status report."
  log_error "📡 状态报告发送失败。"
  exit 1
fi
