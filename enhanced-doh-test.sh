#!/usr/bin/env bash
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
# 🧪 全面型 DoH 测试脚本
# 功能：测试 DoH 服务可用性、延迟、HTTP 能力和基础网络依赖
# By: BuBuXSY
# Version: 2026-07-11
# ====================================================

set -u -o pipefail

# Optional embedded UI; the script remains standalone when the shared library is absent.
COLOR_MODE="${COLOR_MODE:-auto}"
init_colors() {
    local mode="$COLOR_MODE"
    case "$mode" in auto|always|never) ;; *) mode=auto ;; esac
    case "$mode" in
        always) COLOR_ENABLED=1 ;;
        auto)
            if [[ -t 2 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then COLOR_ENABLED=1; else COLOR_ENABLED=0; fi
            ;;
        never) COLOR_ENABLED=0 ;;
    esac
    if [[ "$COLOR_ENABLED" == 1 ]]; then
        GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; BLUE=$'\033[36m'; CYAN=$'\033[36m'; MAGENTA=$'\033[35m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
    else GREEN=; YELLOW=; RED=; BLUE=; CYAN=; MAGENTA=; BOLD=; RESET=; fi
}
init_colors

# 配置变量
TEST_DOMAIN="www.google.com"
TIMEOUT=5
OUTPUT_FORMAT="table"
DEBUG=false
RUN_DIAGNOSIS=false

PURPLE="$MAGENTA"
NC="$RESET"

TABLE_FORMAT="%-30s %-45s %-15s %-10s %-18s %-17s %-12s %s"

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

