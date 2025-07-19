#!/bin/bash
# 证书管理终极脚本，支持多CA，DNS API/手动验证，ECC证书，自动部署并重载nginx
# 支持多CA，DNS API/手动验证，ECC证书，自动部署并重载nginx
# By: BuBuXSY
# Version: 2025-07-19
# License: MIT


set -euo pipefail  # 严格模式

# 设置颜色和格式
readonly RED="\e[31m"
readonly GREEN="\e[32m"
readonly YELLOW="\e[33m"
readonly BLUE="\e[34m"
readonly MAGENTA="\e[35m"
readonly CYAN="\e[36m"
readonly BOLD="\e[1m"
readonly RESET="\e[0m"

# 设置表情
readonly SUCCESS="✔️"
readonly ERROR="❌"
readonly INFO="ℹ️"
readonly WARNING="⚠️"
readonly THINKING="🤔"
readonly LOADING="⏳"

# 全局变量
CA_URL=""
DOMAIN=""
OPERATION=""
DNS_METHOD=""
DNS_PROVIDER=""
CERT_DIR="/etc/nginx/cert_file"
LOG_FILE="/var/log/acme-cert-tool.log"

# 日志函数
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case "$level" in
        "ERROR")
            echo -e "${RED}${ERROR} $message${RESET}" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}${WARNING} $message${RESET}"
            ;;
        "INFO")
            echo -e "${CYAN}${INFO} $message${RESET}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}${SUCCESS} $message${RESET}"
            ;;
    esac
}

# 错误处理函数
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# 显示欢迎信息
welcome_message() {
    clear
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║          ACME 证书申请自动化工具 - 优化版                  ║${RESET}"
    echo -e "${CYAN}${BOLD}║                  支持多CA和自动化部署                     ║${RESET}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    log "INFO" "工具启动，支持 Let's Encrypt, Buypass, ZeroSSL"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "此脚本需要root权限运行，请使用 sudo 或切换到root用户"
    fi
}

# 检查系统依赖
check_dependencies() {
    local deps=("curl" "wget" "dig" "openssl")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "WARN" "缺少依赖: ${missing[*]}"
        read -p "是否自动安装缺少的依赖？[y/N]: " install_deps
        if [[ "$install_deps" =~ ^[Yy]$ ]]; then
            log "INFO" "安装依赖包..."
            apt update && apt install -y "${missing[@]}" || error_exit "依赖安装失败"
            log "SUCCESS" "依赖安装完成"
        else
            error_exit "缺少必要依赖，无法继续"
        fi
    fi
}

# 显示进度条
show_progress() {
    local pid=$1
    local message="$2"
    local chars="/-\\|"
    local i=0
    
    echo -n "$message "
    while kill -0 $pid 2>/dev/null; do
        printf "\r$message ${LOADING} %c" "${chars:$((i%4)):1}"
        sleep 0.2
        ((i++))
    done
    echo -e "\r$message ${SUCCESS}"
}

# 选择 CA 供应商
select_ca() {
    echo -e "${GREEN}${BOLD}选择 CA 供应商：${RESET}"
    echo -e "  ${BLUE}1)${RESET} Let's Encrypt (免费，推荐)"
    echo -e "  ${BLUE}2)${RESET} Buypass (免费，90天)"
    echo -e "  ${BLUE}3)${RESET} ZeroSSL (免费，90天)"
    echo ""
    
    while true; do
        read -p "请选择 [1-3] (默认: 1): " ca_choice
        ca_choice=${ca_choice:-1}
        
        case $ca_choice in
            1)
                CA_URL="https://acme-v02.api.letsencrypt.org/directory"
                log "SUCCESS" "选择了 Let's Encrypt 作为 CA"
                break
                ;;
            2)
                CA_URL="https://api.buypass.com/acme/directory"
                log "SUCCESS" "选择了 Buypass 作为 CA"
                break
                ;;
            3)
                CA_URL="https://acme.zerossl.com/v2/DV90"
                log "SUCCESS" "选择了 ZeroSSL 作为 CA"
                break
                ;;
            *)
                log "WARN" "无效选择，请重新输入"
                ;;
        esac
    done
}

