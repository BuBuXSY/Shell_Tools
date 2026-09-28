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
# 🧠 MOSDNS 重复域名监控辅助脚本
# 功能: 监控mosdns查询日志，检测重复域名并生成，最后会添加在规则里面辅助减少mosdns对重复域名的查询，重复次数很多的域名服务器直接TTL最大。
# 依赖: mosdns 日志文件
# By: BuBuXSY
# Version: 2026-07-11
# ====================================================



set -euo pipefail  # 严格模式：遇到错误立即退出

TEMP_FILES=()
EXTRACTED_DOMAINS_FILE=""
EXTRACTED_STATS_FILE=""

# ==== 配置文件加载 ====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${DNS_MONITOR_CONFIG:-${SCRIPT_DIR}/dns_monitor.conf}"
PLAN_ONLY=false

# 默认配置
DEFAULT_DOMAIN_FILE="/etc/mosdns/mosdns.log"
DEFAULT_OUTPUT_FILE="/etc/mosdns/rules/repeat_domain.txt"
DEFAULT_THRESHOLD=500
DEFAULT_LOG_FILE="/var/log/dns_monitor.log"
DEFAULT_HISTORY_FILE="/var/log/dns_monitor_history.json"
DEFAULT_MAX_LOG_SIZE="100M"
LOCK_FILE="${DNS_MONITOR_LOCK_FILE:-/run/lock/collect_repeat_dns.lock}"
LOCK_FD=9
LOCK_DIR="${LOCK_FILE}.d"
LOCK_MODE=''

# 仅解析受限的 KEY=VALUE 纯文本；绝不执行配置内容。
parse_config_value() {
    local key="$1" value="$2"
    case "$key" in
        DOMAIN_FILE|OUTPUT_FILE|LOG_FILE|HISTORY_FILE|LOCK_FILE|MAX_LOG_SIZE|EMAIL_TO|EMAIL_SUBJECT|WECHAT_WEBHOOK_URL) ;;
        THRESHOLD) [[ "$value" =~ ^[0-9]+$ ]] || return 1 ;;
        ENABLE_WECHAT_NOTIFY|ENABLE_EMAIL_NOTIFY|ENABLE_HISTORY|ENABLE_STATS|WHITELIST_ONLY|TRUNCATE_SOURCE_LOG) [[ "$value" == true || "$value" == false ]] || return 1 ;;
        BLACKLIST_DOMAINS) ;;
        *) return 1 ;;
    esac
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *';'* && "$value" != *'`'* && "$value" != *'$('* ]] || return 1
    case "$key" in
        BLACKLIST_DOMAINS) BLACKLIST_DOMAINS+=("$value") ;;
        *) printf -v "$key" '%s' "$value" ;;
    esac
}

