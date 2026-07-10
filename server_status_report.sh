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

WEBHOOK_URL="${WEBHOOK_URL:-${WECHAT_WEBHOOK_URL:-}}"
CACHE_FILE="${SERVER_STATUS_CACHE_FILE:-/tmp/server_net_stat.cache}"
LOG_FILE="${SERVER_STATUS_LOG_FILE:-/tmp/server_net_stat.log}"
IP_INFO_URL="${IP_INFO_URL:-https://myip.ipip.net}"
CACHE_TIMEOUT="${CACHE_TIMEOUT:-3600}"
DRY_RUN=false

show_help() {
  cat <<EOF
服务器状态企业微信推送脚本

用法: $0 [选项]

选项:
  --webhook-url URL      企业微信机器人 Webhook
  --cache-file FILE      网络流量缓存文件
  --log-file FILE        运行日志文件
  --cache-timeout SEC    流量缓存有效期（默认: 3600 秒）
  --dry-run              仅在终端显示报告，不推送
  -h, --help             显示帮助信息

也可通过 WEBHOOK_URL、SERVER_STATUS_CACHE_FILE、SERVER_STATUS_LOG_FILE 环境变量配置。
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

read_counter() {
  local file="$1"
  local value=0
  if [[ -r "$file" ]]; then
    read -r value < "$file" || value=0
  fi
  [[ "$value" =~ ^[0-9]+$ ]] || value=0
  printf '%s\n' "$value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --webhook-url)
      require_value "$1" "${2:-}"
      WEBHOOK_URL="$2"
      shift 2
      ;;
    --cache-file)
      require_value "$1" "${2:-}"
      CACHE_FILE="$2"
      shift 2
      ;;
    --log-file)
      require_value "$1" "${2:-}"
      LOG_FILE="$2"
      shift 2
      ;;
    --cache-timeout)
      require_value "$1" "${2:-}"
      CACHE_TIMEOUT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
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