# 验证域名格式
validate_domain() {
    local domain="$1"
    # 简单的域名格式验证
    if [[ ! "$domain" =~ ^(\*\.)?[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

# 选择DNS验证方式
select_dns_method() {
    echo -e "${GREEN}${BOLD}选择 DNS 验证方式：${RESET}"
    echo -e "  ${BLUE}1)${RESET} 手动添加 DNS 记录"
    echo -e "  ${BLUE}2)${RESET} 使用 DNS API 自动验证"
    echo ""
    
    while true; do
        read -p "请选择 [1-2] (默认: 1): " dns_method_choice
        dns_method_choice=${dns_method_choice:-1}
        
        case $dns_method_choice in
            1)
                DNS_METHOD="manual"
                log "SUCCESS" "选择手动 DNS 验证方式"
                break
                ;;
            2)
                DNS_METHOD="api"
                select_dns_provider
                break
                ;;
            *)
                log "WARN" "无效选择，请重新输入"
                ;;
        esac
    done
}

# 选择DNS服务商
select_dns_provider() {
    echo -e "${GREEN}${BOLD}选择 DNS 服务商：${RESET}"
    echo -e "  ${BLUE}1)${RESET} 阿里云 DNS (dns_ali)"
    echo -e "  ${BLUE}2)${RESET} 腾讯云 DNS (dns_tencent)" 
    echo -e "  ${BLUE}3)${RESET} Cloudflare (dns_cf)"
    echo -e "  ${BLUE}4)${RESET} DNSPod (dns_dp)"
    echo -e "  ${BLUE}5)${RESET} 华为云 DNS (dns_huaweicloud)"
    echo -e "  ${BLUE}6)${RESET} 其他服务商"
    echo ""
    
    while true; do
        read -p "请选择 [1-6]: " dns_provider_choice
        
        case $dns_provider_choice in
            1)
                DNS_PROVIDER="dns_ali"
                setup_aliyun_dns_api
                break
                ;;
            2)
                DNS_PROVIDER="dns_tencent"
                setup_tencent_dns_api
                break
                ;;
            3)
                DNS_PROVIDER="dns_cf"
                setup_cloudflare_dns_api
                break
                ;;
            4)
                DNS_PROVIDER="dns_dp"
                setup_dnspod_dns_api
                break
                ;;
            5)
                DNS_PROVIDER="dns_huaweicloud"
                setup_huawei_dns_api
                break
                ;;
            6)
                show_other_providers
                setup_custom_dns_api
                break
                ;;
            *)
                log "WARN" "无效选择，请重新输入"
                ;;
        esac
    done
}

# 设置阿里云DNS API
setup_aliyun_dns_api() {
    log "INFO" "配置阿里云 DNS API"
    echo -e "${CYAN}请从阿里云控制台获取 AccessKey：${RESET}"
    echo -e "${CYAN}https://ram.console.aliyun.com/manage/ak${RESET}"
    echo ""
    
    read -p "请输入 AccessKey ID: " ali_key
    read -s -p "请输入 AccessKey Secret: " ali_secret
    echo ""
    
    if [[ -n "$ali_key" && -n "$ali_secret" ]]; then
        export Ali_Key="$ali_key"
        export Ali_Secret="$ali_secret"
        log "SUCCESS" "阿里云 DNS API 配置完成"
    else
        error_exit "阿里云 API 密钥不能为空"
    fi
}

# 设置腾讯云DNS API
setup_tencent_dns_api() {
    log "INFO" "配置腾讯云 DNS API"
    echo -e "${CYAN}请从腾讯云控制台获取密钥：${RESET}"
    echo -e "${CYAN}https://console.cloud.tencent.com/cam/capi${RESET}"
    echo ""
    
    read -p "请输入 SecretId: " tencent_id
    read -s -p "请输入 SecretKey: " tencent_key
    echo ""
    
    if [[ -n "$tencent_id" && -n "$tencent_key" ]]; then
        export Tencent_SecretId="$tencent_id"
        export Tencent_SecretKey="$tencent_key"
        log "SUCCESS" "腾讯云 DNS API 配置完成"
    else
        error_exit "腾讯云 API 密钥不能为空"
    fi
}

