#!/bin/bash
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
# 🔐 SSL 证书管理工具
# 支持 Let's Encrypt / ZeroSSL，DNS API/手动验证，ECC证书，自动部署并重载nginx
# By: BuBuXSY
# Version: 2026-07-11
# ====================================================

set -euo pipefail  # 严格模式

# 设置颜色和格式
readonly RED="\e[31m"
readonly GREEN="\e[32m"
readonly YELLOW="\e[33m"
readonly BLUE="\e[34m"
readonly CYAN="\e[36m"
readonly BOLD="\e[1m"
readonly RESET="\e[0m"

# 设置表情符号（兼容性更好的版本）
readonly SUCCESS="[✓]"
readonly ERROR="[✗]"
readonly INFO="[i]"
readonly WARNING="[!]"
readonly LOADING="[...]"

# 全局变量
CA_URL=""
DOMAIN=""
OPERATION=""
DNS_METHOD=""
DNS_PROVIDER=""
CERT_DIR="/etc/nginx/ssl"
LOG_FILE=""
ACME_HOME="/root/.acme.sh"
ACME_INSTALLER=""
ACME_INSTALL_LOG=""
ACME_SOURCE_DIR=""
ACME_SH_VERSION="${ACME_SH_VERSION:-3.1.3}"
ACME_SH_SHA256="${ACME_SH_SHA256:-}"
NGINX_RELOAD_MODE=""

# Verify that the running Nginx configuration uses the files acme.sh just
# installed.  A successful acme.sh install/reload alone is not sufficient:
# Nginx may still point at an older certificate path.
verify_nginx_certificate_deployment() {
    local cert_file="$1"
    local key_file="$2"
    local nginx_config

    if ! command -v nginx >/dev/null 2>&1; then
        log "WARN" "未找到 nginx，跳过活动配置证书路径校验"
        return 0
    fi

    if ! nginx_config=$(nginx -T 2>&1); then
        error_exit "无法读取 Nginx 活动配置，证书已写入但未确认生效"
    fi

    if ! awk -v expected="$cert_file;" '$1 == "ssl_certificate" && $2 == expected { found = 1 } END { exit !found }' <<< "$nginx_config" \
        || ! awk -v expected="$key_file;" '$1 == "ssl_certificate_key" && $2 == expected { found = 1 } END { exit !found }' <<< "$nginx_config"; then
        log "ERROR" "Nginx 活动配置没有引用刚部署的证书"
        log "INFO" "期望证书: $cert_file"
        log "INFO" "期望私钥: $key_file"
        log "INFO" "请将 ssl_certificate 和 ssl_certificate_key 指向上述文件后重新 reload"
        return 1
    fi

    log "SUCCESS" "Nginx 活动配置已引用新证书"
}

show_help() {
    cat <<EOF
SSL 证书自动化管理工具

用法: $0 [--help]

该工具使用交互式流程选择 CA、证书操作、域名和 DNS 验证方式。
签发、续期和部署证书需要 root 权限。
默认安装经过 SHA-256 固定的 acme.sh 3.1.3；覆盖 ACME_SH_VERSION 时必须同时提供 ACME_SH_SHA256。

选项:
  -h, --help    显示帮助信息
EOF
}

# 初始化日志文件路径
init_log_file() {
    if [[ $EUID -eq 0 ]]; then
        LOG_FILE="/var/log/acme-cert-tool.log"
        # 确保日志目录存在
        mkdir -p "$(dirname "$LOG_FILE")"
    else
        LOG_FILE="$HOME/acme-cert-tool.log"
        # 如果家目录不可写，使用临时目录
        if [[ ! -w "$HOME" ]]; then
            LOG_FILE="/tmp/acme-cert-tool-$(id -u).log"
        fi
    fi
    
    if [[ -L "$LOG_FILE" ]]; then
        echo "❌ 日志路径不能是符号链接: $LOG_FILE" >&2
        exit 1
    fi

    # 创建日志文件；回退路径使用 mktemp，避免可预测文件名和符号链接攻击。
    if ! touch "$LOG_FILE" 2>/dev/null; then
        LOG_FILE=$(umask 077; mktemp /tmp/acme-cert-tool.XXXXXX.log) || {
            echo "❌ 无法创建安全日志文件" >&2
            exit 1
        }
    fi
    chmod 0600 "$LOG_FILE" 2>/dev/null || {
        echo "❌ 无法设置日志文件权限: $LOG_FILE" >&2
        exit 1
    }
}

