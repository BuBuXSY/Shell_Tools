#!/bin/bash

# 指定文件路径
file_path="/var/log/nginx/access.log"

# 使用grep命令查找包含"dns"的行，并提取其中的IP地址
ip_list=$(grep -E "dns" "$file_path" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")

# 使用awk命令统计每个IP出现的次数（排除特定的IP），并按次数降序排序
sorted_ips=$(echo "$ip_list" | awk '!/0\.0\.0/' | awk '{ ips[$0]++ } END { for (ip in ips) print ip, ips[ip] }' | sort -k2 -nr)

# 将排序后的IP地址存储到数组中
readarray -t ip_array <<< "$sorted_ips"

# 遍历排序后的IP地址列表
echo "以下查询DNS的IP地址频次由高到低，并附带地理位置信息："
for ip in "${ip_array[@]}"; do
  # 提取IP地址和出现次数
  ip_address=$(echo "$ip" | awk '{print $1}')
  count=$(echo "$ip" | awk '{print $2}')
  
  # 使用nali命令查询IP地址的地理位置
  location=$(nali "$ip_address")
  
  # 输出地理位置信息和出现次数
  echo "$location $count"
done