load_config() {
    : "${DOMAIN_FILE:=$DEFAULT_DOMAIN_FILE}"; : "${OUTPUT_FILE:=$DEFAULT_OUTPUT_FILE}"
    : "${THRESHOLD:=$DEFAULT_THRESHOLD}"; : "${LOG_FILE:=$DEFAULT_LOG_FILE}"
    : "${HISTORY_FILE:=$DEFAULT_HISTORY_FILE}"; : "${MAX_LOG_SIZE:=$DEFAULT_MAX_LOG_SIZE}"
    : "${LOCK_FILE:=${DNS_MONITOR_LOCK_FILE:-/run/lock/collect_repeat_dns.lock}}"
    BLACKLIST_DOMAINS=(localhost '*.local' '*.test')
    if [[ -e "$CONFIG_FILE" ]]; then
        [[ -f "$CONFIG_FILE" && ! -L "$CONFIG_FILE" && -r "$CONFIG_FILE" ]] || { log_error "配置必须是可读的普通文件且不能是符号链接: $CONFIG_FILE"; exit 1; }
        local line key value lineno=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            lineno=$((lineno + 1)); line="${line%%#*}"
            [[ -z "${line//[[:space:]]/}" ]] && continue
            if [[ "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$ ]]; then
                key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
                if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then value="${BASH_REMATCH[1]}"; fi
                parse_config_value "$key" "$value" || { log_error "配置第 $lineno 行无效或包含不安全内容: $key"; exit 1; }
            else
                log_error "配置第 $lineno 行语法无效；请使用纯文本 KEY=VALUE 格式"; exit 1
            fi
        done < "$CONFIG_FILE"
        log_info "配置文件已加载: $CONFIG_FILE"
    elif [[ "${DNS_MONITOR_CREATE_CONFIG:-false}" == true ]]; then
        log_warn "配置文件不存在，使用默认配置"; create_default_config
    else
        log_warn "配置文件不存在，使用默认配置（不会自动写入系统路径）"
    fi
    [[ "$THRESHOLD" =~ ^[0-9]+$ ]] || { log_error "THRESHOLD 必须是非负整数"; exit 1; }
    THRESHOLD=$((10#$THRESHOLD))
}

# 创建默认配置文件
create_default_config() {
    if ! cat > "$CONFIG_FILE" << EOF
# DNS监控配置文件
DOMAIN_FILE="$DEFAULT_DOMAIN_FILE"
OUTPUT_FILE="$DEFAULT_OUTPUT_FILE"
THRESHOLD=$DEFAULT_THRESHOLD
LOG_FILE="$DEFAULT_LOG_FILE"
HISTORY_FILE="$DEFAULT_HISTORY_FILE"
MAX_LOG_SIZE="$DEFAULT_MAX_LOG_SIZE"

# 企业微信配置（默认关闭，避免首次生成配置就带着占位密钥）
WECHAT_WEBHOOK_URL=""
ENABLE_WECHAT_NOTIFY=false

# 邮件配置（可选）
ENABLE_EMAIL_NOTIFY=false
EMAIL_TO="admin@example.com"
EMAIL_SUBJECT="DNS域名监控报告"

# 高级配置
ENABLE_HISTORY=true
ENABLE_STATS=true
BLACKLIST_DOMAINS=localhost
BLACKLIST_DOMAINS=*.local
BLACKLIST_DOMAINS=*.test
WHITELIST_ONLY=false
# 兼容旧配置；脚本不会主动清空正在写入的源日志。
TRUNCATE_SOURCE_LOG=false
EOF
    then
        log_warn "无法写入默认配置文件，将仅在本次运行中使用默认值: $CONFIG_FILE"
        return 0
    fi
    log_info "已创建默认配置文件: $CONFIG_FILE"
}

# ==== 颜色和格式定义 ====
COLOR_RED='\e[31m'; COLOR_GREEN='\e[32m'; COLOR_YELLOW='\e[33m'
COLOR_BLUE='\e[34m'; COLOR_MAGENTA='\e[35m'; COLOR_CYAN='\e[36m'; COLOR_RESET='\e[0m'

# ==== 日志函数 ====
log_message() {
    local level="$1"
    local message="$2"
    local timestamp prefix
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        INFO) prefix="${COLOR_CYAN}✨ ℹ️ ${COLOR_RESET}" ;;
        SUCCESS) prefix="${COLOR_GREEN}🎉 ✅ ${COLOR_RESET}" ;;
        WARN) prefix="${COLOR_YELLOW}⚠️ ⚡ ${COLOR_RESET}" ;;
        ERROR) prefix="${COLOR_RED}❌ 💥 ${COLOR_RESET}" ;;
        PROMPT) prefix="${COLOR_MAGENTA}👉 🌟 ${COLOR_RESET}" ;;
        STATS) prefix="${COLOR_BLUE}📊 📈 ${COLOR_RESET}" ;;
        *) prefix='' ;;
    esac
    printf '%b%s\n' "$prefix" "$message"
    
    # 写入日志文件
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

log_info() { log_message "INFO" "$1"; }
log_success() { log_message "SUCCESS" "$1"; }
log_warn() { log_message "WARN" "$1"; }
log_error() { log_message "ERROR" "$1"; }

# ==== 错误处理 ====
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 && $exit_code -ne 2 ]]; then
        log_error "脚本异常退出，退出码: $exit_code"
    fi
    
    # 只清理本实例创建的临时文件，避免影响并发任务。
    if (( ${#TEMP_FILES[@]} > 0 )); then
        rm -f -- "${TEMP_FILES[@]}"
    fi
    [[ "$LOCK_MODE" == mkdir ]] && rmdir "$LOCK_DIR" 2>/dev/null || true
}

error_handler() {
    local line_number=$1
    local command="$2"
    log_error "第 $line_number 行执行失败: $command"
    exit 1
}

trap cleanup EXIT
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR

size_to_bytes() {
    local value
    value=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')
    local number
    local unit
    local multiplier=1

    if [[ ! "$value" =~ ^([0-9]+)([KMGT]?)(I?B)?$ ]]; then
        return 1
    fi

    number=$((10#${BASH_REMATCH[1]}))
    unit="${BASH_REMATCH[2]}"
    case "$unit" in
        K) multiplier=1024 ;;
        M) multiplier=$((1024 ** 2)) ;;
        G) multiplier=$((1024 ** 3)) ;;
        T) multiplier=$((1024 ** 4)) ;;
    esac
    printf '%s\n' "$((number * multiplier))"
}

