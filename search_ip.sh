#!/bin/bash

# Colors for output
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
RED="\e[1;31m"
BLUE="\e[1;34m"
RESET="\e[0m"

# 指定文件路径
file_path="/var/log/nginx/access.log"

# 提取包含 "dns" 的行，并提取出所有 IP 地址
echo -e "${BLUE}提取包含'dns'的IP地址并统计频率...${RESET}"

ip_list=$(grep -E "dns" "$file_path" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | awk '!/0\.0\.0/ { ips[$0]++ } END { for (ip in ips) print ip, ips[ip] }')

# 按次数降序排序
sorted_ips=$(echo "$ip_list" | sort -k2 -nr)

# 将排序后的IP地址存储到数组中
readarray -t ip_array <<< "$sorted_ips"

# 输出信息
echo -e "${GREEN}以下查询DNS的IP地址频次由高到低，并附带地理位置信息：${RESET}"

# 遍历排序后的IP地址列表
for ip in "${ip_array[@]}"; do
  # 提取IP地址和出现次数
  ip_address=$(echo "$ip" | awk '{print $1}')
  count=$(echo "$ip" | awk '{print $2}')
  
  # 使用nali命令查询IP地址的地理位置
  location=$(nali "$ip_address")
  
  # 格式化输出
  echo -e "${YELLOW}IP:${RESET} $ip_address ${GREEN}频次:${RESET} $count ${BLUE}位置:${RESET} $location"
done
