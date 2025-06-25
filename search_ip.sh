#!/bin/bash

# ========== 色彩定义 ==========
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
RED="\e[1;31m"
BLUE="\e[1;34m"
RESET="\e[0m"

# ========== 配置 ==========
file_path="/var/log/nginx/access.log"
webhook_url="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=你的KEY"

# ========== 检查文件 ==========
if [[ ! -f "$file_path" ]]; then
    echo -e "${RED}❌ 日志文件不存在：$file_path${RESET}"
    exit 1
fi

# ========== 提取并统计 IP ==========
echo -e "${BLUE}📊 提取包含 'dns' 的 IP 并统计频率...${RESET}"

ip_list=$(grep -E "dns" "$file_path" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | awk '!/0\.0\.0/ { ips[$0]++ } END { for (ip in ips) print ip, ips[ip] }')

if [[ -z "$ip_list" ]]; then
    echo -e "${YELLOW}⚠️ 没有找到包含 'dns' 的 IP 记录。${RESET}"
    exit 0
fi

sorted_ips=$(echo "$ip_list" | sort -k2 -nr)
readarray -t ip_array <<< "$sorted_ips"

# ========== 构建消息 ==========
echo -e "${GREEN}📋 以下为 DNS 查询频次较高的 IP：${RESET}"
message="📊 *高频 DNS 查询 IP 报告*\n🕒 时间：$(date '+%F %T')"

for ip in "${ip_array[@]}"; do
    ip_address=$(echo "$ip" | awk '{print $1}')
    count=$(echo "$ip" | awk '{print $2}')
    location=$(nali "$ip_address" 2>/dev/null)
    [[ -z "$location" ]] && location="未知"

    echo -e "${YELLOW}IP:${RESET} $ip_address ${GREEN}频次:${RESET} $count ${BLUE}位置:${RESET} $location"
    message+="\n📌 ${ip_address}（$location） - $count 次"
done

# ========== 推送企业微信 ==========
echo -e "${CYAN}📤 推送报告到企业微信...${RESET}"
safe_message=$(echo "$message" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
json="{\"msgtype\":\"text\",\"text\":{\"content\":\"$safe_message\"}}"

curl -s -X POST "$webhook_url" \
    -H 'Content-Type: application/json' \
    -d "$json" >/dev/null

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ 推送成功！${RESET}"
else
    echo -e "${RED}❌ 推送失败，请检查 webhook！${RESET}"
fi