ensure_parent_directory() {
    local file="$1"
    local parent_dir
    parent_dir=$(dirname "$file")

    if [[ ! -d "$parent_dir" ]] && ! mkdir -p "$parent_dir"; then
        log_error "无法创建目录: $parent_dir"
        return 1
    fi
}

show_help() {
    cat << EOF
MOSDNS 重复域名监控辅助脚本

用法: $0 [选项]

选项:
  -c, --config FILE    指定配置文件（默认: ${CONFIG_FILE}）
      --plan           只读显示配置、日志和报告路径
  -h, --help           显示帮助信息

也可通过 DNS_MONITOR_CONFIG 环境变量指定配置文件。
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config)
                if [[ -z "${2:-}" ]]; then
                    log_error "参数 $1 缺少配置文件路径"
                    exit 2
                fi
                CONFIG_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --plan)
                PLAN_ONLY=true
                shift
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 2
                ;;
        esac
    done
}

# ==== 文件和权限检查 ====
check_prerequisites() {
    log_info "检查运行环境和权限..."
    
    # 检查必要的命令
    local required_commands=("grep" "sed" "awk" "sort" "uniq" "mktemp" "tr")
    local optional_commands=("jq")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "缺少必要命令: $cmd"
            exit 1
        fi
    done
    
    # 检查可选命令
    for cmd in "${optional_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_warn "可选命令 $cmd 不可用，某些功能可能受限"
        fi
    done

    if [[ "${ENABLE_WECHAT_NOTIFY:-false}" == "true" && -n "${WECHAT_WEBHOOK_URL:-}" ]] && ! command -v curl &> /dev/null; then
        log_error "已启用企业微信通知，但缺少必要命令: curl"
        exit 1
    fi
    
    # 检查文件权限
    if [[ ! -r "$DOMAIN_FILE" ]]; then
        log_error "无法读取域名日志文件: $DOMAIN_FILE"
        exit 1
    fi
    if [[ "${TRUNCATE_SOURCE_LOG:-false}" == "true" ]]; then
        log_warn "TRUNCATE_SOURCE_LOG 已停用；请使用 mosdns 自身轮转或 logrotate 管理源日志"
    fi
    
    ensure_parent_directory "$OUTPUT_FILE"
    if command -v flock >/dev/null 2>&1; then
        ensure_parent_directory "$LOCK_FILE"
        eval "exec ${LOCK_FD}>\"$LOCK_FILE\""
        if ! flock -n "$LOCK_FD"; then
            log_warn "已有 DNS 监控任务运行，退出以避免并发覆盖"
            exit 1
        fi
        LOCK_MODE='flock'
    else
        ensure_parent_directory "$LOCK_DIR"
        if ! mkdir "$LOCK_DIR" 2>/dev/null; then
            log_warn "已有 DNS 监控任务运行，退出以避免并发覆盖"
            exit 1
        fi
        LOCK_MODE='mkdir'
        log_warn "系统没有 flock，已使用 mkdir 原子锁回退"
    fi
    if [[ "${ENABLE_HISTORY:-false}" == "true" ]]; then
        ensure_parent_directory "$HISTORY_FILE"
    fi

    local max_log_bytes
    if ! max_log_bytes=$(size_to_bytes "$MAX_LOG_SIZE"); then
        log_error "MAX_LOG_SIZE 格式无效: $MAX_LOG_SIZE（示例: 100M、1G）"
        exit 1
    fi
    
    # 检查日志文件大小并轮转
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt "$max_log_bytes" ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        log_info "日志文件已轮转"
    fi
}