# 设置Cloudflare DNS API
setup_cloudflare_dns_api() {
    log "INFO" "配置 Cloudflare DNS API"
    echo -e "${CYAN}请从 Cloudflare 控制台获取 API Token：${RESET}"
    echo -e "${CYAN}https://dash.cloudflare.com/profile/api-tokens${RESET}"
    echo ""
    
    read -s -p "请输入 API Token: " cf_token
    echo ""
    
    if [[ -n "$cf_token" ]]; then
        export CF_Token="$cf_token"
        log "SUCCESS" "Cloudflare DNS API 配置完成"
    else
        error_exit "Cloudflare API Token 不能为空"
    fi
}

# 设置DNSPod API
setup_dnspod_dns_api() {
    log "INFO" "配置 DNSPod DNS API"
    echo -e "${CYAN}请从 DNSPod 控制台获取密钥：${RESET}"
    echo -e "${CYAN}https://console.dnspod.cn/account/token${RESET}"
    echo ""
    
    read -p "请输入 API ID: " dp_id
    read -s -p "请输入 API Key: " dp_key
    echo ""
    
    if [[ -n "$dp_id" && -n "$dp_key" ]]; then
        export DP_Id="$dp_id"
        export DP_Key="$dp_key"
        log "SUCCESS" "DNSPod DNS API 配置完成"
    else
        error_exit "DNSPod API 密钥不能为空"
    fi
}

# 设置华为云DNS API
setup_huawei_dns_api() {
    log "INFO" "配置华为云 DNS API"
    echo -e "${CYAN}请从华为云控制台获取密钥：${RESET}"
    echo -e "${CYAN}https://console.huaweicloud.com/iam/#/mine/accessKey${RESET}"
    echo ""
    
    read -p "请输入 Access Key: " huawei_key
    read -s -p "请输入 Secret Key: " huawei_secret
    echo ""
    
    if [[ -n "$huawei_key" && -n "$huawei_secret" ]]; then
        export HUAWEICLOUD_AccessKey="$huawei_key"
        export HUAWEICLOUD_SecretKey="$huawei_secret"
        log "SUCCESS" "华为云 DNS API 配置完成"
    else
        error_exit "华为云 API 密钥不能为空"
    fi
}

# 显示其他DNS服务商
show_other_providers() {
    echo -e "${CYAN}${BOLD}支持的其他 DNS 服务商：${RESET}"
    echo -e "${CYAN}• GoDaddy (dns_gd)${RESET}"
    echo -e "${CYAN}• Name.com (dns_namecom)${RESET}"
    echo -e "${CYAN}• Namecheap (dns_namecheap)${RESET}"
    echo -e "${CYAN}• Route53 (dns_aws)${RESET}"
    echo -e "${CYAN}• Google Cloud DNS (dns_gcloud)${RESET}"
    echo -e "${CYAN}• 更多服务商请查看：https://github.com/acmesh-official/acme.sh/wiki/dnsapi${RESET}"
    echo ""
}

# 设置自定义DNS API
setup_custom_dns_api() {
    read -p "请输入 DNS API 名称 (例如: dns_gd): " custom_dns
    
    if [[ -z "$custom_dns" ]]; then
        error_exit "DNS API 名称不能为空"
    fi
    
    DNS_PROVIDER="$custom_dns"
    log "INFO" "请根据 acme.sh 文档配置对应的环境变量"
    log "INFO" "文档地址：https://github.com/acmesh-official/acme.sh/wiki/dnsapi"
    
    read -p "按 [Enter] 继续，确保已配置好相关环境变量..."
}

# 获取域名输入
get_domain_input() {
    while true; do
        read -p "请输入域名 (例如: example.com 或 *.example.com): " domain_input
        
        if [[ -z "$domain_input" ]]; then
            log "WARN" "域名不能为空"
            continue
        fi
        
        if validate_domain "$domain_input"; then
            DOMAIN="$domain_input"
            log "INFO" "域名格式验证通过: $DOMAIN"
            break
        else
            log "WARN" "域名格式不正确，请重新输入"
        fi
    done
}