# 日志函数
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 写入日志文件
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    
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
    echo ""
    log "INFO" "日志文件: $LOG_FILE"
    exit 1
}

# 显示欢迎信息
welcome_message() {
    if [[ -t 1 ]] && command -v clear >/dev/null 2>&1; then
        clear || true
    fi
    echo -e "${CYAN}${BOLD}============================================================${RESET}"
    echo -e "${CYAN}${BOLD}          ACME SSL证书自动化管理工具                        ${RESET}"
    echo -e "${CYAN}${BOLD}          支持多CA和自动化部署                              ${RESET}"
    echo -e "${CYAN}${BOLD}============================================================${RESET}"
    echo ""
    log "INFO" "工具启动，支持 Let's Encrypt 与 ZeroSSL"
    echo ""
}

# 检测操作系统
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS="${NAME:-Linux}"
    elif [[ -f /etc/redhat-release ]]; then
        OS=$(cat /etc/redhat-release | cut -d' ' -f1)
    else
        OS=$(uname -s)
    fi
    log "INFO" "检测到操作系统: $OS"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}${ERROR} 此脚本需要root权限运行${RESET}"
        echo -e "${YELLOW}请使用以下命令之一：${RESET}"
        echo -e "  ${CYAN}sudo $0${RESET}"
        echo -e "  ${CYAN}su - root -c '$0'${RESET}"
        exit 1
    fi
    
    log "SUCCESS" "Root权限检查通过"
}

# 安装包管理器检测
get_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

# 安装依赖
install_dependencies() {
    local pkg_manager
    pkg_manager=$(get_package_manager)
    
    case $pkg_manager in
        "apt")
            apt-get update -y
            apt-get install -y curl dnsutils openssl cron tar coreutils grep gawk
            ;;
        "yum"|"dnf")
            "$pkg_manager" install -y curl bind-utils openssl cronie tar coreutils grep gawk
            if command -v systemctl >/dev/null 2>&1; then
                systemctl enable --now crond >/dev/null 2>&1 || log "WARN" "crond 启动失败，请稍后手动检查"
            fi
            ;;
        "pacman")
            pacman -Sy --noconfirm curl bind-tools openssl cronie tar coreutils grep gawk
            if command -v systemctl >/dev/null 2>&1; then
                systemctl enable --now cronie >/dev/null 2>&1 || log "WARN" "cronie 启动失败，请稍后手动检查"
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

# 检查系统依赖
check_dependencies() {
    local deps=("curl" "openssl" "tar" "sha256sum" "mktemp" "awk" "grep")
    local missing=()
    
    # 检查dig命令（不同系统命令名可能不同）
    if ! command -v dig >/dev/null 2>&1 && ! command -v nslookup >/dev/null 2>&1; then
        missing+=("dnsutils")
    fi
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "WARN" "缺少依赖: ${missing[*]}"
        echo -e "${YELLOW}是否自动安装缺少的依赖？[Y/n]:${RESET} "
        read -r install_deps
        install_deps=${install_deps:-Y}
        
        if [[ "$install_deps" =~ ^[Yy]$ ]]; then
            log "INFO" "正在安装依赖包..."
            install_dependencies || error_exit "依赖自动安装失败，请手动安装: curl, dig/nslookup, openssl, tar, coreutils, grep, awk"
            local dep
            for dep in curl openssl tar sha256sum mktemp awk grep; do
                command -v "$dep" >/dev/null 2>&1 || error_exit "依赖安装后仍缺少命令: $dep"
            done
            if ! command -v dig >/dev/null 2>&1 && ! command -v nslookup >/dev/null 2>&1; then
                error_exit "依赖安装后仍缺少 DNS 查询命令（dig/nslookup）"
            fi
            log "SUCCESS" "依赖安装完成并通过复检"
        else
            error_exit "缺少必要依赖，无法继续"
        fi
    else
        log "SUCCESS" "系统依赖检查通过"
    fi
}

# 显示进度条
show_progress() {
    local pid=$1
    local message="$2"
    local chars="/-\\|"
    local i=0
    
    echo -n "$message "
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r$message ${LOADING} %c" "${chars:$((i%4)):1}"
        sleep 0.2
        i=$((i + 1))
    done
    echo -e "\r$message ${SUCCESS}"
}

