#!/bin/bash
# ==== MOSDNS监控辅助脚本====
# 功能: 监控mosdns查询日志，检测重复域名并生成，最后会添加在规则里面辅助减少mosdns对重复域名的查询，重复次数很多的域名服务器直接TTL最大。
# 依赖: mosdns 日志文件
# By: BuBuXSY
# Version: 2025.07.19

set -euo pipefail  # 严格模式：遇到错误立即退出

# ==== 配置文件加载 ====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/dns_monitor.conf"

# 默认配置
DEFAULT_DOMAIN_FILE="/etc/mosdns/mosdns.log"
DEFAULT_OUTPUT_FILE="/etc/mosdns/rules/repeat_domain.txt"
DEFAULT_THRESHOLD=500
DEFAULT_LOG_FILE="/var/log/dns_monitor.log"
DEFAULT_HISTORY_FILE="/var/log/dns_monitor_history.json"
DEFAULT_MAX_LOG_SIZE="100M"

# 加载配置文件
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log_info "配置文件已加载: $CONFIG_FILE"
    else
        log_warn "配置文件不存在，使用默认配置"
        create_default_config
    fi
    
    # 设置默认值（如果配置文件中没有定义）
    DOMAIN_FILE="${DOMAIN_FILE:-$DEFAULT_DOMAIN_FILE}"
    OUTPUT_FILE="${OUTPUT_FILE:-$DEFAULT_OUTPUT_FILE}"
    THRESHOLD="${THRESHOLD:-$DEFAULT_THRESHOLD}"
    LOG_FILE="${LOG_FILE:-$DEFAULT_LOG_FILE}"
    HISTORY_FILE="${HISTORY_FILE:-$DEFAULT_HISTORY_FILE}"
    MAX_LOG_SIZE="${MAX_LOG_SIZE:-$DEFAULT_MAX_LOG_SIZE}"
}

# 创建默认配置文件
create_default_config() {
    cat > "$CONFIG_FILE" << EOF
# DNS监控配置文件
DOMAIN_FILE="$DEFAULT_DOMAIN_FILE"
OUTPUT_FILE="$DEFAULT_OUTPUT_FILE"
THRESHOLD=$DEFAULT_THRESHOLD
LOG_FILE="$DEFAULT_LOG_FILE"
HISTORY_FILE="$DEFAULT_HISTORY_FILE"
MAX_LOG_SIZE="$DEFAULT_MAX_LOG_SIZE"

# 企业微信配置
WECHAT_WEBHOOK_URL="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=你的KEY"
ENABLE_WECHAT_NOTIFY=true

# 邮件配置（可选）
ENABLE_EMAIL_NOTIFY=false
EMAIL_TO="admin@example.com"
EMAIL_SUBJECT="DNS域名监控报告"

# 高级配置
ENABLE_HISTORY=true
ENABLE_STATS=true
BLACKLIST_DOMAINS=("localhost" "*.local" "*.test")
WHITELIST_ONLY=false
EOF
    log_info "已创建默认配置文件: $CONFIG_FILE"
}

# ==== 颜色和格式定义 ====
declare -A COLORS=(
    [RED]="\e[31m"
    [GREEN]="\e[32m"
    [YELLOW]="\e[33m"
    [BLUE]="\e[34m"
    [MAGENTA]="\e[35m"
    [CYAN]="\e[36m"
    [BOLD]="\e[1m"
    [RESET]="\e[0m"
)

declare -A ICONS=(
    [INFO]="${COLORS[CYAN]}✨ ℹ️ ${COLORS[RESET]}"
    [SUCCESS]="${COLORS[GREEN]}🎉 ✅ ${COLORS[RESET]}"
    [WARN]="${COLORS[YELLOW]}⚠️ ⚡ ${COLORS[RESET]}"
    [ERROR]="${COLORS[RED]}❌ 💥 ${COLORS[RESET]}"
    [PROMPT]="${COLORS[MAGENTA]}👉 🌟 ${COLORS[RESET]}"
    [STATS]="${COLORS[BLUE]}📊 📈 ${COLORS[RESET]}"
)

