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
# By: BuBuXSY
# Version: 2025-07-03


######################################################################################
WEBHOOK_URL="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=你的企业微信机器人KEY"
######################################################################################


CACHE_FILE="/tmp/server_net_stat.cache"
LOG_FILE="/tmp/server_net_stat.log"
CURRENT_TIME=$(date +"%Y-%m-%d %H:%M:%S")
CACHE_TIMEOUT=3600  # 缓存过期时间，单位：秒（1小时）

log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" >> "$LOG_FILE"
}

# 获取公网 IP 和地理信息
IP_INFO_RAW=$(curl -s http://myip.ipip.net)
CURL_STATUS=$?

if [[ "$CURL_STATUS" -ne 0 ]]; then
    log "Curl failed with status: $CURL_STATUS"
    IP_INFO_RAW="" # 确保为空，触发未知
fi

PUBLIC_IP=$(echo "$IP_INFO_RAW" | sed -n 's/.*IP：\([0-9\.]*\).*/\1/p')
LOCATION=$(echo "$IP_INFO_RAW" | sed -n 's/.*来自于：\(.*\)$/\1/p')

[[ -z "$PUBLIC_IP" ]] && PUBLIC_IP="未知"
[[ -z "$LOCATION" ]] && LOCATION="未知"

# 获取默认网卡接口（自动选择流量最大的网卡）
NET_INTERFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}')
[[ -z "$NET_INTERFACE" ]] && NET_INTERFACE="eth0"

# 网络流量统计
RX_NOW=$(cat /sys/class/net/${NET_INTERFACE}/statistics/rx_bytes 2>/dev/null || echo 0)
TX_NOW=$(cat /sys/class/net/${NET_INTERFACE}/statistics/tx_bytes 2>/dev/null || echo 0)
NOW_EPOCH=$(date +%s)

if [[ -f "$CACHE_FILE" ]]; then
  read LAST_EPOCH LAST_RX LAST_TX < "$CACHE_FILE"
else
  LAST_EPOCH=$NOW_EPOCH
  LAST_RX=$RX_NOW
  LAST_TX=$TX_NOW
fi

TIME_DIFF=$((NOW_EPOCH - LAST_EPOCH))
# 如果缓存超过设定的超时时间，强制更新
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

# CPU 负载
read CPU1 CPU5 CPU15 <<<$(uptime | awk -F 'load average:' '{print $2}' | tr -d ',')

# 内存状态
MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
MEM_BUFF_CACHE=$(free -m | awk '/Mem:/ {print $6}')
MEM_AVAILABLE=$(free -m | awk '/Mem:/ {print $7}')
MEM_USAGE=$(( MEM_USED * 100 / MEM_TOTAL ))

# 磁盘使用
DISK_INFO=$(df -h --output=target,pcent | tail -n +2 | awk '{print $1" "$2}' | paste -sd ", " -)

# Top3 CPU 占用进程
TOP_PROC=$(ps -eo pid,pcpu,comm --sort=-pcpu | head -n 4 | tail -n 3 | \
  awk '{printf "PID:%s CPU:%.1f%% CMD:%s\n", $1,$2,$3}')

# 系统运行时间
UPTIME=$(uptime -p)

# 构建消息 payload
read -r -d '' PAYLOAD <<EOF
{
  "msgtype": "text",
  "text": {
    "content": "🖥️ *服务器状态报告*\n时间: $CURRENT_TIME\n\n📍 服务器地理位置: $LOCATION (公网IP: $PUBLIC_IP)\n\n💡 *CPU 负载* (1m/5m/15m): $CPU1 / $CPU5 / $CPU15\n\n🧠 *内存* (已用/总量/缓存/可用): ${MEM_USED}MB / ${MEM_TOTAL}MB / ${MEM_BUFF_CACHE}MB / ${MEM_AVAILABLE}MB\n内存使用率: ${MEM_USAGE}%\n\n💽 *磁盘使用*:\n$DISK_INFO\n\n🌐 *网络流量* (${NET_INTERFACE} 接口):\n⬇️ 下载速率: ${RX_RATE} KB/s\n⬆️ 上传速率: ${TX_RATE} KB/s\n\n🔥 *Top 3 CPU 占用进程*:\n$TOP_PROC\n\n⏳ 系统运行时间: $UPTIME"
  }
}
EOF

# 推送消息
curl -s -X POST -H "Content-Type: application/json" -d "$PAYLOAD" "$WEBHOOK_URL" > /dev/null
if [[ $? -eq 0 ]]; then
  log "Status report sent successfully."
else
  log "Failed to send status report."
fi