# ==== 域名提取和分析 ====
extract_domains() {
    log_info "开始从日志文件中提取域名..."
    
    local temp_file
    local stats_file
    local total_queries=0
    local unique_domains=0
    temp_file=$(mktemp /tmp/dns_monitor_domains_XXXXXX.tmp)
    stats_file=$(mktemp /tmp/dns_monitor_stats_XXXXXX.tmp)
    TEMP_FILES+=("$temp_file" "$stats_file")
    
    # 检查源文件是否存在且不为空
    if [[ ! -s "$DOMAIN_FILE" ]]; then
        log_warn "日志文件为空或不存在: $DOMAIN_FILE"
        # 创建空的临时文件
        touch "$temp_file"
    else
        # 提取域名并统计，使用更安全的方式
        {
            grep -oE '"qname": "([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})' "$DOMAIN_FILE" 2>/dev/null || true
        } | {
            sed 's/"qname": "//' || true
        } | {
            tr '[:upper:]' '[:lower:]' || true
        } | {
            grep -v "in-addr.arpa" || true
        } | {
            grep -v "ip6.arpa" || true
        } | {
            sort || true
        } | {
            uniq -c || true
        } | {
            sort -rn || true
        } > "$temp_file"
        
        # 确保临时文件存在
        touch "$temp_file"
        
        # 计算统计信息，处理空文件情况
        if [[ -s "$temp_file" ]]; then
            total_queries=$(awk '{sum+=$1} END {print sum+0}' "$temp_file")
            unique_domains=$(wc -l < "$temp_file" | tr -d ' ')
        fi
    fi
    
    log_info "提取完成 - 总查询: $total_queries, 唯一域名: $unique_domains"
    
    # 生成统计信息
    cat > "$stats_file" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "total_queries": $total_queries,
    "unique_domains": $unique_domains,
    "threshold": $THRESHOLD,
    "log_file_size": $(stat -f%z "$DOMAIN_FILE" 2>/dev/null || stat -c%s "$DOMAIN_FILE" 2>/dev/null || echo 0)
}
EOF
    
    EXTRACTED_DOMAINS_FILE="$temp_file"
    EXTRACTED_STATS_FILE="$stats_file"
}

# ==== 黑白名单过滤 ====
filter_domains() {
    local input_file="$1"
    local output_file="$2"
    
    # 确保输出文件存在
    touch "$output_file"
    
    # 检查输入文件是否存在且不为空
    if [[ ! -s "$input_file" ]]; then
        log_info "没有域名数据需要过滤"
        return 0
    fi
    
    while read -r line; do
        # 跳过空行
        [[ -z "$line" ]] && continue
        
        local count
        local domain
        read -r count domain _ <<< "$line"
        
        # 检查是否为有效的数字和域名
        if [[ ! "$count" =~ ^[0-9]+$ ]] || [[ -z "$domain" ]]; then
            continue
        fi
        
        # 黑名单过滤
        local skip=false
        for pattern in "${BLACKLIST_DOMAINS[@]-}"; do
            # shellcheck disable=SC2053 # 配置项有意支持 shell glob（例如 *.example.com）
            if [[ -n "$pattern" && "$domain" == $pattern ]]; then
                skip=true
                break
            fi
        done
        
        if [[ "$skip" == false ]] && (( count > THRESHOLD )); then
            echo "$line" >> "$output_file"
        fi
    done < "$input_file"
}

