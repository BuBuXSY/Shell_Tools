#!/bin/bash

# 指定文件路径
file_path="/var/log/nginx/access.log"

# 使用grep命令查找包含"dns"的行，并提取其中的IP地址
ip_list=$(grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" "$file_path")

# 使用awk命令统计每个IP出现的次数，并按次数降序排序
sorted_ips=$(echo "$ip_list" | awk '{ ips[$0]++ } END { for (ip in ips) print ip, ips[ip] }' | sort -k2 -nr)

# 遍历排序后的IP地址列表
echo "以下查询DNS的IP地址频次由高到低，并附带地理位置信息（排除状态码为200的行）："
while IFS= read -r ip
do
  # 使用nali命令查询IP地址的地理位置
  location=$(nali "$ip")

  # 检查行中是否包含状态码为200
  if ! grep -q " dns-query " "$file_path" ; then
    echo "$location"
  fi
done <<< "$sorted_ips"