# 选择操作类型
select_operation() {
    echo -e "${GREEN}${BOLD}选择操作类型：${RESET}"
    echo -e "  ${BLUE}1)${RESET} 申请新证书"
    echo -e "  ${BLUE}2)${RESET} 续期现有证书"
    echo -e "  ${BLUE}3)${RESET} 强制更新证书"
    echo -e "  ${BLUE}4)${RESET} 查看现有证书"
    echo ""
    
    while true; do
        read -p "请选择 [1-4]: " operation_choice
        
        case $operation_choice in
            1)
                OPERATION="issue"
                get_domain_input
                check_existing_cert
                select_dns_method
                break
                ;;
            2)
                OPERATION="renew"
                select_existing_domain
                break
                ;;
            3)
                OPERATION="force_renew"
                select_existing_domain
                break
                ;;
            4)
                list_certificates
                select_operation
                break
                ;;
            *)
                log "WARN" "无效选择，请重新输入"
                ;;
        esac
    done
}

# 检查现有证书
check_existing_cert() {
    if command -v acme.sh &> /dev/null; then
        local existing=$(acme.sh --list 2>/dev/null | grep -w "$DOMAIN" || true)
        if [[ -n "$existing" ]]; then
            log "WARN" "域名 $DOMAIN 已存在证书"
            echo -e "${YELLOW}现有证书信息：${RESET}"
            echo "$existing"
            echo ""
            read -p "是否继续？这将覆盖现有证书 [y/N]: " continue_choice
            if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
                log "INFO" "操作已取消"
                exit 0
            fi
        fi
    fi
}

# 列出现有证书
list_certificates() {
    echo -e "${GREEN}${BOLD}现有证书列表：${RESET}"
    if command -v acme.sh &> /dev/null; then
        local cert_list=$(acme.sh --list 2>/dev/null)
        if [[ -n "$cert_list" ]]; then
            echo "$cert_list"
        else
            log "INFO" "未找到任何证书"
        fi
    else
        log "WARN" "acme.sh 未安装，无法查看证书列表"
    fi
    echo ""
}

# 选择现有域名
select_existing_domain() {
    if ! command -v acme.sh &> /dev/null; then
        error_exit "acme.sh 未安装，无法操作现有证书"
    fi
    
    local domains=$(acme.sh --list 2>/dev/null | awk 'NR>1 {print $1}' | grep -v "^$" || true)
    
    if [[ -z "$domains" ]]; then
        error_exit "未找到任何现有证书"
    fi
    
    echo -e "${GREEN}现有域名列表：${RESET}"
    local domain_array=()
    local i=1
    
    while IFS= read -r domain; do
        if [[ -n "$domain" ]]; then
            echo -e "  ${BLUE}$i)${RESET} $domain"
            domain_array+=("$domain")
            ((i++))
        fi
    done <<< "$domains"
    
    echo ""
    while true; do
        read -p "请选择域名 [1-$((i-1))]: " domain_choice
        
        if [[ "$domain_choice" =~ ^[0-9]+$ ]] && [[ "$domain_choice" -ge 1 ]] && [[ "$domain_choice" -le $((i-1)) ]]; then
            DOMAIN="${domain_array[$((domain_choice-1))]}"
            log "SUCCESS" "选择了域名: $DOMAIN"
            break
        else
            log "WARN" "无效选择，请重新输入"
        fi
    done
}

# 安装 acme.sh
install_acme() {
    if command -v acme.sh &> /dev/null; then
        log "SUCCESS" "acme.sh 已安装"
        return 0
    fi
    
    log "INFO" "开始安装 acme.sh..."
    
    # 下载并安装 acme.sh
    {
        cd /tmp
        wget -O- https://get.acme.sh | sh -s email=admin@example.com
    } &
    
    show_progress $! "正在安装 acme.sh"
    wait
    
    # 创建软链接
    if [[ -f "$HOME/.acme.sh/acme.sh" ]]; then
        ln -sf "$HOME/.acme.sh/acme.sh" /usr/local/bin/acme.sh
        # 添加到PATH
        if ! echo "$PATH" | grep -q "/usr/local/bin"; then
            export PATH="/usr/local/bin:$PATH"
        fi
        log "SUCCESS" "acme.sh 安装完成"
    else
        error_exit "acme.sh 安装失败"
    fi
}