# ==== 生成报告 ====
generate_report() {
    local domains_file="$1"
    local stats_file="$2"
    
    log_info "正在生成重复域名报告..."
    
    local filtered_file
    filtered_file=$(mktemp /tmp/dns_monitor_filtered_XXXXXX.tmp)
    TEMP_FILES+=("$filtered_file")
    filter_domains "$domains_file" "$filtered_file"

    local output_tmp
    output_tmp=$(mktemp "${OUTPUT_FILE}.tmp.XXXXXX")
    TEMP_FILES+=("$output_tmp")
    
    # 生成规则文件
    {
        echo "# 重复域名列表 - 生成时间: $(date)"
        echo "# 阈值: $THRESHOLD 次"
        echo "# =================================="
    } > "$output_tmp"
    
    local duplicate_count=0
    local message_body="🌈 DNS重复域名监控报告\n"
    message_body+="📅 时间: $(date '+%Y-%m-%d %H:%M:%S')\n"
    message_body+="🎯 阈值: $THRESHOLD 次\n\n"
    
    # 读取统计信息，处理可能的JSON解析错误
    local total_queries=0
    local unique_domains=0
    if [[ -s "$stats_file" ]] && command -v jq >/dev/null 2>&1; then
        total_queries=$(jq -r '.total_queries // 0' "$stats_file" 2>/dev/null || echo 0)
        unique_domains=$(jq -r '.unique_domains // 0' "$stats_file" 2>/dev/null || echo 0)
    elif [[ -s "$stats_file" ]]; then
        total_queries=$(sed -n 's/.*"total_queries": *\([0-9][0-9]*\).*/\1/p' "$stats_file")
        unique_domains=$(sed -n 's/.*"unique_domains": *\([0-9][0-9]*\).*/\1/p' "$stats_file")
        total_queries="${total_queries:-0}"
        unique_domains="${unique_domains:-0}"
    fi
    
    if [[ -s "$filtered_file" ]]; then
        while read -r line; do
            # 跳过空行
            [[ -z "$line" ]] && continue
            
            local count
            local domain
            read -r count domain _ <<< "$line"
            
            # 验证数据有效性
            if [[ "$count" =~ ^[0-9]+$ ]] && [[ -n "$domain" ]]; then
                printf 'full:%s\n' "$domain" >> "$output_tmp"
                message_body+="🔥 $domain → $count 次\n"
                duplicate_count=$((duplicate_count + 1))
            fi
        done < "$filtered_file"
        
        if [[ $duplicate_count -gt 0 ]]; then
            # 添加统计信息到消息
            message_body+="\n📊 统计信息:\n"
            message_body+="• 总查询次数: $total_queries\n"
            message_body+="• 唯一域名数: $unique_domains\n"
            message_body+="• 重复域名数: $duplicate_count\n"
            
            log_success "发现 $duplicate_count 个重复域名"
        else
            message_body+="✨ 未发现超过阈值的重复域名\n"
            message_body+="🎉 域名查询正常！\n"
            log_info "未发现重复域名"
        fi
    else
        message_body+="✨ 未发现超过阈值的重复域名\n"
        message_body+="🎉 域名查询正常！\n"
        
        # 仍然显示统计信息
        if [[ $total_queries -gt 0 || $unique_domains -gt 0 ]]; then
            message_body+="\n📊 统计信息:\n"
            message_body+="• 总查询次数: $total_queries\n"
            message_body+="• 唯一域名数: $unique_domains\n"
            message_body+="• 重复域名数: 0\n"
        fi
        
        log_info "未发现重复域名"
    fi

    chmod 0644 "$output_tmp"
    mv -f -- "$output_tmp" "$OUTPUT_FILE"
    log_info "规则文件已更新: $OUTPUT_FILE"
    
    # 保存历史记录
    if [[ "${ENABLE_HISTORY:-false}" == "true" ]]; then
        save_history "$stats_file" "$duplicate_count"
    fi
    
    # 发送通知
    send_notifications "$message_body"
    
}

# ==== 历史记录 ====
save_history() {
    local stats_file="$1"
    local duplicate_count="$2"
    
    # 检查 jq 是否可用
    if ! command -v jq >/dev/null 2>&1; then
        log_warn "jq 命令不可用，跳过历史记录保存"
        return 0
    fi
    
    # 检查统计文件是否存在
    if [[ ! -s "$stats_file" ]]; then
        log_warn "统计文件为空，跳过历史记录保存"
        return 0
    fi
    
    local history_entry
    if history_entry=$(jq --argjson dup_count "$duplicate_count" '. + {duplicate_domains: $dup_count}' "$stats_file" 2>/dev/null); then
        local temp_history
        temp_history=$(mktemp "${HISTORY_FILE}.tmp.XXXXXX")
        TEMP_FILES+=("$temp_history")
        if [[ -f "$HISTORY_FILE" ]]; then
            if jq --argjson entry "$history_entry" '. + [$entry]' "$HISTORY_FILE" > "$temp_history" 2>/dev/null; then
                chmod 0644 "$temp_history"
                mv -f -- "$temp_history" "$HISTORY_FILE"
                log_info "历史记录已更新"
            else
                log_warn "历史记录更新失败"
                rm -f "$temp_history"
            fi
        else
            printf '[%s]\n' "$history_entry" > "$temp_history"
            chmod 0644 "$temp_history"
            mv -f -- "$temp_history" "$HISTORY_FILE"
            log_info "历史记录文件已创建"
        fi
    else
        log_warn "无法处理统计数据，跳过历史记录保存"
    fi
}