# ==== 日志函数 ====
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${ICONS[$level]}$message"
    
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
    if [[ $exit_code -ne 0 ]]; then
        log_error "脚本异常退出，退出码: $exit_code"
    fi
    
    # 清理临时文件
    rm -f /tmp/dns_monitor_*.tmp
}

error_handler() {
    local line_number=$1
    local command="$2"
    log_error "第 $line_number 行执行失败: $command"
    exit 1
}

trap cleanup EXIT
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR

# ==== 文件和权限检查 ====
check_prerequisites() {
    log_info "检查运行环境和权限..."
    
    # 检查必要的命令
    local required_commands=("grep" "sed" "awk" "sort" "uniq" "curl")
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
    
    # 检查文件权限
    if [[ ! -r "$DOMAIN_FILE" ]]; then
        log_error "无法读取域名日志文件: $DOMAIN_FILE"
        exit 1
    fi
    
    # 创建输出目录
    local output_dir=$(dirname "$OUTPUT_FILE")
    if [[ ! -d "$output_dir" ]]; then
        mkdir -p "$output_dir" || {
            log_error "无法创建输出目录: $output_dir"
            exit 1
        }
    fi
    
    # 检查日志文件大小并轮转
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt 104857600 ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        log_info "日志文件已轮转"
    fi
}