# 选择 CA 供应商
select_ca() {
    echo -e "${GREEN}${BOLD}请选择 CA 供应商：${RESET}"
    echo -e "  ${BLUE}1)${RESET} Let's Encrypt (免费，推荐)"
    echo -e "  ${BLUE}2)${RESET} ZeroSSL (免费，90天)"
    echo ""
    
    while true; do
        echo -n "请选择 [1-2] (默认: 1): "
        read -r ca_choice
        ca_choice=${ca_choice:-1}
        
        case $ca_choice in
            1)
                CA_URL="https://acme-v02.api.letsencrypt.org/directory"
                log "SUCCESS" "选择了 Let's Encrypt 作为 CA"
                break
                ;;
            2)
                CA_URL="https://acme.zerossl.com/v2/DV90"
                while [[ -z "${ACME_EMAIL:-}" || ! "$ACME_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; do
                    echo -n "ZeroSSL 需要账户邮箱，请输入 ACME_EMAIL: "
                    read -r ACME_EMAIL
                    if [[ ! "$ACME_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
                        log "WARN" "邮箱格式无效，请重新输入"
                    fi
                done
                export ACME_EMAIL
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
    # 改进的域名格式验证
    if [[ "$domain" =~ ^(\*\.)?[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        # 检查域名长度
        if [[ ${#domain} -le 253 ]]; then
            return 0
        fi
    fi
    return 1
}

# 获取域名输入
get_domain_input() {
    while true; do
        echo -n "请输入域名 (例如: example.com 或 *.example.com): "
        read -r domain_input
        
        if [[ -z "$domain_input" ]]; then
            log "WARN" "域名不能为空"
            continue
        fi
        
        if validate_domain "$domain_input"; then
            DOMAIN="$domain_input"
            log "SUCCESS" "域名格式验证通过: $DOMAIN"
            break
        else
            log "WARN" "域名格式不正确，请重新输入"
        fi
    done
}

# 选择DNS验证方式
select_dns_method() {
    echo -e "${GREEN}${BOLD}请选择 DNS 验证方式：${RESET}"
    echo -e "  ${BLUE}1)${RESET} 手动添加 DNS 记录"
    echo -e "  ${BLUE}2)${RESET} 使用 DNS API 自动验证"
    echo ""
    
    while true; do
        echo -n "请选择 [1-2] (默认: 1): "
        read -r dns_method_choice
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
    echo -e "${GREEN}${BOLD}请选择 DNS 服务商：${RESET}"
    echo -e "  ${BLUE}1)${RESET} 阿里云 DNS (dns_ali)"
    echo -e "  ${BLUE}2)${RESET} 腾讯云 DNS (dns_tencent)" 
    echo -e "  ${BLUE}3)${RESET} Cloudflare (dns_cf)"
    echo -e "  ${BLUE}4)${RESET} DNSPod (dns_dp)"
    echo -e "  ${BLUE}5)${RESET} 华为云 DNS (dns_huaweicloud)"
    echo -e "  ${BLUE}6)${RESET} 其他服务商"
    echo ""
    
    while true; do
        echo -n "请选择 [1-6]: "
        read -r dns_provider_choice
        
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
    
    echo -n "请输入 AccessKey ID: "
    read -r ali_key
    echo -n "请输入 AccessKey Secret (输入不可见): "
    read -rs ali_secret
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
    
    echo -n "请输入 SecretId: "
    read -r tencent_id
    echo -n "请输入 SecretKey (输入不可见): "
    read -rs tencent_key
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
    
    echo -n "请输入 API Token (输入不可见): "
    read -rs cf_token
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
    
    echo -n "请输入 API ID: "
    read -r dp_id
    echo -n "请输入 API Key (输入不可见): "
    read -rs dp_key
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
    
    echo -n "请输入 Access Key: "
    read -r huawei_key
    echo -n "请输入 Secret Key (输入不可见): "
    read -rs huawei_secret
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
    echo -n "请输入 DNS API 名称 (例如: dns_gd): "
    read -r custom_dns
    
    if [[ ! "$custom_dns" =~ ^dns_[A-Za-z0-9_]+$ ]]; then
        error_exit "DNS API 名称格式无效，应类似 dns_gd"
    fi
    
    DNS_PROVIDER="$custom_dns"
    log "INFO" "请根据 acme.sh 文档配置对应的环境变量"
    log "INFO" "文档地址：https://github.com/acmesh-official/acme.sh/wiki/dnsapi"
    
    echo -n "按 [Enter] 继续，确保已配置好相关环境变量..."
    read -r
}

# 选择操作类型
select_operation() {
    echo -e "${GREEN}${BOLD}请选择操作类型：${RESET}"
    echo -e "  ${BLUE}1)${RESET} 申请新证书"
    echo -e "  ${BLUE}2)${RESET} 续期现有证书"
    echo -e "  ${BLUE}3)${RESET} 强制更新证书"
    echo -e "  ${BLUE}4)${RESET} 查看现有证书"
    echo ""
    
    while true; do
        echo -n "请选择 [1-4]: "
        read -r operation_choice
        
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
                echo ""
                ;;
            *)
                log "WARN" "无效选择，请重新输入"
                ;;
        esac
    done
}

# 检查现有证书
check_existing_cert() {
    if command -v acme.sh >/dev/null 2>&1; then
        local existing
        existing=$(acme.sh --list 2>/dev/null | grep -w "$DOMAIN" || true)
        if [[ -n "$existing" ]]; then
            log "WARN" "域名 $DOMAIN 已存在证书"
            echo -e "${YELLOW}现有证书信息：${RESET}"
            echo "$existing"
            echo ""
            echo -n "是否继续？这将覆盖现有证书 [y/N]: "
            read -r continue_choice
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
    if command -v acme.sh >/dev/null 2>&1; then
        local cert_list
        cert_list=$(acme.sh --list 2>/dev/null || true)
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
    if ! command -v acme.sh >/dev/null 2>&1; then
        error_exit "acme.sh 未安装，无法操作现有证书"
    fi
    
    local domains
    domains=$(acme.sh --list 2>/dev/null | awk 'NR>1 {print $1}' | grep -v "^$" || true)
    
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
        echo -n "请选择域名 [1-$((i-1))]: "
        read -r domain_choice
        
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
    if command -v acme.sh >/dev/null 2>&1; then
        log "SUCCESS" "acme.sh 已安装"
        return 0
    fi
    
    log "INFO" "开始安装 acme.sh..."
    
    if [[ ! "$ACME_SH_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error_exit "ACME_SH_VERSION 格式无效: $ACME_SH_VERSION"
    fi
    if [[ -z "$ACME_SH_SHA256" ]]; then
        if [[ "$ACME_SH_VERSION" == "3.1.3" ]]; then
            ACME_SH_SHA256="efd12b265252f8875269960b6b31830731ccce2b3e6ff8e7ecfbee21fde35ab4"
        else
            error_exit "覆盖 ACME_SH_VERSION 时必须同时提供 ACME_SH_SHA256"
        fi
    fi
    ACME_SH_SHA256="${ACME_SH_SHA256,,}"
    [[ "$ACME_SH_SHA256" =~ ^[0-9a-f]{64}$ ]] \
        || error_exit "ACME_SH_SHA256 必须是 64 位十六进制摘要"

    ACME_INSTALLER=$(mktemp /tmp/acme-sh.XXXXXX.tar.gz) \
        || error_exit "无法创建临时归档文件"
    ACME_INSTALL_LOG=$(mktemp /tmp/acme-installer-log.XXXXXX) \
        || error_exit "无法创建临时日志文件"
    ACME_SOURCE_DIR=$(mktemp -d /tmp/acme-source.XXXXXX) \
        || error_exit "无法创建临时源码目录"

    if ! curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 \
        "https://codeload.github.com/acmesh-official/acme.sh/tar.gz/refs/tags/${ACME_SH_VERSION}" \
        -o "$ACME_INSTALLER"; then
        error_exit "acme.sh ${ACME_SH_VERSION} 源码归档下载失败"
    fi
    local actual_sha256
    actual_sha256=$(sha256sum "$ACME_INSTALLER" | awk '{print tolower($1)}')
    [[ "$actual_sha256" == "$ACME_SH_SHA256" ]] \
        || error_exit "acme.sh 归档 SHA-256 不匹配，已拒绝执行"

    local archive_list
    archive_list=$(tar -tzf "$ACME_INSTALLER" 2>/dev/null) \
        || error_exit "acme.sh 源码归档损坏"
    if grep -Eq '(^/|(^|/)\.\.(/|$))' <<< "$archive_list"; then
        error_exit "acme.sh 源码归档包含不安全路径"
    fi
    if grep -Ev "^acme\.sh-${ACME_SH_VERSION}(/|$)" <<< "$archive_list" | grep -q .; then
        error_exit "acme.sh 源码归档目录结构异常"
    fi
    tar -xzf "$ACME_INSTALLER" -C "$ACME_SOURCE_DIR" \
        || error_exit "acme.sh 源码归档解压失败"

    local acme_source="$ACME_SOURCE_DIR/acme.sh-${ACME_SH_VERSION}/acme.sh"
    [[ -f "$acme_source" ]] || error_exit "acme.sh 主脚本不存在"
    grep -Fxq "VER=${ACME_SH_VERSION}" "$acme_source" \
        || error_exit "acme.sh 主脚本版本与归档标签不一致"
    grep -Fq 'PROJECT="https://github.com/acmesh-official/$PROJECT_NAME"' "$acme_source" \
        || error_exit "acme.sh 主脚本来源标识异常"

    local install_pid
    local install_args=(--install --home "$ACME_HOME")
    if [[ -n "${ACME_EMAIL:-}" ]]; then
        install_args+=(--email "$ACME_EMAIL")
        sh "$acme_source" "${install_args[@]}" >"$ACME_INSTALL_LOG" 2>&1 &
    else
        log "WARN" "未设置 ACME_EMAIL，将使用 acme.sh 默认账户注册流程"
        sh "$acme_source" "${install_args[@]}" >"$ACME_INSTALL_LOG" 2>&1 &
    fi
    install_pid=$!
    show_progress "$install_pid" "正在安装 acme.sh"
    if ! wait "$install_pid"; then
        tail -n 20 "$ACME_INSTALL_LOG" >&2 || true
        error_exit "acme.sh 安装失败"
    fi
    
    # 创建软链接
    if [[ -f "$ACME_HOME/acme.sh" ]]; then
        ln -sf "$ACME_HOME/acme.sh" /usr/local/bin/acme.sh
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
    local directory_json
    if ! directory_json=$(curl -fsSL --retry 2 --connect-timeout 8 --max-time 20 "$CA_URL") \
        || ! grep -q '"newNonce"' <<< "$directory_json" \
        || ! grep -q '"newAccount"' <<< "$directory_json" \
        || ! grep -q '"newOrder"' <<< "$directory_json"; then
        error_exit "所选 CA 的 ACME Directory 不可用或响应格式异常: $CA_URL"
    fi
    if ! acme.sh --set-default-ca --server "$CA_URL" >/dev/null 2>&1; then
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
            local result
            if command -v dig >/dev/null 2>&1; then
                result=$(dig @"$dns_server" +short TXT "_acme-challenge.$domain" 2>/dev/null | tr -d '"' || true)
            elif command -v nslookup >/dev/null 2>&1; then
                result=$(nslookup -type=TXT "_acme-challenge.$domain" "$dns_server" 2>/dev/null | grep -v "^$" | tail -1 | cut -d'"' -f2 || true)
            fi
            
            if [[ "$result" == *"$txt_value"* ]]; then
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
        
        log "INFO" "等待 DNS 记录生效... ($((max_attempts - attempt)) 次重试剩余)"
        sleep 10
        ((attempt++))
    done
}

# 申请证书 - 修复版
issue_certificate() {
    log "INFO" "开始申请证书: $DOMAIN"
    
    if [[ "$DNS_METHOD" == "api" ]]; then
        # 使用 DNS API 自动验证
        log "INFO" "使用 DNS API 自动验证: $DNS_PROVIDER"
        
        if acme.sh --issue --dns "$DNS_PROVIDER" --keylength ec-256 -d "$DOMAIN" >/dev/null 2>&1; then
            log "SUCCESS" "证书申请成功（DNS API 验证）"
        else
            error_exit "证书申请失败（DNS API 验证）"
        fi
    else
        # 手动 DNS 验证需要先生成 TXT，再在记录生效后执行 renew 完成签发。
        log "INFO" "使用手动 DNS 验证方式"
        log "INFO" "第一步将显示需要添加的 DNS TXT 记录"
        
        echo ""
        echo -e "${YELLOW}${BOLD}注意：接下来 acme.sh 会显示需要添加的DNS记录信息${RESET}"
        echo -e "${YELLOW}请在DNS控制台添加显示的TXT记录，然后按提示继续${RESET}"
        echo ""
        echo -n "按 [Enter] 生成 DNS 验证记录..."
        read -r

        acme.sh --issue --dns -d "$DOMAIN" --keylength ec-256 \
            --yes-I-know-dns-manual-mode-enough-go-ahead-please || true

        echo ""
        echo -e "${YELLOW}请添加上方 TXT 记录并等待 DNS 生效。${RESET}"
        echo -n "记录生效后按 [Enter] 继续签发..."
        read -r
        if acme.sh --renew --ecc -d "$DOMAIN" \
            --yes-I-know-dns-manual-mode-enough-go-ahead-please; then
            log "SUCCESS" "证书申请成功（手动 DNS 验证）"
        else
            error_exit "证书申请失败，请确认 TXT 记录已生效"
        fi
    fi
}

# 续期证书 - 修复版
renew_certificate() {
    log "INFO" "开始续期证书: $DOMAIN"
    
    local renewal_output
    if renewal_output=$(acme.sh --renew --ecc -d "$DOMAIN" 2>&1); then
        if ! echo "$renewal_output" | grep -qi "skip"; then
            log "SUCCESS" "证书续期成功"
            return 0
        fi

        log "INFO" "证书尚未到续期时间"
        echo "$renewal_output" | grep -Ei "(skip|next renewal)" || true
        
        echo -n "是否强制续期？[y/N]: "
        read -r force_choice
        if [[ "$force_choice" =~ ^[Yy]$ ]]; then
            force_renew_certificate
        else
            log "INFO" "续期操作已跳过"
        fi
    else
        # 检查是否需要手动DNS验证
        if echo "$renewal_output" | grep -q "dns manual mode" || [[ "$DOMAIN" == \*.* ]]; then
            log "INFO" "需要手动DNS验证进行续期"
            
            # 检查证书配置
            local cert_conf="$ACME_HOME/${DOMAIN}_ecc/${DOMAIN}.conf"
            if [[ -f "$cert_conf" ]] && grep -q "Le_Webroot='dns'" "$cert_conf" 2>/dev/null; then
                log "INFO" "使用手动DNS验证续期"
                echo ""
                echo -e "${YELLOW}${BOLD}注意：需要重新添加DNS验证记录${RESET}"
                echo -n "按 [Enter] 继续..."
                read -r
                
                if acme.sh --renew --ecc -d "$DOMAIN" --yes-I-know-dns-manual-mode-enough-go-ahead-please; then
                    log "SUCCESS" "证书续期成功（手动DNS验证）"
                else
                    error_exit "证书续期失败（手动DNS验证）"
                fi
            else
                error_exit "证书续期失败，请检查配置或重新申请证书"
            fi
        else
            error_exit "证书续期失败"
        fi
    fi
}

# 强制续期证书 - 修复版
force_renew_certificate() {
    log "INFO" "强制更新证书: $DOMAIN"
    
    # 检查证书配置文件，确定验证方式
    local cert_conf="$ACME_HOME/${DOMAIN}_ecc/${DOMAIN}.conf"
    local dns_api_provider=""
    
    if [[ -f "$cert_conf" ]]; then
        # 检查是否使用DNS API
        if grep -q "Le_Webroot='dns_" "$cert_conf" 2>/dev/null; then
            dns_api_provider=$(grep "Le_Webroot=" "$cert_conf" | cut -d"'" -f2)
            log "INFO" "检测到原证书使用DNS API: $dns_api_provider"
        elif grep -q "Le_Webroot='dns'" "$cert_conf" 2>/dev/null; then
            log "INFO" "检测到原证书使用手动DNS验证"
        fi
    fi
    
    if [[ -n "$dns_api_provider" && "$dns_api_provider" != "dns" ]]; then
        # 使用DNS API强制续期
        log "INFO" "使用DNS API强制续期: $dns_api_provider"
        if acme.sh --renew --ecc -d "$DOMAIN" --force >/dev/null 2>&1; then
            log "SUCCESS" "证书强制更新成功（DNS API）"
        else
            error_exit "证书强制更新失败（DNS API）"
        fi
    elif [[ "$DOMAIN" == \*.* ]] || (grep -q "Le_Webroot='dns'" "$cert_conf" 2>/dev/null); then
        # 通配符域名或手动DNS验证，使用手动DNS验证强制续期
        log "INFO" "使用手动DNS验证强制续期"
        log "INFO" "这将是一个交互式过程，请按 acme.sh 提示操作"
        
        echo ""
        echo -e "${YELLOW}${BOLD}注意：需要重新添加DNS验证记录${RESET}"
        echo -n "按 [Enter] 继续..."
        read -r
        
        # 修复：使用正确的手动DNS验证强制续期命令
        if acme.sh --renew --ecc -d "$DOMAIN" --force --yes-I-know-dns-manual-mode-enough-go-ahead-please; then
            log "SUCCESS" "证书强制更新成功（手动DNS验证）"
        else
            error_exit "证书强制更新失败（手动DNS验证）"
        fi
    else
        # 非通配符域名，可以使用HTTP验证
        if acme.sh --renew --ecc -d "$DOMAIN" --force >/dev/null 2>&1; then
            log "SUCCESS" "证书强制更新成功"
        else
            error_exit "证书强制更新失败"
        fi
    fi
}

# 创建证书目录
create_cert_directory() {
    if [[ -e "$CERT_DIR" && ! -d "$CERT_DIR" || -L "$CERT_DIR" ]]; then
        error_exit "证书目录必须是非符号链接目录: $CERT_DIR"
    fi
    if [[ ! -d "$CERT_DIR" ]]; then
        mkdir -p -- "$CERT_DIR" || error_exit "无法创建证书目录: $CERT_DIR"
        log "SUCCESS" "证书目录创建成功: $CERT_DIR"
    fi
    chmod 0750 -- "$CERT_DIR" || error_exit "无法收紧证书目录权限: $CERT_DIR"
    [[ "$(stat -c '%a' -- "$CERT_DIR" 2>/dev/null || stat -f '%Lp' -- "$CERT_DIR")" =~ ^(700|750)$ ]] \
        || error_exit "证书目录权限不安全: $CERT_DIR"
}

# 检查nginx状态
check_nginx() {
    NGINX_RELOAD_MODE=""
    if ! command -v nginx >/dev/null 2>&1; then
        log "WARN" "未检测到 Nginx，证书将安装但不会重载服务"
        return 1
    fi

    if command -v systemctl >/dev/null 2>&1 \
        && systemctl is-active --quiet nginx >/dev/null 2>&1; then
        NGINX_RELOAD_MODE="systemd"
        return 0
    fi

    if command -v pgrep >/dev/null 2>&1 && pgrep -x nginx >/dev/null 2>&1; then
        NGINX_RELOAD_MODE="signal"
        if command -v systemctl >/dev/null 2>&1; then
            log "WARN" "nginx.service 未运行，但检测到 Nginx 进程，将使用 nginx -s reload"
        fi
        return 0
    else
        log "WARN" "Nginx 进程未运行"
        return 1
    fi
}

# 安装证书到 Nginx
install_certificate() {
    log "INFO" "安装证书到 Nginx..."
    
    create_cert_directory
    
    local reload_cmd=""
    if check_nginx; then
        case "$NGINX_RELOAD_MODE" in
            systemd) reload_cmd="nginx -t && (systemctl reload nginx || nginx -s reload)" ;;
            signal)  reload_cmd="nginx -t && nginx -s reload" ;;
        esac
    fi

    local install_args=(
        --install-cert -d "$DOMAIN" --ecc
        --cert-file "$CERT_DIR/${DOMAIN}.cert.pem"
        --key-file "$CERT_DIR/${DOMAIN}.key.pem"
        --fullchain-file "$CERT_DIR/${DOMAIN}.fullchain.pem"
    )
    [[ -n "$reload_cmd" ]] && install_args+=(--reloadcmd "$reload_cmd")

    # 安装证书
    if acme.sh "${install_args[@]}" >/dev/null 2>&1; then
        local cert_file="$CERT_DIR/${DOMAIN}.cert.pem" key_file="$CERT_DIR/${DOMAIN}.key.pem" fullchain_file="$CERT_DIR/${DOMAIN}.fullchain.pem"
        [[ -f "$cert_file" && -f "$key_file" && -f "$fullchain_file" ]] || error_exit "acme.sh 未生成完整证书文件"
        [[ ! -L "$cert_file" && ! -L "$key_file" && ! -L "$fullchain_file" ]] || error_exit "证书文件不能是符号链接"
        chmod 0644 "$cert_file" "$fullchain_file" || error_exit "无法设置证书文件权限"
        chmod 0600 "$key_file" || error_exit "无法设置私钥权限"
        [[ "$(stat -c '%a' "$key_file" 2>/dev/null || stat -f '%Lp' "$key_file")" == 600 ]] || error_exit "私钥权限验证失败"
        verify_nginx_certificate_deployment "$fullchain_file" "$key_file" \
            || error_exit "证书已部署，但 Nginx 仍未使用该证书"
        log "SUCCESS" "证书安装成功"
        log "INFO" "证书文件位置: $cert_file"
        log "INFO" "私钥文件位置: $key_file"
        log "INFO" "完整链文件位置: $fullchain_file"
    else
        error_exit "证书安装失败"
    fi
}

# 设置自动续期
setup_auto_renewal() {
    log "INFO" "设置自动续期..."

    command -v crontab >/dev/null 2>&1 || error_exit "未找到 crontab，无法设置自动续期"
    local existing_crontab
    existing_crontab=$(crontab -l 2>/dev/null || true)

    # 检查是否已有crontab任务
    if grep -Fq "acme.sh" <<< "$existing_crontab"; then
        log "INFO" "自动续期已设置"
        return 0
    fi

    # 添加 crontab任务
    local cron_job="0 2 * * * /usr/local/bin/acme.sh --cron --home $ACME_HOME >/dev/null 2>&1"
    { [[ -z "$existing_crontab" ]] || printf '%s\n' "$existing_crontab"; printf '%s\n' "$cron_job"; } | crontab -
    
    log "SUCCESS" "自动续期设置完成 (每天凌晨2点检查)"
}

# 显示证书信息
show_certificate_info() {
    if [[ -f "$CERT_DIR/${DOMAIN}.fullchain.pem" ]]; then
        echo ""
        log "INFO" "证书信息:"
        openssl x509 -in "$CERT_DIR/${DOMAIN}.fullchain.pem" -noout -dates -subject -issuer 2>/dev/null || {
            log "WARN" "无法读取证书信息"
            return
        }
        echo ""
        
        # 检查证书有效期
        local expiry_date
        expiry_date=$(openssl x509 -in "$CERT_DIR/${DOMAIN}.fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        if [[ -n "$expiry_date" ]]; then
            local expiry_timestamp current_timestamp days_remaining
            expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null || true)
            if [[ ! "$expiry_timestamp" =~ ^[0-9]+$ ]] || [[ "$expiry_timestamp" -eq 0 ]]; then
                log "WARN" "无法解析证书过期时间: $expiry_date"
                return
            fi
            current_timestamp=$(date +%s)
            days_remaining=$(( (expiry_timestamp - current_timestamp) / 86400 ))
            
            if [[ $days_remaining -gt 30 ]]; then
                log "SUCCESS" "证书还有 $days_remaining 天过期"
            elif [[ $days_remaining -gt 0 ]]; then
                log "WARN" "证书还有 $days_remaining 天过期，建议尽快续期"
            else
                log "ERROR" "证书已过期 $((days_remaining * -1)) 天"
            fi
        fi
    fi
}

# 显示nginx配置示例
show_nginx_config_example() {
    echo ""
    echo -e "${YELLOW}${BOLD}Nginx 配置示例：${RESET}"
    printf '%b' "$CYAN"
    cat <<EOF
server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    
    ssl_certificate $CERT_DIR/${DOMAIN}.fullchain.pem;
    ssl_certificate_key $CERT_DIR/${DOMAIN}.key.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    
    # 安全头部
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    
    # 网站配置...
    location / {
        # 您的网站配置
    }
}

# HTTP 重定向到 HTTPS
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}
EOF
    printf '%b\n' "$RESET"
}

# 主函数
main() {
    if [[ $# -gt 0 ]]; then
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}${ERROR} 未知参数: $1${RESET}" >&2
                show_help >&2
                exit 2
                ;;
        esac
    fi

    # 初始化
    init_log_file
    welcome_message
    check_root
    detect_os
    check_dependencies
    
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
            if [[ "$DNS_METHOD" == "api" ]]; then
                setup_auto_renewal
            else
                log "WARN" "手动 DNS 验证不能可靠自动续期，未安装 acme.sh 自动续期任务"
                log "INFO" "如需无人值守续期，请重新申请并选择 DNS API"
            fi
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
    show_nginx_config_example
    
    echo ""
    log "SUCCESS" "所有操作完成！"
    log "INFO" "日志文件: $LOG_FILE"
    
    echo ""
    if [[ "$OPERATION" == "issue" ]]; then
        if [[ "$DNS_METHOD" == "api" ]]; then
            log "INFO" "已使用 DNS API 验证方式，后续续期将自动进行"
            log "INFO" "DNS API 提供商: $DNS_PROVIDER"
        else
            log "INFO" "已使用手动 DNS 验证方式"
            log "INFO" "如需自动化续期，建议配置 DNS API"
        fi
    else
        log "INFO" "现有证书操作完成: $DOMAIN"
    fi
    
    echo -e "${GREEN}感谢使用 SSL 证书自动化管理工具！${RESET}"
}

# 信号处理
cleanup() {
    [[ -n "$ACME_INSTALLER" ]] && rm -f "$ACME_INSTALLER"
    [[ -n "$ACME_INSTALL_LOG" ]] && rm -f "$ACME_INSTALL_LOG"
    [[ -n "$ACME_SOURCE_DIR" ]] && rm -rf "$ACME_SOURCE_DIR"
    return 0
}

trap cleanup EXIT
trap 'error_exit "脚本被中断"' INT TERM

# 执行主函数
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