# ==== 通知系统 ====
send_notifications() {
    local message="$1"
    local failed=0
    
    # 企业微信通知
    if [[ "${ENABLE_WECHAT_NOTIFY:-true}" == "true" && -n "${WECHAT_WEBHOOK_URL:-}" ]]; then
        send_wechat_message "$message" || failed=1
    fi
    
    # 邮件通知
    if [[ "${ENABLE_EMAIL_NOTIFY:-false}" == "true" ]]; then
        send_email_notification "$message" || failed=1
    fi

    return "$failed"
}

send_wechat_message() {
    local message="$1"
    local title="【DNS域名监控报告】"
    
    if [[ -z "${WECHAT_WEBHOOK_URL:-}" || "${WECHAT_WEBHOOK_URL:-}" == *"你的KEY"* ]]; then
        log_error "企业微信 Webhook URL 未配置"
        return 1
    fi

    if [[ ! "$WECHAT_WEBHOOK_URL" =~ ^https://[^[:space:][:cntrl:]]+$ ]]; then
        log_error "企业微信 Webhook URL 格式无效，必须使用 HTTPS"
        return 1
    fi

    message=${message//\\n/$'\n'}
    local content="$title"$'\n\n'"$message"
    local safe_content
    local json
    local response
    safe_content=$(json_escape "$content")
    json="{\"msgtype\":\"text\",\"text\":{\"content\":\"$safe_content\"}}"

    if response=$(curl --fail-with-body --silent --show-error --proto '=https' --proto-redir '=https' --connect-timeout 5 --max-time 15 -X POST "$WECHAT_WEBHOOK_URL" -H 'Content-Type: application/json' -d "$json") && \
        [[ "$response" =~ \"errcode\"[[:space:]]*:[[:space:]]*0 ]]; then
        log_success "企业微信消息发送成功"
    else
        log_error "企业微信消息发送失败${response:+: $response}"
        return 1
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

send_email_notification() {
    local message="$1"
    
    if command -v mail &> /dev/null && [[ -n "${EMAIL_TO:-}" ]]; then
        if echo -e "$message" | mail -s "${EMAIL_SUBJECT:-DNS监控报告}" "$EMAIL_TO"; then
            log_info "邮件通知已发送"
        else
            log_error "邮件通知发送失败"
            return 1
        fi
    else
        log_error "邮件功能未配置或不可用"
        return 1
    fi
}

# ==== 性能监控 ====
show_performance_stats() {
    local started_at="$1"
    local started_epoch="$2"
    if [[ "${ENABLE_STATS:-true}" == "true" ]]; then
        log_message "STATS" "脚本执行统计:"
        log_message "STATS" "• 开始时间: $started_at"
        log_message "STATS" "• 结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
        log_message "STATS" "• 执行用时: $(($(date +%s) - started_epoch)) 秒"
    fi
}

# ==== 主函数 ====
main() {
    local start_time
    local start_epoch
    start_time=$(date '+%Y-%m-%d %H:%M:%S')
    start_epoch=$(date +%s)

    parse_arguments "$@"

    if [[ "$PLAN_ONLY" == true ]]; then
        DNS_MONITOR_CREATE_CONFIG=false
        LOG_FILE=/dev/null
        load_config
        printf 'DNS 重复查询分析预览\n配置: %s\n域名源日志: %s\n报告输出: %s\n阈值: %s\n通知: %s\n' \
            "$CONFIG_FILE" "$DOMAIN_FILE" "$OUTPUT_FILE" "$THRESHOLD" "${ENABLE_WECHAT_NOTIFY:-false}"
        printf '正式运行才会生成报告和历史记录，不会清空源日志。\n'
        return 0
    fi
    
    log_info "DNS域名监控脚本启动 v2.0"
    
    # 加载配置
    load_config
    
    # 环境检查
    check_prerequisites
    
    # 提取域名
    extract_domains
    
    # 生成报告
    generate_report "$EXTRACTED_DOMAINS_FILE" "$EXTRACTED_STATS_FILE"
    
    # 显示性能统计
    show_performance_stats "$start_time" "$start_epoch"
    
    log_success "DNS域名监控完成！"
}

# ==== 脚本入口 ====
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