if [[ ! "$CACHE_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  log_error "缓存有效期必须是正整数秒数: $CACHE_TIMEOUT"
  exit 2
fi
CACHE_TIMEOUT=$((10#$CACHE_TIMEOUT))

if [[ "$DRY_RUN" == false && -n "$WEBHOOK_URL" && "$WEBHOOK_URL" != *"你的"* && ! "$WEBHOOK_URL" =~ ^https?:// ]]; then
  log_error "Webhook URL 格式无效，必须以 http:// 或 https:// 开头。"
  exit 2
fi

umask 077
if [[ "$DRY_RUN" == false ]]; then
  mkdir -p "$(dirname "$CACHE_FILE")" "$(dirname "$LOG_FILE")"
  if [[ -L "$CACHE_FILE" || -L "$LOG_FILE" ]]; then
    log_error "缓存文件和日志文件不能是符号链接。"
    exit 1
  fi
fi

log() {
  [[ "$DRY_RUN" == true ]] && return 0
  printf '[%s] %s\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$1" >> "$LOG_FILE" 2>/dev/null || true
}

if [[ "$DRY_RUN" == false && ( -z "$WEBHOOK_URL" || "$WEBHOOK_URL" == *"你的"* ) ]]; then
  log "Webhook is not configured. Set WEBHOOK_URL or WECHAT_WEBHOOK_URL."
  log_error "📣 未配置 webhook，无法推送。请设置 WEBHOOK_URL，或使用 --dry-run 仅预览。"
  exit 1
fi

if [[ "$DRY_RUN" == false ]] && ! command -v curl >/dev/null 2>&1; then
  log_error "执行推送需要 curl 命令。"
  exit 1
fi

required_commands=(awk date df dirname free mktemp ps sed uptime)
for command_name in "${required_commands[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    log_error "缺少必要命令: $command_name"
    exit 1
  fi
done

CURRENT_TIME=$(date +"%Y-%m-%d %H:%M:%S")
IP_INFO_RAW=""
if command -v curl >/dev/null 2>&1; then
  IP_INFO_RAW=$(curl -fsS --connect-timeout 3 --max-time 8 "$IP_INFO_URL" 2>/dev/null || true)
fi
PUBLIC_IP=$(sed -n 's/.*IP：\([^ ]*\).*/\1/p' <<< "$IP_INFO_RAW")
LOCATION=$(sed -n 's/.*来自于：\(.*\)$/\1/p' <<< "$IP_INFO_RAW")

[[ -z "$PUBLIC_IP" ]] && PUBLIC_IP="未知"
[[ -z "$LOCATION" ]] && LOCATION="未知"

NET_INTERFACE=""
if command -v ip >/dev/null 2>&1; then
  NET_INTERFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}' || true)
fi
if [[ -z "$NET_INTERFACE" || ! -d "/sys/class/net/$NET_INTERFACE" ]]; then
  for interface_path in /sys/class/net/*; do
    [[ -e "$interface_path" ]] || continue
    candidate_interface=${interface_path##*/}
    if [[ "$candidate_interface" != "lo" ]]; then
      NET_INTERFACE="$candidate_interface"
      break
    fi
  done
fi
[[ -z "$NET_INTERFACE" ]] && NET_INTERFACE="未知"

RX_NOW=$(read_counter "/sys/class/net/${NET_INTERFACE}/statistics/rx_bytes")
TX_NOW=$(read_counter "/sys/class/net/${NET_INTERFACE}/statistics/tx_bytes")
NOW_EPOCH=$(date +%s)

LAST_EPOCH=$NOW_EPOCH
LAST_RX=$RX_NOW
LAST_TX=$TX_NOW
LAST_INTERFACE="$NET_INTERFACE"
if [[ -f "$CACHE_FILE" ]]; then
  read -r cached_epoch cached_rx cached_tx cached_interface < "$CACHE_FILE" || true
  if [[ "${cached_epoch:-}" =~ ^[0-9]+$ && "${cached_rx:-}" =~ ^[0-9]+$ && "${cached_tx:-}" =~ ^[0-9]+$ ]]; then
    LAST_EPOCH=$((10#$cached_epoch))
    LAST_RX=$((10#$cached_rx))
    LAST_TX=$((10#$cached_tx))
    LAST_INTERFACE="${cached_interface:-$NET_INTERFACE}"
  else
    log "Invalid cache data ignored: $CACHE_FILE"
  fi
fi

TIME_DIFF=$((NOW_EPOCH - LAST_EPOCH))
if [[ "$LAST_INTERFACE" != "$NET_INTERFACE" || "$TIME_DIFF" -gt "$CACHE_TIMEOUT" ]]; then
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

if [[ "$DRY_RUN" == false ]]; then
  cache_tmp=$(mktemp "${CACHE_FILE}.tmp.XXXXXX")
  trap 'rm -f -- "$cache_tmp"' EXIT
  printf '%s %s %s %s\n' "$NOW_EPOCH" "$RX_NOW" "$TX_NOW" "$NET_INTERFACE" > "$cache_tmp"
  chmod 0600 "$cache_tmp"
  mv -f -- "$cache_tmp" "$CACHE_FILE"
fi

if [[ -r /proc/loadavg ]]; then
  read -r CPU1 CPU5 CPU15 _ < /proc/loadavg
else
  read -r CPU1 CPU5 CPU15 <<< "$(uptime | awk -F 'load average:|load averages:' '{gsub(/,/, "", $2); print $2}')"
fi

if ! read -r MEM_TOTAL MEM_USED MEM_BUFF_CACHE MEM_AVAILABLE < <(free -m | awk '/^Mem:/ {print $2, $3, $6, $7}'); then
  log_error "无法读取内存统计。"
  exit 1
fi
if [[ "$MEM_TOTAL" =~ ^[1-9][0-9]*$ && "$MEM_USED" =~ ^[0-9]+$ ]]; then
  MEM_USAGE=$(( MEM_USED * 100 / MEM_TOTAL ))
else
  log_error "无法解析内存统计。"
  exit 1
fi

DISK_INFO=$(df -h --output=target,pcent | awk 'NR > 1 {printf "%s%s %s", separator, $1, $2; separator=", "}')

TOP_PROC=$(ps -eo pid=,pcpu=,comm= --sort=-pcpu | \
  awk 'NR <= 3 {printf "PID:%s CPU:%.1f%% CMD:%s%s", $1, $2, $3, (NR < 3 ? "\n" : "")}')

UPTIME=$(uptime -p)

REPORT_CONTENT=$(cat <<EOF
🖥️ 服务器状态报告
时间: $CURRENT_TIME

📍 服务器地理位置: $LOCATION (公网IP: $PUBLIC_IP)

💡 CPU 负载 (1m/5m/15m): $CPU1 / $CPU5 / $CPU15

🧠 内存 (已用/总量/缓存/可用): ${MEM_USED}MB / ${MEM_TOTAL}MB / ${MEM_BUFF_CACHE}MB / ${MEM_AVAILABLE}MB
内存使用率: ${MEM_USAGE}%

💽 磁盘使用:
$DISK_INFO

🌐 网络流量 (${NET_INTERFACE} 接口):
⬇️ 下载速率: ${RX_RATE} KB/s
⬆️ 上传速率: ${TX_RATE} KB/s

🔥 Top 3 CPU 占用进程:
$TOP_PROC

⏳ 系统运行时间: $UPTIME
EOF
)

if [[ "$DRY_RUN" == true ]]; then
  log_info "📋 服务器状态报告预览："
  printf '%s\n' "$REPORT_CONTENT"
  exit 0
fi

SAFE_CONTENT=$(json_escape "$REPORT_CONTENT")
PAYLOAD="{\"msgtype\":\"text\",\"text\":{\"content\":\"$SAFE_CONTENT\"}}"
RESPONSE=""

if RESPONSE=$(curl -fsS --connect-timeout 5 --max-time 15 -X POST \
  -H "Content-Type: application/json" -d "$PAYLOAD" "$WEBHOOK_URL") && \
  [[ "$RESPONSE" =~ \"errcode\"[[:space:]]*:[[:space:]]*0 ]]; then
  log "Status report sent successfully."
  log_ok "📡 状态报告发送成功。"
else
  log "Failed to send status report. Response: $RESPONSE"
  log_error "📡 状态报告发送失败。${RESPONSE:+ 服务端响应: $RESPONSE}"
  exit 1
fi