# 设置 CA
set_ca() {
    log "INFO" "设置 CA 为: $CA_URL"
    if ! acme.sh --set-default-ca --server "$CA_URL"; then
        error_exit "设置 CA 失败"
    fi
    log "SUCCESS" "CA 设置完成"
}

# DNS记录验证
verify_dns_record() {
    local domain="$1"
    local txt_value="$2"
    local max_attempts=30
    local attempt=1
    
    log "INFO" "验证 DNS TXT 记录..."
    
    while [[ $attempt -le $max_attempts ]]; do
        log "INFO" "第 $attempt/$max_attempts 次验证..."
        
        # 使用多个DNS服务器验证
        local dns_servers=("8.8.8.8" "1.1.1.1" "208.67.222.222")
        local verified=false
        
        for dns_server in "${dns_servers[@]}"; do
            local result=$(dig @"$dns_server" +short TXT "_acme-challenge.$domain" 2>/dev/null || true)
            if echo "$result" | grep -q "$txt_value"; then
                verified=true
                break
            fi
        done
        
        if [[ "$verified" == true ]]; then
            log "SUCCESS" "DNS 记录验证成功"
            return 0
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            log "ERROR" "DNS 记录验证失败，已达到最大尝试次数"
            return 1
        fi
        
        log "INFO" "等待 DNS 记录生效... ($(($max_attempts - $attempt)) 次重试剩余)"
        sleep 10
        ((attempt++))
    done
}

# 申请证书
issue_certificate() {
    log "INFO" "开始申请证书: $DOMAIN"
    
    if [[ "$DNS_METHOD" == "api" ]]; then
        # 使用 DNS API 自动验证
        log "INFO" "使用 DNS API 自动验证: $DNS_PROVIDER"
        
        if acme.sh --issue --dns "$DNS_PROVIDER" --keylength ec-256 -d "$DOMAIN"; then
            log "SUCCESS" "证书申请成功（DNS API 验证）"
        else
            error_exit "证书申请失败（DNS API 验证）"
        fi
    else
        # 手动 DNS 验证
        log "INFO" "使用手动 DNS 验证方式"
        
        # 第一步：生成 DNS 验证记录
        log "INFO" "生成 DNS 验证记录..."
        local challenge_output
        challenge_output=$(acme.sh --issue --dns --keylength ec-256 -d "$DOMAIN" --yes-I-know-dns-manual-mode-enough-go-ahead-please 2>&1 || true)
        
        # 提取 TXT 记录值
        local txt_name="_acme-challenge.$DOMAIN"
        local txt_value
        txt_value=$(echo "$challenge_output" | grep -oP "TXT value: '\K[^']+'" | head -1)
        
        if [[ -z "$txt_value" ]]; then
            # 尝试另一种提取方式
            txt_value=$(echo "$challenge_output" | grep -oP "TXT value:\s*\K\S+" | head -1)
        fi
        
        if [[ -z "$txt_value" ]]; then
            log "ERROR" "无法提取 TXT 记录值"
            echo -e "${RED}验证输出：${RESET}"
            echo "$challenge_output"
            error_exit "DNS 验证记录生成失败"
        fi
        
        # 显示 DNS 记录信息
        echo -e "${YELLOW}${BOLD}请添加以下 DNS TXT 记录：${RESET}"
        echo -e "${CYAN}记录名称：${RESET} $txt_name"
        echo -e "${CYAN}记录类型：${RESET} TXT"
        echo -e "${CYAN}记录值：${RESET} $txt_value"
        echo -e "${CYAN}TTL：${RESET} 600 (或最小值)"
        echo ""
        
        read -p "添加完成后按 [Enter] 继续，或输入 'q' 退出: " continue_choice
        if [[ "$continue_choice" == "q" ]]; then
            log "INFO" "操作已取消"
            exit 0
        fi
        
        # 验证 DNS 记录
        if ! verify_dns_record "$DOMAIN" "$txt_value"; then
            read -p "DNS 记录验证失败，是否强制继续？[y/N]: " force_continue
            if [[ ! "$force_continue" =~ ^[Yy]$ ]]; then
                error_exit "操作已取消"
            fi
        fi
        
        # 第二步：完成验证
        log "INFO" "完成证书验证..."
        if acme.sh --renew --ecc -d "$DOMAIN" --yes-I-know-dns-manual-mode-enough-go-ahead-please; then
            log "SUCCESS" "证书申请成功（手动 DNS 验证）"
        else
            error_exit "证书申请失败（手动 DNS 验证）"
        fi
    fi
}