# ==== 域名提取和分析 ====
extract_domains() {
    log_info "开始从日志文件中提取域名..."
    
    local temp_file="/tmp/dns_monitor_domains_$.tmp"
    local stats_file="/tmp/dns_monitor_stats_$.tmp"
    
    # 检查源文件是否存在且不为空
    if [[ ! -s "$DOMAIN_FILE" ]]; then
        log_warn "日志文件为空或不存在: $DOMAIN_FILE"
        # 创建空的临时文件
        touch "$temp_file"
        local total_queries=0
        local unique_domains=0
    else
        # 提取域名并统计，使用更安全的方式
        {
            grep -oE '"qname": "([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})' "$DOMAIN_FILE" 2>/dev/null || true
        } | {
            sed 's/"qname": "//' || true
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
            local total_queries=$(awk '{sum+=$1} END {print sum+0}' "$temp_file")
            local unique_domains=$(wc -l < "$temp_file" | tr -d ' ')
        else
            local total_queries=0
            local unique_domains=0
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
    
    echo "$temp_file|$stats_file"
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
        
        local count=$(echo "$line" | awk '{print $1}')
        local domain=$(echo "$line" | awk '{print $2}')
        
        # 检查是否为有效的数字和域名
        if [[ ! "$count" =~ ^[0-9]+$ ]] || [[ -z "$domain" ]]; then
            continue
        fi
        
        # 黑名单过滤
        local skip=false
        for pattern in "${BLACKLIST_DOMAINS[@]:-}"; do
            if [[ "$domain" =~ $pattern ]]; then
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
    
    local filtered_file="/tmp/dns_monitor_filtered_$.tmp"
    filter_domains "$domains_file" "$filtered_file"
    
    # 生成规则文件
    {
        echo "# 重复域名列表 - 生成时间: $(date)"
        echo "# 阈值: $THRESHOLD 次"
        echo "# =================================="
    } > "$OUTPUT_FILE"
    
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
    fi
    
    if [[ -s "$filtered_file" ]]; then
        while read -r line; do
            # 跳过空行
            [[ -z "$line" ]] && continue
            
            local count=$(echo "$line" | awk '{print $1}')
            local domain=$(echo "$line" | awk '{print $2}')
            
            # 验证数据有效性
            if [[ "$count" =~ ^[0-9]+$ ]] && [[ -n "$domain" ]]; then
                echo "full:$domain" >> "$OUTPUT_FILE"
                message_body+="🔥 $domain → $count 次\n"
                ((duplicate_count++))
            fi
        done < "$filtered_file"
        
        if [[ $duplicate_count -gt 0 ]]; then
            # 添加统计信息到消息
            message_body+="\n📊 统计信息:\n"
            message_body+="• 总查询次数: $total_queries\n"
            message_body+="• 唯一域名数: $unique_domains\n"
            message_body+="• 重复域名数: $duplicate_count\n"
            
            log_success "发现 $duplicate_count 个重复域名，已保存到 $OUTPUT_FILE"
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
    
    # 保存历史记录
    if [[ "${ENABLE_HISTORY:-false}" == "true" ]]; then
        save_history "$stats_file" "$duplicate_count"
    fi
    
    # 发送通知
    send_notifications "$message_body"
    
    # 清空日志文件
    if [[ -f "$DOMAIN_FILE" ]]; then
        > "$DOMAIN_FILE"
        log_info "原始日志文件已清空"
    fi
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
        if [[ -f "$HISTORY_FILE" ]]; then
            local temp_history="/tmp/dns_monitor_history_$.tmp"
            if jq --argjson entry "$history_entry" '. + [$entry]' "$HISTORY_FILE" > "$temp_history" 2>/dev/null; then
                mv "$temp_history" "$HISTORY_FILE"
                log_info "历史记录已更新"
            else
                log_warn "历史记录更新失败"
                rm -f "$temp_history"
            fi
        else
            echo "[$history_entry]" > "$HISTORY_FILE"
            log_info "历史记录文件已创建"
        fi
    else
        log_warn "无法处理统计数据，跳过历史记录保存"
    fi
}

# ==== 通知系统 ====
send_notifications() {
    local message="$1"
    
    # 企业微信通知
    if [[ "${ENABLE_WECHAT_NOTIFY:-true}" == "true" && -n "${WECHAT_WEBHOOK_URL:-}" ]]; then
        send_wechat_message "$message"
    fi
    
    # 邮件通知
    if [[ "${ENABLE_EMAIL_NOTIFY:-false}" == "true" ]]; then
        send_email_notification "$message"
    fi
}

send_wechat_message() {
    local message="$1"
    local title="【DNS域名监控报告】"
    
    if [[ "${WECHAT_WEBHOOK_URL:-}" == *"你的KEY"* ]]; then
        log_warn "企业微信 Webhook URL 未配置，跳过推送"
        return
    fi
    
    local safe_message=$(echo "$message" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
    local json="{\"msgtype\":\"text\",\"text\":{\"content\":\"$title\\n\\n$safe_message\"}}"
    
    if curl -s -f -X POST "$WECHAT_WEBHOOK_URL" -H 'Content-Type: application/json' -d "$json" >/dev/null; then
        log_success "企业微信消息发送成功"
    else
        log_error "企业微信消息发送失败"
    fi
}

send_email_notification() {
    local message="$1"
    
    if command -v mail &> /dev/null && [[ -n "${EMAIL_TO:-}" ]]; then
        echo -e "$message" | mail -s "${EMAIL_SUBJECT:-DNS监控报告}" "$EMAIL_TO"
        log_info "邮件通知已发送"
    else
        log_warn "邮件功能未配置或不可用"
    fi
}

# ==== 性能监控 ====
show_performance_stats() {
    if [[ "${ENABLE_STATS:-true}" == "true" ]]; then
        log_message "STATS" "脚本执行统计:"
        log_message "STATS" "• 开始时间: $start_time"
        log_message "STATS" "• 结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
        log_message "STATS" "• 执行用时: $(($(date +%s) - $(date -d "$start_time" +%s))) 秒"
    fi
}

# ==== 主函数 ====
main() {
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_info "DNS域名监控脚本启动 v2.0"
    
    # 加载配置
    load_config
    
    # 环境检查
    check_prerequisites
    
    # 提取域名
    local files=$(extract_domains)
    local domains_file=$(echo "$files" | cut -d'|' -f1)
    local stats_file=$(echo "$files" | cut -d'|' -f2)
    
    # 生成报告
    generate_report "$domains_file" "$stats_file"
    
    # 显示性能统计
    show_performance_stats
    
    log_success "DNS域名监控完成！"
}

# ==== 脚本入口 ====
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
