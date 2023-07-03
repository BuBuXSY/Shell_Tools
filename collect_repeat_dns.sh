#!/bin/bash

# 读取包含域名的文本文件，每行一个域名
domain_file="/etc/mosdns/mosdns.log"

# 输出文件，保存查询结果
output_file="/etc/mosdns/rules/repeat_domain.txt"

# 设置重复次数的阈值
threshold=2000

# 使用grep和正则表达式获取 "qname" 之后的域名
# 排除数字、日期和标点符号，只查询域名网址
# 使用sort和uniq -c对结果进行统计和排序
# 结果保存到临时文件temp.txt
grep -oE '"qname": "([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})' "$domain_file" | sed 's/"qname": "//' | grep -v "in-addr.arpa" | sort | uniq -c | sort -rn > temp.txt

# 从临时文件中读取结果，并生成域名列表
# 同时将重复次数超过阈值的域名保存到输出文件
echo "#重复域名列表：" > "$output_file"
duplicate_domains=0
while read -r line; do
  count=$(echo "$line" | awk '{print $1}')
  domain=$(echo "$line" | awk '{print $2}')
  if (( count > threshold )); then
    echo "full:$domain" >> "$output_file"
    duplicate_domains=1
  fi
done < temp.txt

# 删除临时文件
rm temp.txt

# 检查是否存在重复域名超过阈值的情况，给出相应的提示
if ((duplicate_domains == 1)); then
  echo "查询完成，请查看 $output_file 文件。"
  # 清空日志文件
  cat /dev/null > "$domain_file"
else
  echo "发现的重复域名数量少于阈值。"
  rm "$output_file"  # 删除输出文件
fi
