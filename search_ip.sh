#!/bin/bash

# ========== 配置 ==========
file_path="/var/log/nginx/access.log"
###########################################################################
webhook_url="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=你的KEY"#
###########################################################################
cache_file="/tmp/nali_cache.txt"  # 缓存文件

# ========== 检查文件 ==========
if [[ ! -f "$file_path" ]]; then
    echo "❌ 日志文件不存在：$file_path"
    exit 1
fi

# ========== 提取并统计 IP ==========
echo "📊 提取包含 'dns' 的 IP 并统计频率..."

ip_list=$(grep -E "dns" "$file_path" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | awk '!/0\.0\.0/ { ips[$0]++ } END { for (ip in ips) print ip, ips[ip] }')

if [[ -z "$ip_list" ]]; then
    echo "⚠️ 没有找到包含 'dns' 的 IP 记录。"
    exit 0
fi

sorted_ips=$(echo "$ip_list" | sort -k2 -nr)
readarray -t ip_array <<< "$sorted_ips"

# ========== 构建消息 ==========
echo "📋 以下为 DNS 查询频次较高的 IP："
message="📊 *高频 DNS 查询 IP 报告*\n🕒 时间：$(date '+%F %T')"

for ip in "${ip_array[@]}"; do
    ip_address=$(echo "$ip" | awk '{print $1}')
    count=$(echo "$ip" | awk '{print $2}')
    
    echo "正在查询 IP：$ip_address"

    # 缓存查询的地理位置信息
    location=$(grep -w "$ip_address" "$cache_file" | awk '{print $2}')
    if [[ -z "$location" ]]; then
        # 调试输出 nali 查询结果
        echo "查询 IP 地址的地理信息：$ip_address"
        location=$(nali "$ip_address" 2>/dev/null)

        # 输出 nali 原始返回值，用于调试
        echo "nali 输出：$location"

        if [[ -z "$location" ]]; then
            location="未知"
        else
            # 提取括号内的地理位置（移除 IP 地址）
            location=$(echo "$location" | sed -E 's/.*\[(.*)\].*/\1/')
            echo "提取后的地理位置：$location"
        fi

        echo "$ip_address $location" >> "$cache_file"
    fi

    echo "IP: $ip_address 频次: $count 位置: $location"
    message+="\n📌 ${ip_address}（$location） - $count 次"
done

# ========== 推送企业微信 ==========
echo "📤 推送报告到企业微信..."
safe_message=$(echo "$message" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
json="{\"msgtype\":\"text\",\"text\":{\"content\":\"【DNS 查询高频 IP 报告】\\n$safe_message\"}}"

curl -s -X POST "$webhook_url" \
    -H 'Content-Type: application/json' \
    -d "$json" >/dev/null

if [[ $? -eq 0 ]]; then
    echo "✅ 推送成功！"
else
    echo "❌ 推送失败，请检查 webhook！"
fi