# 处理DNS手动验证
handle_manual_dns_verification() {
    local output="$1"
    local operation_type="$2"
    
    # 检查是否需要手动添加DNS记录
    if echo "$output" | grep -q "You need to add the TXT record manually"; then
        log "INFO" "需要手动添加 DNS TXT 记录"
        
        # 提取TXT记录信息
        local txt_domain=$(echo "$output" | grep "Domain:" | sed "s/.*Domain: '\(.*\)'/\1/" | head -1)
        local txt_value=$(echo "$output" | grep "TXT value:" | sed "s/.*TXT value: '\(.*\)'/\1/" | head -1)
        
        if [[ -z "$txt_domain" || -z "$txt_value" ]]; then
            # 尝试另一种提取方式
            txt_domain=$(echo "$output" | grep -oP "Domain:\s*['\"]?\K[^'\"]*" | head -1)
            txt_value=$(echo "$output" | grep -oP "TXT value:\s*['\"]?\K[^'\"]*" | head -1)
        fi
        
        if [[ -n "$txt_domain" && -n "$txt_value" ]]; then
            echo ""
            echo -e "${YELLOW}${BOLD}请添加以下 DNS TXT 记录：${RESET}"
            echo -e "${CYAN}记录名称：${RESET} $txt_domain"
            echo -e "${CYAN}记录类型：${RESET} TXT" 
            echo -e "${CYAN}记录值：${RESET} $txt_value"
            echo -e "${CYAN}TTL：${RESET} 600 (或最小值)"
            echo ""
            
            # 询问是否使用DNS API
            read -p "是否使用 DNS API 自动处理此验证？[y/N]: " use_api
            if [[ "$use_api" =~ ^[Yy]$ ]]; then
                select_dns_provider
                
                # 使用DNS API重新执行操作
                local final_result
                case "$operation_type" in
                    "renew")
                        final_result=$(acme.sh --renew --ecc --dns "$DNS_PROVIDER" -d "$DOMAIN" 2>&1 || true)
                        ;;
                    "force_renew")
                        final_result=$(acme.sh --renew --ecc --dns "$DNS_PROVIDER" -d "$DOMAIN" --force 2>&1 || true)
                        ;;
                esac
                
                if echo "$final_result" | grep -q "Success"; then
                    log "SUCCESS" "证书${operation_type}成功 (DNS API)"
                    return 0
                else
                    log "ERROR" "证书${operation_type}失败 (DNS API)"
                    echo "$final_result"
                    return 1
                fi
            else
                # 手动验证流程
                while true; do
                    read -p "是否已完成 DNS 记录添加？[y/N/q]: " dns_choice
                    case "$dns_choice" in
                        [Yy]*)
                            log "INFO" "用户确认已添加 DNS 记录，继续验证..."
                            
                            # 验证DNS记录
                            if verify_dns_record "${txt_domain#_acme-challenge.}" "$txt_value"; then
                                log "SUCCESS" "DNS 记录验证成功，继续证书操作..."
                                
                                # 继续执行证书验证
                                local final_result
                                case "$operation_type" in
                                    "renew")
                                        final_result=$(acme.sh --renew --ecc -d "$DOMAIN" 2>&1 || true)
                                        ;;
                                    "force_renew")
                                        final_result=$(acme.sh --renew --ecc -d "$DOMAIN" --force 2>&1 || true)
                                        ;;
                                esac
                                
                                if echo "$final_result" | grep -q "Success"; then
                                    log "SUCCESS" "证书${operation_type}成功 (手动验证)"
                                    return 0
                                else
                                    log "ERROR" "证书${operation_type}失败 (手动验证)"
                                    echo "$final_result"
                                    return 1
                                fi
                            else
                                log "WARN" "DNS 记录验证失败"
                                read -p "是否强制继续？[y/N]: " force_continue
                                if [[ "$force_continue" =~ ^[Yy]$ ]]; then
                                    log "INFO" "强制继续证书验证..."
                                    local final_result
                                    case "$operation_type" in
                                        "renew")
                                            final_result=$(acme.sh --renew --ecc -d "$DOMAIN" 2>&1 || true)
                                            ;;
                                        "force_renew")
                                            final_result=$(acme.sh --renew --ecc -d "$DOMAIN" --force 2>&1 || true)
                                            ;;
                                    esac
                                    
                                    if echo "$final_result" | grep -q "Success"; then
                                        log "SUCCESS" "证书${operation_type}成功 (强制执行)"
                                        return 0
                                    else
                                        log "ERROR" "证书${operation_type}失败 (强制执行)"
                                        echo "$final_result"
                                        return 1
                                    fi
                                fi
                            fi
                            ;;
                        [Qq]*)
                            log "INFO" "用户取消操作"
                            exit 0
                            ;;
                        *)
                            log "INFO" "请先添加 DNS 记录后再确认"
                            ;;
                    esac
                done
            fi
        else
            log "ERROR" "无法提取 DNS 记录信息"
            echo "$output"
            return 1
        fi
    else
        # 不需要手动DNS验证，检查其他结果
        if echo "$output" | grep -q "Success"; then
            log "SUCCESS" "证书${operation_type}成功"
            return 0
        else
            log "ERROR" "证书${operation_type}失败"
            echo "$output"
            return 1
        fi
    fi
}