now_milliseconds() {
    local value
    value=$(date +%s%3N 2>/dev/null || true)
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$value"
    else
        printf '%s000\n' "$(date +%s)"
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

csv_escape() {
    local value="$1"
    value=${value//\"/\"\"}
    printf '"%s"' "$value"
}

valid_domain() {
    local domain="${1%.}"
    local label
    local labels=()

    [[ -n "$domain" && ${#domain} -le 253 ]] || return 1
    IFS='.' read -r -a labels <<< "$domain"
    for label in "${labels[@]}"; do
        [[ ${#label} -le 63 && "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    done
}

print_result() {
    local name="$1"
    local server="$2"
    local latency="$3"
    local country="$4"
    local status="$5"
    local provider="$6"
    local method="$7"
    local features="$8"
    local color="$9"

    case "$OUTPUT_FORMAT" in
        table)
            printf "${color}${TABLE_FORMAT}${NC}\n" \
                "$name" "$server" "$latency" "$country" "$status" "$provider" "$method" "$features"
            ;;
        json)
            printf '{"name":"%s","server":"%s","latency_ms":%s,"country":"%s","status":"%s","provider":"%s","method":"%s","features":"%s"}' \
                "$(json_escape "$name")" \
                "$(json_escape "$server")" \
                "$([[ "$latency" =~ ^[0-9]+$ ]] && printf '%s' "$latency" || printf 'null')" \
                "$(json_escape "$country")" \
                "$(json_escape "$status")" \
                "$(json_escape "$provider")" \
                "$(json_escape "$method")" \
                "$(json_escape "$features")"
            ;;
        csv)
            printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
                "$(csv_escape "$name")" \
                "$(csv_escape "$server")" \
                "$(csv_escape "$latency")" \
                "$(csv_escape "$country")" \
                "$(csv_escape "$status")" \
                "$(csv_escape "$provider")" \
                "$(csv_escape "$method")" \
                "$(csv_escape "$features")"
            ;;
    esac
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
    
    # 方法1: 使用 q 工具进行标准 DoH 查询。
    if command -v q &> /dev/null; then
        debug_log "尝试使用 q 工具"
        local start_time
        local end_time
        start_time=$(now_milliseconds)
        result=$(q -r -s "$server" -t A --timeout="${TIMEOUT}s" "$TEST_DOMAIN" 2>/dev/null || true)
        end_time=$(now_milliseconds)
        
        if grep -Eq '([0-9]{1,3}\.){3}[0-9]{1,3}|[0-9a-fA-F]{0,4}:[0-9a-fA-F:]+' <<< "$result"; then
            latency=$((end_time - start_time))
            status="✅ OK"
            method_used="q"
            debug_log "q 工具成功: $result"
        else
            debug_log "q 工具失败: $result"
        fi
    fi
    
    # 方法2: 如果 q 失败，尝试兼容 dns-json 的 DoH 查询。
    if [[ "$status" == "❌ Fail" ]] && command -v curl &> /dev/null; then
        debug_log "尝试使用 curl dns-json"
        local start_time
        local end_time
        local doh_result
        start_time=$(now_milliseconds)
        
        doh_result=$(curl -fsS --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" \
            --get -H "Accept: application/dns-json" \
            --data-urlencode "name=$TEST_DOMAIN" --data-urlencode "type=A" \
            "$server" 2>/dev/null || true)
        
        end_time=$(now_milliseconds)
        
        if grep -Eq '"Status"[[:space:]]*:[[:space:]]*0' <<< "$doh_result" && \
            grep -q '"Answer"' <<< "$doh_result" && grep -q '"data"' <<< "$doh_result"; then
            latency=$((end_time - start_time))
            status="✅ OK"
            method_used="curl"
            debug_log "curl 成功: $doh_result"
        else
            debug_log "curl 失败: $doh_result"
        fi
    fi
    
    # 方法3: 如果查询失败，区分服务不可用与 HTTP 端点可达。
    if [[ "$status" == "❌ Fail" ]] && command -v curl &> /dev/null; then
        debug_log "尝试连通性测试"
        local start_time
        local end_time
        local http_code
        start_time=$(now_milliseconds)
        
        if http_code=$(curl -sS -o /dev/null -w '%{http_code}' \
            --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" "$server" 2>/dev/null) && \
            [[ "$http_code" =~ ^[1-5][0-9][0-9]$ ]]; then
            end_time=$(now_milliseconds)
            latency=$((end_time - start_time))
            status="🔗 Reachable"
            method_used="HTTP"
            debug_log "连通性测试成功，HTTP 状态码: $http_code"
        else
            debug_log "连通性测试失败"
        fi
    fi
    
    local color="$RED"
    case "$status" in
        "✅ OK") color="$GREEN" ;;
        "🔗 Reachable") color="$YELLOW" ;;
    esac
    print_result "$name" "$server" "$latency" "$country" "$status" "$provider" "$method_used" "$features" "$color"
    
    case "$status" in
        "✅ OK") return 0 ;;
        "🔗 Reachable") return 2 ;;
        *) return 1 ;;
    esac
}

# 网络诊断函数
network_diagnosis() {
    echo -e "${CYAN}===== 网络诊断 =====${NC}"
    local failures=0
    
    # 检查基本网络连接
    echo -n "检查网络连接... "
    if command -v ping >/dev/null 2>&1 && ping -c 1 -W 3 8.8.8.8 &> /dev/null; then
        echo -e "${GREEN}✅ 正常${NC}"
    else
        echo -e "${RED}❌ 网络不可达${NC}"
        failures=$((failures + 1))
    fi
    
    # 检查 DNS 解析
    echo -n "检查 DNS 解析... "
    if command -v nslookup >/dev/null 2>&1 && nslookup google.com &> /dev/null; then
        echo -e "${GREEN}✅ 正常${NC}"
    else
        echo -e "${RED}❌ DNS 解析失败${NC}"
        failures=$((failures + 1))
    fi
    
    # 检查 HTTPS 连接
    echo -n "检查 HTTPS 连接... "
    if command -v curl >/dev/null 2>&1 && curl -fsS --connect-timeout 3 --max-time 3 https://www.google.com &> /dev/null; then
        echo -e "${GREEN}✅ 正常${NC}"
    else
        echo -e "${RED}❌ HTTPS 连接失败${NC}"
        failures=$((failures + 1))
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
    (( failures == 0 ))
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
  --no-color             禁用 ANSI 颜色
  --color=MODE           auto、always 或 never
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
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                echo "参数 $1 缺少域名" >&2
                exit 2
            fi
            TEST_DOMAIN="$2"
            shift 2
            ;;
        -t|--timeout)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                echo "参数 $1 缺少超时秒数" >&2
                exit 2
            fi
            TIMEOUT="$2"
            shift 2
            ;;
        --no-color) COLOR_MODE=never; init_colors; PURPLE="$MAGENTA"; NC="$RESET"; shift ;;
        --color=*) COLOR_MODE=${1#*=}; case "$COLOR_MODE" in auto|always|never) ;; *) echo "无效颜色模式: $COLOR_MODE" >&2; exit 2;; esac; init_colors; PURPLE="$MAGENTA"; NC="$RESET"; shift ;;
        -f|--format)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                echo "参数 $1 缺少输出格式" >&2
                exit 2
            fi
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --diagnosis)
            RUN_DIAGNOSIS=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "未知参数: $1" >&2
            show_help >&2
            exit 2
            ;;
    esac
done

if ! valid_domain "$TEST_DOMAIN"; then
    echo "无效测试域名: $TEST_DOMAIN" >&2
    exit 2
