#!/usr/bin/env bash
# filename: robust-doh-test.sh
#  全面型 DoH 测试脚本
# 2025.07.18 
# By:BuBuXSY


# 配置变量
TEST_DOMAIN="www.google.com"
TIMEOUT=5
VERBOSE=false
OUTPUT_FORMAT="table"
DEBUG=false

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 精选的可靠 DoH 服务器
DOH_SERVERS=(
  # 国际主流，经过验证的稳定服务器
  "Cloudflare|https://1.1.1.1/dns-query|US|HTTP2,EDNS,DNSSEC,DoT|Cloudflare"
  "Cloudflare-Malware|https://1.1.1.2/dns-query|US|HTTP2,EDNS,DNSSEC,DoT,Malware-Block|Cloudflare"
  "Cloudflare-Family|https://1.1.1.3/dns-query|US|HTTP2,EDNS,DNSSEC,DoT,Family-Filter|Cloudflare"
  "Google|https://dns.google/dns-query|US|HTTP2,EDNS,DNSSEC,DoT|Google"
  "Google-Alt|https://8.8.8.8/dns-query|US|HTTP2,EDNS,DNSSEC,DoT|Google"
  "Quad9|https://dns.quad9.net/dns-query|CH|HTTP2,EDNS,DNSSEC,DoT,Malware-Block|Quad9"
  "Quad9-ECS|https://dns11.quad9.net/dns-query|CH|HTTP2,EDNS,DNSSEC,DoT,ECS|Quad9"
  "OpenDNS|https://doh.opendns.com/dns-query|US|HTTP2,EDNS,DNSSEC,DoT,Malware-Block|Cisco"
  "AdGuard|https://dns.adguard.com/dns-query|CY|HTTP2,EDNS,DNSSEC,DoT,Ad-Block|AdGuard"
  "AdGuard-Family|https://dns-family.adguard.com/dns-query|CY|HTTP2,EDNS,DNSSEC,DoT,Ad-Block,Family-Filter|AdGuard"
  
  # 国内 DNS 服务商
  "阿里DNS|https://dns.alidns.com/dns-query|CN|HTTP2,EDNS,DNSSEC,DoT|阿里云"
  "腾讯DNS|https://doh.pub/dns-query|CN|HTTP2,EDNS,DNSSEC|腾讯云"
  "360安全DNS|https://dns.pub/dns-query|CN|HTTP2,EDNS,DNSSEC,Ad-Block|360"
  "RubyFish|https://dns.rubyfish.cn/dns-query|CN|HTTP2,EDNS,DNSSEC|RubyFish"
  "233py|https://dns.233py.com/dns-query|CN|HTTP2,EDNS,DNSSEC|233py"
  
  # 专业和隐私 DNS
  "Mullvad|https://doh.mullvad.net/dns-query|SE|HTTP2,EDNS,DNSSEC,DoT,Privacy,No-Log|Mullvad"
  "LibreDNS|https://doh.libredns.gr/dns-query|DE|HTTP2,EDNS,DNSSEC,DoT,Ad-Block,Open-Source|LibreDNS"
  "CleanBrowsing|https://doh.cleanbrowsing.org/doh/security-filter|US|HTTP2,EDNS,DNSSEC,DoT,Malware-Block,Adult-Filter|CleanBrowsing"
  "NextDNS|https://dns.nextdns.io/dns-query|US|HTTP2,EDNS,DNSSEC,DoT,Custom-Filter|NextDNS"
  "Comodo|https://dns.comodo.com/dns-query|US|HTTP2,EDNS,DNSSEC,DoT,Malware-Block|Comodo"
  
  # 其他可靠服务器
  "PowerDNS|https://doh.powerdns.org/dns-query|NL|HTTP2,EDNS,DNSSEC,DoT,Open-Source|PowerDNS"
  "Digitale-Gesellschaft|https://dns.digitale-gesellschaft.ch/dns-query|CH|HTTP2,EDNS,DNSSEC,DoT,Privacy,No-Log|Digitale-Gesellschaft"
  "Quad101|https://dns.twnic.tw/dns-query|TW|HTTP2,EDNS,DNSSEC,DoT|TWNIC"
  "CZ.NIC|https://odvr.nic.cz/doh|CZ|HTTP2,EDNS,DNSSEC,DoT|CZ.NIC"
  "Yandex|https://dns.yandex.ru/dns-query|RU|HTTP2,EDNS,DNSSEC,DoT,Ad-Block|Yandex"
)