# 续期证书
renew_certificate() {
    log "INFO" "开始续期证书: $DOMAIN"
    
    local renewal_output
    renewal_output=$(acme.sh --renew --ecc -d "$DOMAIN" 2>&1 || true)
    
    if echo "$renewal_output" | grep -q "Skipping"; then
        log "INFO" "证书尚未到续期时间"
        echo "$renewal_output" | grep -E "(Skip|Next renewal)"
        
        read -p "是否强制续期？[y/N]: " force_choice
        if [[ "$force_choice" =~ ^[Yy]$ ]]; then
            force_renew_certificate
        else
            log "INFO" "续期操作已跳过"
        fi
    else
        # 处理可能的DNS手动验证
        if ! handle_manual_dns_verification "$renewal_output" "renew"; then
            error_exit "证书续期失败"
        fi
    fi
}

# 强制更新证书
force_renew_certificate() {
    log "INFO" "强制更新证书: $DOMAIN"
    
    local renewal_output
    renewal_output=$(acme.sh --renew --ecc -d "$DOMAIN" --force 2>&1 || true)
    
    # 处理可能的DNS手动验证
    if ! handle_manual_dns_verification "$renewal_output" "force_renew"; then
        error_exit "证书强制更新失败"
    fi
}

# 创建证书目录
create_cert_directory() {
    if [[ ! -d "$CERT_DIR" ]]; then
        mkdir -p "$CERT_DIR"
        chmod 755 "$CERT_DIR"
        log "SUCCESS" "证书目录创建成功: $CERT_DIR"
    else
        log "INFO" "证书目录已存在: $CERT_DIR"
    fi
}

