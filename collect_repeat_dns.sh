#!/bin/bash

# ==== 设置颜色和格式 ====
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"
INFO="${CYAN}✨ ℹ️ ${RESET}"
SUCCESS="${GREEN}🎉 ✅ ${RESET}"
WARN="${YELLOW}⚠️ ️⚡ ${RESET}"
ERROR="${RED}❌ 💥 ${RESET}"
PROMPT="${MAGENTA}👉 🌟 ${RESET}"

# ==== 配置 ====
domain_file="/etc/mosdns/mosdns.log"
output_file="/etc/mosdns/rules/repeat_domain.txt"
threshold=500   # 修改阈值为500

# 企业微信 Webhook 地址，替换为你自己的
wechat_webhook_url="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=你的KEY"

# ==== 发送企业微信消息函数 ====
send_wechat_message() {
    local message="$1"
    local title="【重复域名监控结果】"
    # JSON 转义处理（换行转 \n，双引号转义）
    local safe_message
    safe_message=$(echo "$message" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
    local json="{\"msgtype\":\"text\",\"text\":{\"content\":\"$title\\n\\n$safe_message\"}}"
    curl -s -X POST "$wechat_webhook_url" -H 'Content-Type: application/json' -d "$json" >/dev/null || echo -e "${ERROR} 企业微信推送失败${RESET}"
}

echo -e "${INFO}开始从日志文件中萌萌哒提取域名啦~"

grep -oE '"qname": "([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})' "$domain_file" | sed 's/"qname": "//' | grep -v "in-addr.arpa" | sort | uniq -c | sort -rn > temp.txt

echo -e "${INFO}正在努力生成重复域名列表，小心查收哦~"

echo "# 重复域名列表：" > "$output_file"
duplicate_domains=0
message_body="🌈 重复域名列表（出现次数 > $threshold）：\n"

while read -r line; do
  count=$(echo "$line" | awk '{print $1}')
  domain=$(echo "$line" | awk '{print $2}')
  
  if (( count > threshold )); then
    echo "full:$domain" >> "$output_file"
    duplicate_domains=1
    message_body+="🐾 $domain 出现次数：$count\n"
  fi
done < temp.txt

rm temp.txt

if (( duplicate_domains == 1 )); then
  echo -e "${SUCCESS}查找完毕！重复域名已保存到 ${output_file} 文件中哦~"
  cat /dev/null > "$domain_file"
  # 发送微信消息
  send_wechat_message "$message_body"
else
  echo -e "${INFO}没有发现重复域名，大家都很乖，没有超过阈值哦~"
  cat /dev/null > "$output_file"
  send_wechat_message "🌟 查询完毕，未发现重复域名，阈值是 $threshold 哦~"
fi


