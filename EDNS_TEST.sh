#!/bin/bash

# 颜色和样式设置
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
BLUE="\e[34m"
RESET="\e[0m"
BOLD="\e[1m"
MAGENTA="\e[35m"
CYAN="\e[36m"
INFO="${CYAN}󰋼${RESET}"          # Nerd Font: info
SUCCESS="${GREEN}󰒸${RESET}"     # Nerd Font: check-circle
ERROR="${RED}󰛴${RESET}"        # Nerd Font: cross-circle
WARNING="${YELLOW}󰜀${RESET}"   # Nerd Font: warning
NOTE="${MAGENTA}󰏸${RESET}"     # Nerd Font: note

# 自动判断系统类型并安装 nali 和 q
install_tools() {
    # 判断系统类型
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo -e "${INFO} 检测到 Linux 系统，准备安装工具..."

        # 检查 nali 是否已安装
        if ! command -v nali &> /dev/null; then
            echo -e "${ERROR} nali 未安装，正在安装..."
            if [[ -f "/etc/debian_version" ]]; then
                # Debian/Ubuntu 系统
                sudo apt-get update
                sudo apt-get install -y nali
            elif [[ -f "/etc/redhat-release" ]]; then
                # CentOS/Fedora 系统
                sudo yum install -y nali
            else
                echo -e "${ERROR} 无法自动安装 nali，系统未知。"
            fi
        else
            echo -e "${SUCCESS} nali 已安装。"
        fi

        # 检查 q 是否已安装
        if ! command -v q &> /dev/null; then
            echo -e "${ERROR} q 未安装，正在安装..."
            if [[ -f "/etc/debian_version" ]]; then
                # Debian/Ubuntu 系统
                sudo apt-get install -y q
            elif [[ -f "/etc/redhat-release" ]]; then
                # CentOS/Fedora 系统
                sudo yum install -y q
            else
                echo -e "${ERROR} 无法自动安装 q，系统未知。"
            fi
        else
            echo -e "${SUCCESS} q 已安装。"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "${INFO} 检测到 macOS 系统，准备安装工具..."

        # 检查 nali 是否已安装
        if ! command -v nali &> /dev/null; then
            echo -e "${ERROR} nali 未安装，正在安装..."
            brew install nali
        else
            echo -e "${SUCCESS} nali 已安装。"
        fi

        # 检查 q 是否已安装
        if ! command -v q &> /dev/null; then
            echo -e "${ERROR} q 未安装，正在安装..."
            brew install q
        else
            echo -e "${SUCCESS} q 已安装。"
        fi
    else
        echo -e "${ERROR} ❌ 未支持的操作系统类型，无法自动安装工具。"
    fi
}

# 获取用户输入的 DNS 地址
read -p "$(echo -e "${INFO} 请输入你想测试的DNS服务器（例如：8.8.8.8 或 https://dns.google/dns-query）: ")" dns_server

# 安装工具
install_tools

# 执行 DNS 测试，检查解析能力
echo -e "${INFO} 正在测试 DNS 服务器 ${dns_server} 对以下域名的解析能力..."

# 测试一组常见的域名
domains=("www.google.com" "www.youtube.com" "www.baidu.com" "www.tencent.com" "www.amazon.com" "www.apple.com" "www.microsoft.com" "www.wikipedia.org" "www.github.com" "www.reddit.com")

for domain in "${domains[@]}"; do
    echo -e "${INFO} 正在测试域名 ${domain} 的解析能力..."
    
    # 使用 q 测试 DNS 解析能力
    result=$(q "$domain" A @"$dns_server" --timeout 5s --format=raw)

    # 提取解析结果中的 IP 地址并使用 nali 查询地理位置
    ip_addresses=$(echo "$result" | grep -oP '\d+\.\d+\.\d+\.\d+')
    
    if [ -n "$ip_addresses" ]; then
        echo -e "${SUCCESS} 查询结果: $result"
        echo -e "${INFO} 正在查询 IP 地址的地理位置..."
        
        for ip in $ip_addresses; do
            # 跳过本地回环地址 127.0.0.1
            if [[ "$ip" == "127.0.0.1" ]]; then
                echo -e "${WARNING} IP 地址 $ip 是本机地址，跳过地理位置查询。"
                continue
            fi

            # 使用 nali 查询 IP 地址的地理位置
            ip_location=$(nali $ip)
            echo -e "${INFO} IP 地址 $ip 的地理位置: $ip_location"
        done
    else
        echo -e "${ERROR} DNS服务器 $dns_server 无法解析网站 $domain"
    fi
done

# 使用 q 检查是否支持 EDNS
echo -e "${INFO} 正在测试 DNS 服务器 ${dns_server} 是否支持 EDNS..."

# 使用 q 检查是否支持 EDNS
result=$(q -S $dns_server -t edns $dns_server)

# 判断是否支持 EDNS
if [[ "$result" == *"EDNS support"* ]]; then
    echo -e "${SUCCESS} DNS服务器 ${dns_server} 支持 EDNS"
else
    echo -e "${ERROR} DNS服务器 ${dns_server} 不支持 EDNS"
fi

echo -e "${NOTE} DNS测试完成。"