# 安装证书到 Nginx
install_certificate() {
    log "INFO" "安装证书到 Nginx..."
    
    create_cert_directory
    
    # 安装证书
    if acme.sh --install-cert -d "$DOMAIN" --ecc \
        --cert-file "$CERT_DIR/${DOMAIN}.cert.pem" \
        --key-file "$CERT_DIR/${DOMAIN}.key.pem" \
        --fullchain-file "$CERT_DIR/${DOMAIN}.fullchain.pem" \
        --reloadcmd "nginx -t && systemctl reload nginx"; then
        
        log "SUCCESS" "证书安装成功"
        log "INFO" "证书文件位置:"
        log "INFO" "  - 证书: $CERT_DIR/${DOMAIN}.cert.pem"
        log "INFO" "  - 私钥: $CERT_DIR/${DOMAIN}.key.pem"
        log "INFO" "  - 完整链: $CERT_DIR/${DOMAIN}.fullchain.pem"
    else
        error_exit "证书安装失败"
    fi
}

# 设置自动续期
setup_auto_renewal() {
    log "INFO" "设置自动续期..."
    
    # 检查是否已有crontab任务
    if crontab -l 2>/dev/null | grep -q "acme.sh"; then
        log "INFO" "自动续期已设置"
        return 0
    fi
    
    # 添加crontab任务
    local cron_job="0 2 * * * /usr/local/bin/acme.sh --cron --home /root/.acme.sh > /dev/null"
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    
    log "SUCCESS" "自动续期设置完成 (每天凌晨2点检查)"
}

# 显示证书信息
show_certificate_info() {
    if [[ -f "$CERT_DIR/${DOMAIN}.fullchain.pem" ]]; then
        log "INFO" "证书信息:"
        openssl x509 -in "$CERT_DIR/${DOMAIN}.fullchain.pem" -noout -dates -subject -issuer
        echo ""
        
        # 检查证书有效期
        local expiry_date
        expiry_date=$(openssl x509 -in "$CERT_DIR/${DOMAIN}.fullchain.pem" -noout -enddate | cut -d= -f2)
        local expiry_timestamp
        expiry_timestamp=$(date -d "$expiry_date" +%s)
        local current_timestamp
        current_timestamp=$(date +%s)
        local days_remaining
        days_remaining=$(( (expiry_timestamp - current_timestamp) / 86400 ))
        
        if [[ $days_remaining -gt 30 ]]; then
            log "SUCCESS" "证书还有 $days_remaining 天过期"
        elif [[ $days_remaining -gt 0 ]]; then
            log "WARN" "证书还有 $days_remaining 天过期，建议尽快续期"
        else
            log "ERROR" "证书已过期 $((days_remaining * -1)) 天"
        fi
    fi
}

# 主函数
main() {
    # 初始化
    welcome_message
    check_root
    check_dependencies
    
    # 创建日志文件
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    # 用户交互
    select_ca
    select_operation
    
    # 安装和配置
    install_acme
    set_ca
    
    # 执行操作
    case "$OPERATION" in
        "issue")
            issue_certificate
            install_certificate
            setup_auto_renewal
            ;;
        "renew")
            renew_certificate
            install_certificate
            ;;
        "force_renew")
            force_renew_certificate
            install_certificate
            ;;
    esac
    
    # 显示结果
    show_certificate_info
    
    echo ""
    log "SUCCESS" "所有操作完成！"
    log "INFO" "日志文件: $LOG_FILE"
    
    # 提供nginx配置示例
    echo -e "${YELLOW}${BOLD}Nginx 配置示例：${RESET}"
    echo -e "${CYAN}server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    
    ssl_certificate $CERT_DIR/${DOMAIN}.fullchain.pem;
    ssl_certificate_key $CERT_DIR/${DOMAIN}.key.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # Your site configuration...
}${RESET}"

    echo ""
    if [[ "$DNS_METHOD" == "api" ]]; then
        log "INFO" "已使用 DNS API 验证方式，后续续期将自动进行"
        log "INFO" "DNS API 提供商: $DNS_PROVIDER"
    else
        log "INFO" "已使用手动 DNS 验证方式"
        log "INFO" "如需自动化续期，建议配置 DNS API"
    fi
}

# 信号处理
trap 'error_exit "脚本被中断"' INT TERM

# 执行主函数
main "$@"