fi
TEST_DOMAIN="${TEST_DOMAIN%.}"

if [[ ! "$TIMEOUT" =~ ^[1-9][0-9]*$ ]] || (( TIMEOUT > 300 )); then
    echo "超时时间必须是 1-300 秒的整数: $TIMEOUT" >&2
    exit 2
fi

case "$OUTPUT_FORMAT" in
    table|json|csv) ;;
    *)
        echo "无效输出格式: $OUTPUT_FORMAT（支持 table、json、csv）" >&2
        exit 2
        ;;
esac

if [[ "$RUN_DIAGNOSIS" == true ]]; then
    network_diagnosis
    exit $?
fi

# 主程序
main() {
    local info_fd=1
    if [[ "$OUTPUT_FORMAT" != "table" ]]; then
        info_fd=2
    fi

    printf '%b⚡ NOC // 全面型 DoH 测试%b\n' "$CYAN$BOLD" "$RESET" >&$info_fd
    echo -e "${BLUE}===== 全面型 DoH 测试开始 =====${NC}" >&$info_fd
    echo "测试域名: $TEST_DOMAIN" >&$info_fd
    echo "超时时间: ${TIMEOUT}s" >&$info_fd
    echo "输出格式: $OUTPUT_FORMAT" >&$info_fd
    echo >&$info_fd
    
    # 表格头部
    if [[ "$OUTPUT_FORMAT" == "table" ]]; then
        local separator
        printf "${TABLE_FORMAT}\n" "名称" "服务器" "延迟(ms)" "国家" "状态" "提供商" "方法" "特性"
        printf -v separator '%*s' 180 ''
        echo "${separator// /-}"
    elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
        echo '"名称","服务器","延迟(ms)","国家","状态","提供商","方法","特性"'
    else
        printf '[\n'
    fi
    
    # 测试所有服务器
    local total=${#DOH_SERVERS[@]}
    local success=0
    local reachable=0
    local failed=0
    local first_json=true
    local result_status
    
    for server_info in "${DOH_SERVERS[@]}"; do
        IFS='|' read -r name server country features provider <<< "$server_info"
        
        if [[ "$OUTPUT_FORMAT" == "json" ]]; then
            if [[ "$first_json" == true ]]; then
                first_json=false
            else
                printf ',\n'
            fi
        fi

        test_doh_server "$server" "$name" "$features" "$provider" "$country"
        result_status=$?
        if [[ "$result_status" -eq 0 ]]; then
            success=$((success + 1))
        elif [[ "$result_status" -eq 2 ]]; then
            reachable=$((reachable + 1))
        else
            failed=$((failed + 1))
        fi
    done


    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        printf '\n]\n'
    fi
    
    # 统计信息
    echo >&$info_fd
    echo -e "${BLUE}===== 测试统计 =====${NC}" >&$info_fd
    echo "总计: $total 个服务器" >&$info_fd
    echo -e "${GREEN}完全正常: $success 个${NC}" >&$info_fd
    echo -e "${YELLOW}端点可达但查询失败: $reachable 个${NC}" >&$info_fd
    echo -e "${RED}失败: $failed 个${NC}" >&$info_fd
    if [[ $total -gt 0 ]]; then
        echo -e "${YELLOW}成功率: $(( success * 100 / total ))%${NC}" >&$info_fd
    fi
    
    # 推荐服务器
    echo >&$info_fd
    echo -e "${PURPLE}===== 推荐使用 =====${NC}" >&$info_fd
    if [[ $success -gt 0 ]]; then
        echo -e "${GREEN}✅ 有 $success 个服务器工作正常，可以正常使用${NC}" >&$info_fd
        echo "🌍 国际用户推荐: Cloudflare (1.1.1.1), Google (8.8.8.8)" >&$info_fd
        echo "🇨🇳 国内用户推荐: 阿里DNS, 腾讯DNS" >&$info_fd
        echo "🔒 隐私保护推荐: Mullvad, Digitale Gesellschaft" >&$info_fd
        echo "🛡️ 广告拦截推荐: AdGuard, LibreDNS" >&$info_fd
    else
        echo -e "${RED}❌ 没有服务器工作正常${NC}" >&$info_fd
        echo "建议:" >&$info_fd
        echo "1. 检查网络连接: $0 --diagnosis" >&$info_fd
        echo "2. 安装 q 工具: go install github.com/natesales/q@latest" >&$info_fd
        echo "3. 使用调试模式: $0 --debug" >&$info_fd
    fi
    
    echo -e "\n${BLUE}===== DoH 测试结束 =====${NC}" >&$info_fd
    (( success > 0 ))
}

# 运行主程序
main "$@"