# 调试输出函数
debug_log() {
    if [[ "$DEBUG" == true ]]; then
        echo -e "${YELLOW}[DEBUG]${NC} $1" >&2
    fi
}

# 多方法测试 DoH 服务器
test_doh_server() {
    local server=$1
    local name=$2
    local features=$3
    local provider=$4
    local country=$5
    
    local result=""
    local latency="--"
    local status="❌ Fail"
    local method_used=""
    
    debug_log "测试服务器: $name ($server)"
    
    # 方法1: 使用 q 工具
    if command -v q &> /dev/null; then
        debug_log "尝试使用 q 工具"
        local start_time=$(date +%s%3N)
        result=$(timeout ${TIMEOUT}s q "$TEST_DOMAIN" A -s "$server" --timeout=${TIMEOUT}s 2>/dev/null)
        local end_time=$(date +%s%3N)
        
        if echo "$result" | grep -q "A.*[0-9]"; then
            latency=$((end_time - start_time))
            status="✅ OK"
            method_used="q"
            debug_log "q 工具成功: $result"
        else
            debug_log "q 工具失败: $result"
        fi
    fi
    
    # 方法2: 如果 q 失败，尝试 curl + dig
    if [[ "$status" == "❌ Fail" ]] && command -v curl &> /dev/null && command -v dig &> /dev/null; then
        debug_log "尝试使用 curl + dig"
        local start_time=$(date +%s%3N)
        
        # 使用 curl 进行 DoH 查询
        local doh_result=$(curl -s -m "$TIMEOUT" -H "Accept: application/dns-json" \
            "$server?name=$TEST_DOMAIN&type=A" 2>/dev/null)
        
        local end_time=$(date +%s%3N)
        
        if echo "$doh_result" | grep -q '"Answer"' && echo "$doh_result" | grep -q '"data"'; then
            latency=$((end_time - start_time))
            status="✅ OK"
            method_used="curl"
            debug_log "curl 成功: $doh_result"
        else
            debug_log "curl 失败: $doh_result"
        fi
    fi
    
    # 方法3: 如果都失败，尝试简单的连通性测试
    if [[ "$status" == "❌ Fail" ]] && command -v curl &> /dev/null; then
        debug_log "尝试连通性测试"
        local start_time=$(date +%s%3N)
        
        if curl -s -m "$TIMEOUT" -I "$server" | grep -q "200 OK\|400 Bad Request\|405 Method Not Allowed"; then
            local end_time=$(date +%s%3N)
            latency=$((end_time - start_time))
            status="🔗 Reachable"
            method_used="ping"
            debug_log "连通性测试成功"
        else
            debug_log "连通性测试失败"
        fi
    fi
    
    # 输出结果
    if [[ "$OUTPUT_FORMAT" == "table" ]]; then
        local color=""
        case "$status" in
            "✅ OK") color="$GREEN" ;;
            "🔗 Reachable") color="$YELLOW" ;;
            *) color="$RED" ;;
        esac
        
		printf "%-30s %-45s %-23s %-20s ${color}%-18s${NC} %-17s %-18s %s\n" \
  			"$name" "$server" "$latency" "$country" "$status" "$provider" "$method_used" "$features"
    elif [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "{\"name\":\"$name\",\"server\":\"$server\",\"latency\":\"$latency\",\"country\":\"$country\",\"status\":\"$status\",\"provider\":\"$provider\",\"method\":\"$method_used\",\"features\":\"$features\"}"
    elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
        echo "$name,$server,$latency,$country,$status,$provider,$method_used,$features"
    fi
    
    # 返回成功状态
    [[ "$status" == "✅ OK" ]] && return 0 || return 1
}

# 网络诊断函数
network_diagnosis() {
    echo -e "${CYAN}===== 网络诊断 =====${NC}"
    
    # 检查基本网络连接
    echo -n "检查网络连接... "
    if ping -c 1 -W 3 8.8.8.8 &> /dev/null; then
        echo -e "${GREEN}✅ 正常${NC}"
    else
        echo -e "${RED}❌ 网络不可达${NC}"
        return 1
    fi
    
    # 检查 DNS 解析
    echo -n "检查 DNS 解析... "
    if nslookup google.com &> /dev/null; then
        echo -e "${GREEN}✅ 正常${NC}"
    else
        echo -e "${RED}❌ DNS 解析失败${NC}"
    fi
    
    # 检查 HTTPS 连接
    echo -n "检查 HTTPS 连接... "
    if curl -s -m 3 https://www.google.com &> /dev/null; then
        echo -e "${GREEN}✅ 正常${NC}"
    else
        echo -e "${RED}❌ HTTPS 连接失败${NC}"
    fi
    
    # 检查可用工具
    echo -e "\n可用工具检查:"
    for tool in q curl dig nslookup ping; do
        if command -v "$tool" &> /dev/null; then
            echo -e "  $tool: ${GREEN}✅ 已安装${NC}"
        else
            echo -e "  $tool: ${RED}❌ 未安装${NC}"
        fi
    done
    
    echo
}

# 显示帮助
show_help() {
    cat << EOF
全面型 DoH 测试脚本

用法: $0 [选项]

选项:
  -d, --domain DOMAIN    测试域名 (默认: $TEST_DOMAIN)
  -t, --timeout TIMEOUT 超时时间 (默认: ${TIMEOUT}s)
  -f, --format FORMAT    输出格式: table, json, csv (默认: table)
  --debug                调试模式
  --diagnosis            网络诊断
  -h, --help             显示帮助信息

示例:
  $0                     # 基本测试
  $0 --diagnosis         # 网络诊断
  $0 --debug             # 调试模式
  $0 -d baidu.com        # 测试指定域名
  $0 -f json             # JSON 格式输出

EOF
}

# 参数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            TEST_DOMAIN="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -f|--format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --diagnosis)
            network_diagnosis
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 主程序
main() {
    echo -e "${BLUE}===== 全面型 DoH 测试开始 =====${NC}"
    echo "测试域名: $TEST_DOMAIN"
    echo "超时时间: ${TIMEOUT}s"
    echo "输出格式: $OUTPUT_FORMAT"
    echo
    
    # 表格头部
    if [[ "$OUTPUT_FORMAT" == "table" ]]; then
		printf "%-35s %-45s %-25s %-23s %-18s %-18s %-24s %s\n" \
  			"名称" "服务器" "延迟(ms)" "国家" "状态" "提供商" "方法" "特性"
		echo "$(printf '%.240s' "$(yes '-' | head -240 | tr -d '\n')")"
    elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
        echo "名称,服务器,延迟(ms),国家,状态,提供商,方法,特性"
    fi
    
    # 测试所有服务器
    local total=${#DOH_SERVERS[@]}
    local success=0
    local reachable=0
    local failed=0
    
    for server_info in "${DOH_SERVERS[@]}"; do
        IFS='|' read -r name server country features provider <<< "$server_info"
        
        if test_doh_server "$server" "$name" "$features" "$provider" "$country"; then
            ((success++))
        elif [[ "$?" -eq 2 ]]; then
            ((reachable++))
        else
            ((failed++))
        fi
    done
    
    # 统计信息
    echo
    echo -e "${BLUE}===== 测试统计 =====${NC}"
    echo "总计: $total 个服务器"
    echo -e "${GREEN}完全正常: $success 个${NC}"
    echo -e "${YELLOW}可达但未测试: $reachable 个${NC}"
    echo -e "${RED}失败: $failed 个${NC}"
    if [[ $total -gt 0 ]]; then
        echo -e "${YELLOW}成功率: $(( success * 100 / total ))%${NC}"
    fi
    
    # 推荐服务器
    echo
    echo -e "${PURPLE}===== 推荐使用 =====${NC}"
    if [[ $success -gt 0 ]]; then
        echo -e "${GREEN}✅ 有 $success 个服务器工作正常，可以正常使用${NC}"
        echo "🌍 国际用户推荐: Cloudflare (1.1.1.1), Google (8.8.8.8)"
        echo "🇨🇳 国内用户推荐: 阿里DNS, 腾讯DNS"
        echo "🔒 隐私保护推荐: Mullvad, Digitale Gesellschaft"
        echo "🛡️ 广告拦截推荐: AdGuard, LibreDNS"
    else
        echo -e "${RED}❌ 没有服务器工作正常${NC}"
        echo "建议:"
        echo "1. 检查网络连接: $0 --diagnosis"
        echo "2. 安装 q 工具: go install github.com/natesales/q@latest"
        echo "3. 使用调试模式: $0 --debug"
    fi
    
    echo -e "\n${BLUE}===== DoH 测试结束 =====${NC}"
}

# 运行主程序
main "$@"
