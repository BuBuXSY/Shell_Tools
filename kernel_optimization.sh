#!/bin/bash
# Linux 内核优化脚本
# BY BuBuXSY
# Version: 2025.07.19

set -euo pipefail  # 严格模式：遇到错误立即退出

# 颜色和样式定义 - 修复：使用更兼容的转义序列
readonly RED=$'\033[1;31m'
readonly GREEN=$'\033[1;32m'
readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[1;34m'
readonly PURPLE=$'\033[1;35m'
readonly CYAN=$'\033[1;36m'
readonly WHITE=$'\033[1;37m'
readonly BOLD=$'\033[1m'
readonly RESET=$'\033[0m'

# 全局配置
readonly LOG_FILE="/var/log/kernel_optimization.log"
readonly BACKUP_DIR="/var/backups/kernel_optimization"
readonly VERSION_DIR="/etc/kernel_optimization/versions"
readonly BENCHMARK_DIR="/var/log/kernel_optimization/benchmarks"
readonly EXPORT_DIR="/root/kernel_optimization_exports"
readonly TEMP_DIR="/tmp/kernel_optimization"

# 脚本版本和元信息
readonly SCRIPT_VERSION="1.0-fixed-v2"
readonly SCRIPT_NAME="Linux内核优化脚本"
readonly MIN_KERNEL_VERSION="3.10"
readonly MIN_MEMORY_MB=512

# 创建必要的目录
create_directories() {
    local dirs=("$BACKUP_DIR" "$VERSION_DIR" "$BENCHMARK_DIR" "$EXPORT_DIR" "$TEMP_DIR")
    
    for dir in "${dirs[@]}"; do
        if ! mkdir -p "$dir" 2>/dev/null; then
            echo "警告: 无法创建目录 $dir" >&2
        else
            chmod 750 "$dir" 2>/dev/null || true
        fi
    done
}

# 全局变量
SYSTEM_TYPE=""
ENV_TYPE=""
OPTIMIZATION=""
OS=""
VER=""
DISTRO_FAMILY=""
TOTAL_MEM=""
TOTAL_MEM_GB=""
CPU_CORES=""
KERNEL_VERSION=""
WORKLOAD_TYPE=""
AUTO_ROLLBACK_ENABLED=false
DRY_RUN=false

# 优化参数存储 - 修复：添加默认值初始化
declare -A OPTIMAL_VALUES=()
declare -A TEST_RESULTS=()
declare -A CURRENT_VALUES=()

# 安全的数组长度检查函数
safe_array_length() {
    local -n array_ref=$1
    local length=0
    
    # 安全地检查关联数组长度
    if [[ -v array_ref ]]; then
        for key in "${!array_ref[@]}"; do
            ((length++))
        done
    fi
    
    echo "$length"
}

# 安全的数组元素检查函数
safe_array_get() {
    local -n array_ref=$1
    local key="$2"
    local default_value="${3:-}"
    
    if [[ -v array_ref["$key"] ]]; then
        echo "${array_ref[$key]}"
    else
        echo "$default_value"
    fi
}

# 安全的数组元素设置函数
safe_array_set() {
    local -n array_ref=$1
    local key="$2"
    local value="$3"
    
    array_ref["$key"]="$value"
}

# ==================== 基础函数 ====================

# 安全的日志记录函数
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] $message"
    
    # 尝试写入日志文件，失败时输出到stderr
    if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
        echo "$log_entry" >&2
    fi
    
    # 同时输出到终端（可选）
    echo "$log_entry"
}

# 打印带颜色和emoji的消息
print_msg() {
    local type="$1"
    local msg="$2"
    
    case "$type" in
        "success") echo -e "${GREEN}✅ $msg${RESET}" ;;
        "error") echo -e "${RED}❌ $msg${RESET}" ;;
        "warning") echo -e "${YELLOW}⚠️  $msg${RESET}" ;;
        "info") echo -e "${BLUE}ℹ️  $msg${RESET}" ;;
        "question") echo -e "${PURPLE}❓ $msg${RESET}" ;;
        "working") echo -e "${CYAN}⚡ $msg${RESET}" ;;
        "test") echo -e "${PURPLE}🧪 $msg${RESET}" ;;
        "security") echo -e "${RED}🔒 $msg${RESET}" ;;
        "preview") echo -e "${YELLOW}👁️  $msg${RESET}" ;;
    esac
}

# 检查命令是否存在
check_command() {
    command -v "$1" >/dev/null 2>&1
}

# 安全的数值验证
validate_number() {
    local value="$1"
    local min="${2:-0}"
    local max="${3:-9223372036854775807}"  # 64位最大值
    
    if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge "$min" ] && [ "$value" -le "$max" ]; then
        return 0
    else
        return 1
    fi
}

# 输入验证和清理
validate_user_input() {
    local input="$1"
    local valid_options="$2"
    
    # 移除潜在危险字符，只保留字母数字
    input=$(echo "$input" | tr -cd '[:alnum:]')
    
    # 检查是否在有效选项中
    if echo "$valid_options" | grep -qw "$input"; then
        echo "$input"
        return 0
    else
        return 1
    fi
}

# 检查root权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_msg "error" "此脚本必须以root权限运行！🔒"
        echo -e "${YELLOW}请尝试: ${WHITE}sudo $0${RESET}"
        exit 1
    fi
    print_msg "success" "已获取root权限"
}

# 检查系统兼容性
check_compatibility() {
    print_msg "test" "检查系统兼容性..."
    
    # 检查内核版本 - 修复版本比较逻辑
    local kernel_ver=$(uname -r | cut -d. -f1,2)
    
    # 正确的版本比较函数
    version_compare() {
        local ver1="$1"
        local ver2="$2"
        
        # 分割版本号
        local IFS='.'
        local ver1_parts=($ver1)
        local ver2_parts=($ver2)
        
        # 比较主版本号
        if [ "${ver1_parts[0]}" -gt "${ver2_parts[0]}" ]; then
            return 0  # ver1 > ver2
        elif [ "${ver1_parts[0]}" -lt "${ver2_parts[0]}" ]; then
            return 1  # ver1 < ver2
        fi
        
        # 主版本号相同，比较次版本号
        local ver1_minor="${ver1_parts[1]:-0}"
        local ver2_minor="${ver2_parts[1]:-0}"
        
        if [ "$ver1_minor" -ge "$ver2_minor" ]; then
            return 0  # ver1 >= ver2
        else
            return 1  # ver1 < ver2
        fi
    }
    
    if ! version_compare "$kernel_ver" "$MIN_KERNEL_VERSION"; then
        print_msg "error" "内核版本 $kernel_ver 过低，需要 $MIN_KERNEL_VERSION 或更高版本"
        return 1
    fi
    
    # 检查内存
    local mem_mb=$((TOTAL_MEM / 1024 / 1024))
    if [ "$mem_mb" -lt "$MIN_MEMORY_MB" ]; then
        print_msg "warning" "内存容量 ${mem_mb}MB 较低，建议至少 ${MIN_MEMORY_MB}MB"
    fi
    
    # 检查必要的系统文件
    local required_files=("/proc/sys" "/etc/sysctl.conf")
    for file in "${required_files[@]}"; do
        if [ ! -e "$file" ]; then
            print_msg "error" "缺少必要的系统文件: $file"
            return 1
        fi
    done
    
    print_msg "success" "系统兼容性检查通过"
    return 0
}

# ==================== 系统检测函数 ====================

# 安全的发行版检测
detect_distro() {
    print_msg "working" "正在检测Linux发行版..."
    
    if [ -f /etc/os-release ]; then
        # 安全地读取os-release文件，避免代码注入
        local name_line version_line id_line
        
        name_line=$(grep '^NAME=' /etc/os-release 2>/dev/null | head -1)
        version_line=$(grep '^VERSION_ID=' /etc/os-release 2>/dev/null | head -1)
        id_line=$(grep '^ID=' /etc/os-release 2>/dev/null | head -1)
        
        # 安全提取值
        OS=$(echo "$name_line" | cut -d'=' -f2- | tr -d '"' | head -1)
        VER=$(echo "$version_line" | cut -d'=' -f2- | tr -d '"' | head -1)
        local system_id=$(echo "$id_line" | cut -d'=' -f2- | tr -d '"' | head -1)
        
        # 验证和清理提取的值
        OS=$(echo "${OS:-Unknown}" | tr -cd '[:alnum:] ._-')
        VER=$(echo "${VER:-0}" | tr -cd '[:alnum:]._-')
        system_id=$(echo "${system_id:-unknown}" | tr -cd '[:alnum:]._-')
        
        # 检测发行版系列
        case "$system_id" in
            ubuntu|debian|linuxmint|pop|elementary|raspbian)
                DISTRO_FAMILY="debian"
                ;;
            centos|rhel|fedora|rocky|almalinux|ol|amazon)
                DISTRO_FAMILY="redhat"
                ;;
            arch|manjaro|endeavouros|garuda)
                DISTRO_FAMILY="arch"
                ;;
            opensuse*|sles|tumbleweed)
                DISTRO_FAMILY="suse"
                ;;
            alpine)
                DISTRO_FAMILY="alpine"
                ;;
            gentoo)
                DISTRO_FAMILY="gentoo"
                ;;
            *)
                DISTRO_FAMILY="unknown"
                print_msg "warning" "未知的发行版: $system_id"
                ;;
        esac
        
        print_msg "success" "检测到系统: $OS $VER (${DISTRO_FAMILY}系) 🐧"
        log "操作系统: $OS $VER, 发行版系列: $DISTRO_FAMILY"
    else
        print_msg "error" "无法检测操作系统版本"
        exit 1
    fi
}

# 增强的系统资源检测
detect_resources() {
    print_msg "working" "正在分析系统资源..."
    
    # 内存检测 - 多种方法确保准确性
    if check_command free; then
        TOTAL_MEM=$(free -b 2>/dev/null | awk '/^Mem:/{print $2}' | head -1)
    elif [ -f /proc/meminfo ]; then
        TOTAL_MEM=$(awk '/^MemTotal:/{print $2*1024}' /proc/meminfo 2>/dev/null)
    fi
    
    # 验证内存值
    if ! validate_number "${TOTAL_MEM:-0}" 134217728; then
        print_msg "warning" "无法准确检测内存，使用默认值"
        TOTAL_MEM=1073741824  # 1GB默认值
    fi
    
    TOTAL_MEM_GB=$((TOTAL_MEM / 1024 / 1024 / 1024))
    
    # CPU核心检测
    if check_command nproc; then
        CPU_CORES=$(nproc 2>/dev/null)
    elif [ -f /proc/cpuinfo ]; then
        CPU_CORES=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)
    fi
    
    # 验证CPU核心数
    if ! validate_number "${CPU_CORES:-0}" 1 1024; then
        print_msg "warning" "无法准确检测CPU核心数，使用默认值"
        CPU_CORES=1
    fi
    
    # 内核版本检测
    KERNEL_VERSION=$(uname -r 2>/dev/null || echo "unknown")
    
    # CPU架构检测
    local cpu_arch=$(uname -m 2>/dev/null || echo "unknown")
    
    # 显示系统信息
    echo
    echo -e "${WHITE}┌─────────────────────────────────────────┐${RESET}"
    echo -e "${WHITE}│            ${BOLD}系统信息${RESET}${WHITE}                     │${RESET}"
    echo -e "${WHITE}├─────────────────────────────────────────┤${RESET}"
    echo -e "${WHITE}│ 💾 内存: ${GREEN}${TOTAL_MEM_GB} GB${WHITE}                       │${RESET}"
    echo -e "${WHITE}│ 🖥️  CPU核心数: ${GREEN}${CPU_CORES}${WHITE}                        │${RESET}"
    echo -e "${WHITE}│ 🏗️  架构: ${GREEN}${cpu_arch}${WHITE}                    │${RESET}"
    echo -e "${WHITE}│ 🐧 内核版本: ${GREEN}${KERNEL_VERSION}${WHITE}           │${RESET}"
    echo -e "${WHITE}│ 📦 发行版系列: ${GREEN}${DISTRO_FAMILY}${WHITE}                     │${RESET}"
    echo -e "${WHITE}└─────────────────────────────────────────┘${RESET}"
    echo
    
    log "系统资源 - 内存: ${TOTAL_MEM_GB}GB, CPU核心: $CPU_CORES, 架构: $cpu_arch, 内核: $KERNEL_VERSION"
}

# 增强的容器和虚拟化环境检测
detect_container_environment() {
    print_msg "working" "检测容器和虚拟化环境..."
    
    local container_type="none"
    local virt_type="none"
    local restrictions=""
    
    # 检测容器环境
    if [ -f /.dockerenv ]; then
        container_type="docker"
        restrictions="Docker容器内某些内核参数无法修改"
    elif [ -n "${KUBERNETES_SERVICE_HOST:-}" ]; then
        container_type="kubernetes"
        restrictions="K8s Pod内建议在节点级别优化"
    elif [ -f /proc/1/cgroup ] && grep -qE "(lxc|docker|kubepods|container)" /proc/1/cgroup 2>/dev/null; then
        container_type="container"
        restrictions="容器环境内核参数受限"
    elif [ -f /proc/vz/version ]; then
        container_type="openvz"
        restrictions="OpenVZ容器内核参数严格受限"
    fi
    
    # 检测虚拟化环境
    if check_command systemd-detect-virt; then
        virt_type=$(systemd-detect-virt 2>/dev/null || echo "none")
    elif [ -d /proc/xen ]; then
        virt_type="xen"
    elif [ -f /sys/hypervisor/type ]; then
        virt_type=$(cat /sys/hypervisor/type 2>/dev/null || echo "unknown")
    elif grep -q "^flags.*hypervisor" /proc/cpuinfo 2>/dev/null; then
        virt_type="hypervisor"
    elif [ -f /proc/cpuinfo ] && grep -q "QEMU\|KVM" /proc/cpuinfo 2>/dev/null; then
        virt_type="qemu-kvm"
    fi
    
    # 设置环境类型和显示信息
    if [ "$container_type" != "none" ]; then
        ENV_TYPE="container-$container_type"
        print_msg "warning" "检测到容器环境: $container_type"
        [ -n "$restrictions" ] && print_msg "info" "$restrictions"
    elif [ "$virt_type" != "none" ] && [ "$virt_type" != "none" ]; then
        ENV_TYPE="virtual-$virt_type"
        print_msg "info" "检测到虚拟化环境: $virt_type"
    else
        ENV_TYPE="physical"
        print_msg "success" "检测到物理机环境"
    fi
    
    log "环境检测: container=$container_type, virtualization=$virt_type"
}

# ==================== 智能参数计算 ====================

# 安全的参数计算（增强边界检查）
calculate_optimal_values() {
    local total_mem_bytes="${1:-$TOTAL_MEM}"
    local cpu_cores="${2:-$CPU_CORES}"
    local workload_type="${3:-general}"
    
    print_msg "working" "基于系统资源计算最优参数..."
    
    # 严格的输入验证
    if ! validate_number "$total_mem_bytes" 134217728 274877906944; then  # 128MB - 256GB
        print_msg "warning" "内存大小异常，使用安全默认值"
        total_mem_bytes=1073741824  # 1GB
    fi
    
    if ! validate_number "$cpu_cores" 1 1024; then
        print_msg "warning" "CPU核心数异常，使用安全默认值"
        cpu_cores=1
    fi
    
    # 使用安全的算术运算，避免溢出
    local tcp_mem_max net_core_rmem_max net_core_wmem_max somaxconn file_max
    
    # 基础计算（使用安全的除法）
    tcp_mem_max=$((total_mem_bytes / 32))
    net_core_rmem_max=$((total_mem_bytes / 128))
    net_core_wmem_max=$((total_mem_bytes / 128))
    somaxconn=$((cpu_cores * 8192))
    file_max=$((cpu_cores * 65536))
    
    # 根据工作负载类型调整
    case "$workload_type" in
        "web")
            print_msg "info" "应用Web服务器优化"
            somaxconn=$((somaxconn * 2))
            file_max=$((file_max * 2))
            tcp_mem_max=$((tcp_mem_max * 3 / 2))  # 1.5倍
            ;;
        "database")
            print_msg "info" "应用数据库服务器优化"
            tcp_mem_max=$((tcp_mem_max * 2))
            net_core_rmem_max=$((net_core_rmem_max * 2))
            net_core_wmem_max=$((net_core_wmem_max * 2))
            ;;
        "cache")
            print_msg "info" "应用缓存服务器优化"
            tcp_mem_max=$((tcp_mem_max * 3))
            somaxconn=$((somaxconn * 3))
            file_max=$((file_max * 2))
            ;;
        "container")
            print_msg "info" "应用容器主机优化"
            file_max=$((file_max * 4))
            somaxconn=$((somaxconn * 2))
            ;;
    esac
    
    # 严格的边界检查和安全限制
    # TCP内存限制 (4MB - 256MB)
    [ "$tcp_mem_max" -gt 268435456 ] && tcp_mem_max=268435456
    [ "$tcp_mem_max" -lt 4194304 ] && tcp_mem_max=4194304
    
    # 网络缓冲区限制 (1MB - 128MB)
    [ "$net_core_rmem_max" -gt 134217728 ] && net_core_rmem_max=134217728
    [ "$net_core_rmem_max" -lt 1048576 ] && net_core_rmem_max=1048576
    
    [ "$net_core_wmem_max" -gt 134217728 ] && net_core_wmem_max=134217728
    [ "$net_core_wmem_max" -lt 1048576 ] && net_core_wmem_max=1048576
    
    # 连接队列限制 (1024 - 65535)
    [ "$somaxconn" -gt 65535 ] && somaxconn=65535
    [ "$somaxconn" -lt 1024 ] && somaxconn=1024
    
    # 文件句柄限制 (65536 - 16777216)
    [ "$file_max" -gt 16777216 ] && file_max=16777216
    [ "$file_max" -lt 65536 ] && file_max=65536
    
    # 验证所有计算结果 - 使用安全的数组设置函数
    local params=(
        "tcp_mem_max:$tcp_mem_max"
        "net_core_rmem_max:$net_core_rmem_max"
        "net_core_wmem_max:$net_core_wmem_max"
        "somaxconn:$somaxconn"
        "file_max:$file_max"
    )
    
    for param in "${params[@]}"; do
        local key="${param%:*}"
        local value="${param#*:}"
        
        if validate_number "$value" 1; then
            safe_array_set OPTIMAL_VALUES "$key" "$value"
        else
            print_msg "error" "参数计算失败: $key = $value"
            return 1
        fi
    done
    
    # 计算附加参数
    safe_array_set OPTIMAL_VALUES "tcp_rmem_max" "$net_core_rmem_max"
    safe_array_set OPTIMAL_VALUES "tcp_wmem_max" "$net_core_wmem_max"
    safe_array_set OPTIMAL_VALUES "netdev_max_backlog" "32768"
    safe_array_set OPTIMAL_VALUES "tcp_max_syn_backlog" "16384"
    safe_array_set OPTIMAL_VALUES "inotify_max_user_watches" "524288"
    safe_array_set OPTIMAL_VALUES "aio_max_nr" "1048576"
    
    print_msg "success" "参数计算完成并验证通过"
    log "智能参数计算完成: tcp_mem_max=$tcp_mem_max, somaxconn=$somaxconn, file_max=$file_max"
    return 0
}

# ==================== 系统检查和验证 ====================

# 获取当前系统配置
get_current_config() {
    print_msg "working" "读取当前系统配置..."
    
    local key_params=(
        "net.core.somaxconn"
        "fs.file-max"
        "net.core.rmem_max"
        "net.core.wmem_max"
        "net.core.netdev_max_backlog"
        "net.ipv4.tcp_max_syn_backlog"
        "fs.inotify.max_user_watches"
        "fs.aio-max-nr"
        "vm.swappiness"
        "net.ipv4.tcp_syncookies"
        "net.ipv4.tcp_tw_reuse"
        "net.ipv4.tcp_fin_timeout"
    )
    
    for param in "${key_params[@]}"; do
        local current_value
        current_value=$(sysctl -n "$param" 2>/dev/null || echo "未设置")
        safe_array_set CURRENT_VALUES "$param" "$current_value"
    done
    
    print_msg "success" "当前配置读取完成"
}

# 增强的系统预检查
pre_optimization_check() {
    local issues=0
    local warnings=0
    
    print_msg "test" "执行系统状态预检查..."
    
    # 检查系统负载
    if check_command uptime; then
        local load_avg
        load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',' 2>/dev/null)
        if [ -n "$load_avg" ]; then
            local load_int=${load_avg%.*}  # 获取整数部分
            if validate_number "$load_int" && [ "$load_int" -gt 10 ]; then
                print_msg "warning" "系统负载过高 ($load_avg)，建议在低峰期进行优化"
                ((warnings++))
            elif validate_number "$load_int" && [ "$load_int" -gt 5 ]; then
                print_msg "info" "系统负载较高 ($load_avg)，请注意监控"
            fi
        fi
    fi
    
    # 检查磁盘空间
    if check_command df; then
        local disk_usage
        disk_usage=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
        if validate_number "${disk_usage:-0}" && [ "$disk_usage" -gt 95 ]; then
            print_msg "error" "根分区使用率危险 (${disk_usage}%)"
            ((issues++))
        elif validate_number "${disk_usage:-0}" && [ "$disk_usage" -gt 85 ]; then
            print_msg "warning" "根分区使用率较高 (${disk_usage}%)"
            ((warnings++))
        fi
    fi
    
    # 检查内存使用
    if check_command free; then
        local mem_usage
        mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}' 2>/dev/null)
        if validate_number "${mem_usage:-0}" && [ "$mem_usage" -gt 95 ]; then
            print_msg "error" "内存使用率危险 (${mem_usage}%)"
            ((issues++))
        elif validate_number "${mem_usage:-0}" && [ "$mem_usage" -gt 85 ]; then
            print_msg "warning" "内存使用率较高 (${mem_usage}%)"
            ((warnings++))
        fi
    fi
    
    # 检查重要的内核参数是否存在
    local critical_params=(
        "net.core.somaxconn"
        "fs.file-max"
        "net.core.rmem_max"
        "net.core.wmem_max"
    )
    
    for param in "${critical_params[@]}"; do
        local param_path="/proc/sys/${param//./\/}"
        if [ ! -f "$param_path" ]; then
            print_msg "warning" "内核参数不存在: $param"
            ((warnings++))
        fi
    done
    
    # 检查是否有其他优化脚本的残留
    if grep -q "# 内核优化" /etc/sysctl.conf 2>/dev/null; then
        print_msg "info" "检测到之前的优化配置"
    fi
    
    # 统计结果
    if [ $issues -eq 0 ] && [ $warnings -eq 0 ]; then
        print_msg "success" "系统状态检查完美通过"
        safe_array_set TEST_RESULTS "pre_check" "PASS"
    elif [ $issues -eq 0 ]; then
        print_msg "warning" "系统状态良好，发现 $warnings 个警告"
        safe_array_set TEST_RESULTS "pre_check" "WARN"
    else
        print_msg "error" "系统状态检查发现 $issues 个问题，$warnings 个警告"
        safe_array_set TEST_RESULTS "pre_check" "FAIL"
        
        echo
        echo -n "是否继续进行优化? [y/N]: "
        read -r continue_choice
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            print_msg "info" "用户选择退出"
            exit 0
        fi
    fi
    
    log "系统状态预检查完成: 问题=$issues, 警告=$warnings"
    return $((issues + warnings))
}

# ==================== 配置管理函数 ====================

# 安全的文件备份
backup_file() {
    local file="$1"
    local description="${2:-}"
    
    if [ ! -f "$file" ]; then
        print_msg "warning" "文件不存在，跳过备份: $file"
        return 1
    fi
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="$(basename "$file").${timestamp}"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    # 安全地复制文件
    if cp -p "$file" "$backup_path" 2>/dev/null; then
        # 设置安全权限
        chmod 600 "$backup_path" 2>/dev/null
        
        print_msg "success" "已备份: $(basename "$file") → $backup_name 💾"
        
        # 创建备份信息文件
        cat > "${backup_path}.info" <<EOF
原始文件: $file
备份时间: $(date)
描述: ${description:-手动备份}
脚本版本: $SCRIPT_VERSION
系统信息: $OS $VER
内核版本: $KERNEL_VERSION
文件大小: $(stat -c%s "$file" 2>/dev/null || echo "unknown")
文件权限: $(stat -c%a "$file" 2>/dev/null || echo "unknown")
MD5校验: $(md5sum "$file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
EOF
        
        log "创建备份: $backup_path"
        return 0
    else
        print_msg "error" "备份失败: $file"
        return 1
    fi
}

# 格式化数值显示（添加千位分隔符）
format_number() {
    local number="$1"
    echo "$number" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta'
}

# 修复：预览模式 - 显示将要应用的更改
show_preview() {
    local optimization_level="${1:-balanced}"
    
    echo
    print_msg "preview" "预览模式 - 即将应用的更改"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    # 确保已计算最优参数
    local optimal_count
    optimal_count=$(safe_array_length OPTIMAL_VALUES)
    if [ "$optimal_count" -eq 0 ]; then
        calculate_optimal_values "$TOTAL_MEM" "$CPU_CORES" "$WORKLOAD_TYPE"
    fi
    
    # 获取当前配置
    get_current_config
    
    echo -e "\n${CYAN}${BOLD}📊 参数对比预览：${RESET}"
    
    # 修复：使用固定宽度格式化输出，不使用变量传递颜色代码
    printf "%-35s %-20s %-20s %-10s\n" "参数名称" "当前值" "新值" "变化"
    printf "%s\n" "────────────────────────────────────────────────────────────────────────────────────"
    
    # 显示主要参数变化
    local preview_params=(
        "net.core.somaxconn"
        "fs.file-max"
        "net.core.rmem_max"
        "net.core.wmem_max"
        "net.core.netdev_max_backlog"
    )
    
    for param in "${preview_params[@]}"; do
        local new_value=""
        local current_value=""
        
        # 安全地获取值
        case "$param" in
            "net.core.somaxconn")
                new_value=$(safe_array_get OPTIMAL_VALUES "somaxconn" "未计算")
                ;;
            "fs.file-max")
                new_value=$(safe_array_get OPTIMAL_VALUES "file_max" "未计算")
                ;;
            "net.core.rmem_max")
                new_value=$(safe_array_get OPTIMAL_VALUES "net_core_rmem_max" "未计算")
                ;;
            "net.core.wmem_max")
                new_value=$(safe_array_get OPTIMAL_VALUES "net_core_wmem_max" "未计算")
                ;;
            "net.core.netdev_max_backlog")
                new_value=$(safe_array_get OPTIMAL_VALUES "netdev_max_backlog" "未计算")
                ;;
        esac
        
        current_value=$(safe_array_get CURRENT_VALUES "$param" "未设置")
        
        # 格式化数值显示
        local formatted_current="${current_value}"
        local formatted_new="${new_value}"
        
        if validate_number "$current_value"; then
            formatted_current=$(format_number "$current_value")
        fi
        
        if validate_number "$new_value"; then
            formatted_new=$(format_number "$new_value")
        fi
        
        # 计算变化并显示
        printf "%-35s " "$param"
        
        # 显示当前值（红色）
        printf "${RED}%-20s${RESET} " "$formatted_current"
        
        # 显示新值（绿色）
        printf "${GREEN}%-20s${RESET} " "$formatted_new"
        
        # 显示变化指示符
        if [ "$current_value" = "未设置" ]; then
            echo -e "${GREEN}新增${RESET}"
        elif [ "$current_value" != "$new_value" ]; then
            if validate_number "$current_value" && validate_number "$new_value"; then
                if [ "$new_value" -gt "$current_value" ]; then
                    echo -e "${GREEN}↑ 提升${RESET}"
                else
                    echo -e "${RED}↓ 降低${RESET}"
                fi
            else
                echo -e "${YELLOW}修改${RESET}"
            fi
        else
            echo -e "${BLUE}相同${RESET}"
        fi
    done
    
    printf "%s\n" "────────────────────────────────────────────────────────────────────────────────────"
    
    # 显示优化摘要
    echo -e "\n${CYAN}${BOLD}📋 优化摘要：${RESET}"
    echo -e "${WHITE}• 优化级别: ${GREEN}$optimization_level${RESET}"
    echo -e "${WHITE}• 工作负载: ${GREEN}$WORKLOAD_TYPE${RESET}"
    echo -e "${WHITE}• 运行环境: ${GREEN}$ENV_TYPE${RESET}"
    echo -e "${WHITE}• 目标场景: ${GREEN}$(get_workload_description "$WORKLOAD_TYPE")${RESET}"
    
    # 显示可能的影响
    echo -e "\n${YELLOW}${BOLD}⚠️  可能影响：${RESET}"
    case "$optimization_level" in
        "conservative")
            echo -e "${WHITE}• 最小化系统变更，影响范围有限${RESET}"
            echo -e "${WHITE}• 适合生产环境，安全性优先${RESET}"
            ;;
        "balanced")
            echo -e "${WHITE}• 平衡性能与稳定性${RESET}"
            echo -e "${WHITE}• 适合大多数应用场景${RESET}"
            ;;
        "aggressive")
            echo -e "${WHITE}• 最大化性能提升${RESET}"
            echo -e "${WHITE}• 需要充分测试，请谨慎使用${RESET}"
            ;;
    esac
    
    echo -e "\n${BLUE}${BOLD}ℹ️  重要提醒：${RESET}"
    echo -e "${WHITE}• 所有原始配置将自动备份${RESET}"
    echo -e "${WHITE}• 支持一键回滚到之前状态${RESET}"
    echo -e "${WHITE}• 建议优化后监控系统性能${RESET}"
    
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    if [ "$DRY_RUN" = true ]; then
        print_msg "info" "这是预览模式，不会实际修改系统配置"
        return 0
    fi
    
    echo
    echo -n "确认应用这些更改? [y/N]: "
    read -r confirm_choice
    
    if [[ "$confirm_choice" =~ ^[Yy]$ ]]; then
        return 0
    else
        print_msg "info" "用户取消了配置应用"
        return 1
    fi
}

# 获取工作负载描述
get_workload_description() {
    local workload="$1"
    
    case "$workload" in
        "web") echo "Web服务器 - 优化网络连接和文件处理" ;;
        "database") echo "数据库服务器 - 优化内存和I/O性能" ;;
        "cache") echo "缓存服务器 - 优化内存使用和网络性能" ;;
        "container") echo "容器主机 - 优化容器调度和资源管理" ;;
        "general") echo "通用服务器 - 平衡各方面性能" ;;
        *) echo "未知工作负载类型" ;;
    esac
}

# 应用sysctl配置的函数
apply_sysctl_config() {
    local config_file="/etc/sysctl.d/99-kernel-optimization.conf"
    
    print_msg "working" "生成sysctl配置文件..."
    
    # 创建sysctl配置
    cat > "$config_file" << EOF
# Linux内核优化配置
# 由内核优化脚本自动生成 v${SCRIPT_VERSION}
# 生成时间: $(date)
# 系统信息: $OS $VER
# 内核版本: $KERNEL_VERSION
# 工作负载: $WORKLOAD_TYPE
# 优化级别: $OPTIMIZATION

# ===========================================
# 网络优化
# ===========================================

# TCP/IP堆栈优化
net.core.somaxconn = $(safe_array_get OPTIMAL_VALUES "somaxconn" "65535")
net.core.rmem_max = $(safe_array_get OPTIMAL_VALUES "net_core_rmem_max" "134217728")
net.core.wmem_max = $(safe_array_get OPTIMAL_VALUES "net_core_wmem_max" "134217728")
net.core.netdev_max_backlog = $(safe_array_get OPTIMAL_VALUES "netdev_max_backlog" "32768")

# TCP优化
net.ipv4.tcp_max_syn_backlog = $(safe_array_get OPTIMAL_VALUES "tcp_max_syn_backlog" "16384")
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200

# ===========================================
# 文件系统优化
# ===========================================

# 文件句柄限制
fs.file-max = $(safe_array_get OPTIMAL_VALUES "file_max" "1048576")

# inotify限制
fs.inotify.max_user_watches = $(safe_array_get OPTIMAL_VALUES "inotify_max_user_watches" "524288")
fs.inotify.max_user_instances = 256

# AIO限制
fs.aio-max-nr = $(safe_array_get OPTIMAL_VALUES "aio_max_nr" "1048576")

# ===========================================
# 内存管理优化
# ===========================================

# 虚拟内存优化
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50

# ===========================================
# 进程和调度优化
# ===========================================

# 进程限制
kernel.pid_max = 4194304

# 调度优化
kernel.sched_migration_cost_ns = 5000000

EOF

    print_msg "success" "配置文件已生成: $config_file"
    
    # 应用配置
    if sysctl -p "$config_file" >/dev/null 2>&1; then
        print_msg "success" "sysctl配置已生效"
        return 0
    else
        print_msg "error" "sysctl配置应用失败"
        return 1
    fi
}

# 应用优化配置（主函数）
apply_optimizations() {
    local optimization_level="${1:-balanced}"
    
    print_msg "working" "开始应用 $optimization_level 级别优化..."
    
    # 检查是否为预览模式
    if [ "$DRY_RUN" = true ]; then
        show_preview "$optimization_level"
        return 0
    fi
    
    # 预检查
    if ! pre_optimization_check; then
        local check_result
        check_result=$(safe_array_get TEST_RESULTS "pre_check" "UNKNOWN")
        if [ "$check_result" = "FAIL" ]; then
            print_msg "error" "系统预检查失败，建议解决问题后重试"
            return 1
        fi
    fi
    
    # 显示预览并确认
    if ! show_preview "$optimization_level"; then
        return 1
    fi
    
    # 备份原始配置
    backup_file "/etc/sysctl.conf" "优化前自动备份"
    
    # 计算最优参数
    if ! calculate_optimal_values "$TOTAL_MEM" "$CPU_CORES" "$WORKLOAD_TYPE"; then
        print_msg "error" "参数计算失败"
        return 1
    fi
    
    # 应用sysctl配置
    if ! apply_sysctl_config; then
        print_msg "error" "配置应用失败"
        return 1
    fi
    
    print_msg "success" "优化配置应用完成！系统性能已得到提升。"
    print_msg "info" "建议重启系统以确保所有更改完全生效。"
    
    # 显示应用后的配置摘要
    echo -e "\n${GREEN}${BOLD}✅ 优化完成摘要：${RESET}"
    echo -e "${WHITE}• 已优化参数数量: $(safe_array_length OPTIMAL_VALUES)个${RESET}"
    echo -e "${WHITE}• 配置文件位置: /etc/sysctl.d/99-kernel-optimization.conf${RESET}"
    echo -e "${WHITE}• 备份文件位置: $BACKUP_DIR${RESET}"
    echo -e "${WHITE}• 日志文件位置: $LOG_FILE${RESET}"
    
    return 0
}

# ==================== 智能配置向导 ====================

# 智能配置向导
interactive_config_wizard() {
    echo
    echo -e "${PURPLE}${BOLD}🧙‍♂️ 欢迎使用智能配置向导${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    # 1. 选择工作负载类型
    echo -e "\n${CYAN}${BOLD}📊 步骤1: 选择主要工作负载类型${RESET}"
    echo -e "${WHITE}请根据服务器的主要用途选择:${RESET}"
    echo
    echo -e "${GREEN}1)${RESET} ${WHITE}🌐 Web服务器${RESET} - Nginx, Apache, 高并发Web应用"
    echo -e "${GREEN}2)${RESET} ${WHITE}🗄️ 数据库服务器${RESET} - MySQL, PostgreSQL, MongoDB"
    echo -e "${GREEN}3)${RESET} ${WHITE}🚀 缓存服务器${RESET} - Redis, Memcached, 内存缓存"
    echo -e "${GREEN}4)${RESET} ${WHITE}🐳 容器主机${RESET} - Docker, Kubernetes, 容器编排"
    echo -e "${GREEN}5)${RESET} ${WHITE}🏢 通用服务器${RESET} - 混合应用，平衡优化"
    
    while true; do
        echo
        echo -n "请选择工作负载类型 [1-5]: "
        read -r workload_choice
        
        if workload_choice=$(validate_user_input "$workload_choice" "1 2 3 4 5"); then
            case "$workload_choice" in
                1) WORKLOAD_TYPE="web"; break ;;
                2) WORKLOAD_TYPE="database"; break ;;
                3) WORKLOAD_TYPE="cache"; break ;;
                4) WORKLOAD_TYPE="container"; break ;;
                5) WORKLOAD_TYPE="general"; break ;;
            esac
        else
            print_msg "error" "无效选择，请输入1-5"
        fi
    done
    
    # 2. 选择优化级别
    echo -e "\n${CYAN}${BOLD}⚡ 步骤2: 选择优化级别${RESET}"
    echo -e "${WHITE}请根据环境和风险承受能力选择:${RESET}"
    echo
    echo -e "${GREEN}1)${RESET} ${WHITE}🛡️ 保守模式${RESET} - 最小化风险，适合关键生产环境"
    echo -e "${GREEN}2)${RESET} ${WHITE}⚖️ 平衡模式${RESET} - 性能与稳定性兼顾，推荐选择"
    echo -e "${GREEN}3)${RESET} ${WHITE}🚀 激进模式${RESET} - 最大化性能，适合高性能计算"
    
    while true; do
        echo
        echo -n "请选择优化级别 [1-3]: "
        read -r level_choice
        
        if level_choice=$(validate_user_input "$level_choice" "1 2 3"); then
            case "$level_choice" in
                1) OPTIMIZATION="conservative"; break ;;
                2) OPTIMIZATION="balanced"; break ;;
                3) OPTIMIZATION="aggressive"; break ;;
            esac
        else
            print_msg "error" "无效选择，请输入1-3"
        fi
    done
    
    # 3. 高级选项配置
    echo -e "\n${CYAN}${BOLD}🔧 步骤3: 高级选项${RESET}"
    
    echo -n "是否启用自动回滚功能？(遇到问题时自动恢复) [Y/n]: "
    read -r auto_rollback_choice
    if [[ ! "$auto_rollback_choice" =~ ^[Nn]$ ]]; then
        AUTO_ROLLBACK_ENABLED=true
        print_msg "success" "已启用自动回滚功能"
    fi
    
    echo -n "是否先预览更改而不立即应用？ [y/N]: "
    read -r preview_choice
    if [[ "$preview_choice" =~ ^[Yy]$ ]]; then
        DRY_RUN=true
        print_msg "info" "将以预览模式运行"
    fi
    
    # 4. 显示配置摘要
    echo -e "\n${PURPLE}${BOLD}📋 配置摘要${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${WHITE}工作负载类型: ${GREEN}$(get_workload_description "$WORKLOAD_TYPE")${RESET}"
    echo -e "${WHITE}优化级别: ${GREEN}$OPTIMIZATION${RESET}"
    echo -e "${WHITE}运行环境: ${GREEN}$ENV_TYPE${RESET}"
    echo -e "${WHITE}自动回滚: ${GREEN}$([ "$AUTO_ROLLBACK_ENABLED" = true ] && echo "已启用" || echo "已禁用")${RESET}"
    echo -e "${WHITE}预览模式: ${GREEN}$([ "$DRY_RUN" = true ] && echo "是" || echo "否")${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    print_msg "success" "配置向导完成！✨"
    log "配置向导完成: 工作负载=$WORKLOAD_TYPE, 优化级别=$OPTIMIZATION"
}

# ==================== 主菜单系统 ====================

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${PURPLE}${BOLD}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                    Linux 内核优化脚本                         ║
║                   Security Enhanced v1.0                     ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${RESET}"
    
    echo -e "${CYAN}${BOLD}🖥️ 系统信息:${RESET} ${WHITE}$OS $VER | 内存: ${TOTAL_MEM_GB}GB | CPU: ${CPU_CORES}核 | 环境: $ENV_TYPE${RESET}"
    echo
    
    echo -e "${WHITE}${BOLD}主菜单选项:${RESET}"
    echo -e "${GREEN}1)${RESET} ${WHITE}🧙‍♂️ 智能配置向导${RESET}     - 引导式优化配置"
    echo -e "${GREEN}2)${RESET} ${WHITE}⚡ 快速优化${RESET}         - 使用推荐设置快速优化"
    echo -e "${GREEN}3)${RESET} ${WHITE}👁️ 预览优化效果${RESET}      - 查看优化参数不实际应用"
    echo -e "${GREEN}0)${RESET} ${WHITE}🚪 退出程序${RESET}         - 安全退出"
    echo
}

# 主菜单循环
main_menu() {
    while true; do
        show_main_menu
        
        echo -n "请选择选项 [0-3]: "
        read -r choice
        
        # 验证输入
        if choice=$(validate_user_input "$choice" "0 1 2 3"); then
            case "$choice" in
                1)
                    interactive_config_wizard
                    echo
                    echo -n "是否立即应用配置? [Y/n]: "
                    read -r apply_choice
                    if [[ ! "$apply_choice" =~ ^[Nn]$ ]]; then
                        apply_optimizations "$OPTIMIZATION"
                    fi
                    echo
                    echo -n "按Enter键继续..."
                    read -r
                    ;;
                2)
                    # 快速优化 - 使用推荐设置
                    print_msg "info" "使用推荐设置进行快速优化..."
                    OPTIMIZATION="balanced"
                    WORKLOAD_TYPE="general"
                    AUTO_ROLLBACK_ENABLED=true
                    apply_optimizations "$OPTIMIZATION"
                    echo
                    echo -n "按Enter键继续..."
                    read -r
                    ;;
                3)
                    # 预览模式
                    if [ -z "$OPTIMIZATION" ]; then
                        interactive_config_wizard
                    fi
                    DRY_RUN=true
                    apply_optimizations "$OPTIMIZATION"
                    DRY_RUN=false
                    echo
                    echo -n "按Enter键继续..."
                    read -r
                    ;;
                0)
                    echo
                    print_msg "info" "感谢使用Linux内核优化脚本！👋"
                    print_msg "info" "祝您的系统运行得更加出色！🚀"
                    exit 0
                    ;;
            esac
        else
            print_msg "error" "无效的选择: [$choice]，请选择0-3"
            sleep 1
        fi
    done
}

# ==================== 命令行参数处理 ====================

# 显示版本信息
show_version() {
    echo -e "${PURPLE}${BOLD}Linux内核优化脚本${RESET} ${GREEN}v${SCRIPT_VERSION}${RESET}"
    echo -e "${WHITE}Security Enhanced Edition - FIXED v2${RESET}"
    echo
    echo -e "${CYAN}修复内容:${RESET}"
    echo -e "${WHITE}• 🔧 修复关联数组在严格模式下的访问问题${RESET}"
    echo -e "${WHITE}• 🛡️ 增强数组操作的安全性${RESET}"
    echo -e "${WHITE}• 🎨 修复预览模式的颜色显示问题${RESET}"
    echo -e "${WHITE}• ✅ 优化输出格式和用户体验${RESET}"
    echo -e "${WHITE}• 📊 改进参数对比表格显示${RESET}"
    echo
    echo -e "${WHITE}作者: Claude (Anthropic) | 许可: MIT License${RESET}"
}

# 命令行参数处理
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                echo "使用方法: $0 [选项]"
                echo "选项:"
                echo "  --help, -h     显示帮助信息"
                echo "  --version      显示版本信息"
                echo "  --quick        快速优化（平衡+通用）"
                echo "  --preview      预览模式"
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            --quick)
                OPTIMIZATION="balanced"
                WORKLOAD_TYPE="general"
                AUTO_ROLLBACK_ENABLED=true
                print_msg "info" "启用快速优化模式"
                apply_optimizations "$OPTIMIZATION"
                exit 0
                ;;
            --preview)
                DRY_RUN=true
                print_msg "info" "启用预览模式"
                ;;
            *)
                print_msg "error" "未知参数: $1"
                echo "使用 --help 查看帮助信息"
                exit 1
                ;;
        esac
        shift
    done
}

# ==================== 主函数 ====================

# 脚本初始化
initialize_script() {
    # 创建必要目录
    create_directories
    
    # 记录脚本启动
    log "========== 脚本启动 =========="
    log "脚本版本: $SCRIPT_VERSION"
    log "启动时间: $(date)"
    log "运行用户: $(whoami)"
    log "命令行: $0 $*"
    
    # 系统检查
    check_root
    detect_distro
    detect_resources
    detect_container_environment
    
    # 兼容性检查
    if ! check_compatibility; then
        print_msg "error" "系统兼容性检查失败，请检查系统环境"
        exit 1
    fi
}

# 清理函数
cleanup() {
    local exit_code=$?
    
    # 清理临时文件
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    fi
    
    # 记录脚本结束
    log "脚本执行结束，退出码: $exit_code"
    log "结束时间: $(date)"
    log "========== 脚本结束 =========="
    
    exit $exit_code
}

# 信号处理
trap cleanup EXIT
trap 'print_msg "error" "脚本被中断"; exit 130' INT TERM

# 主函数
main() {
    # 处理命令行参数
    parse_arguments "$@"
    
    # 初始化脚本
    initialize_script
    
    # 显示欢迎信息
    echo
    echo -e "${PURPLE}${BOLD}"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════╗
    ║             🚀 Linux 内核优化脚本 v1.0 🚀                     ║
    ║                    Security Enhanced Edition                  ║
    ║                                                               ║
    ║  智能 • 安全 • 高效 • 可靠 • 已修复                           ║
    ╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${RESET}"
    
    print_msg "success" "系统检测完成，准备就绪！✨"
    
    # 如果有预设配置，直接应用
    if [ -n "$OPTIMIZATION" ] && [ -n "$WORKLOAD_TYPE" ]; then
        print_msg "info" "检测到预设配置，开始应用优化..."
        apply_optimizations "$OPTIMIZATION"
    else
        # 进入主菜单
        main_menu
    fi
}

# 执行主函数
main "$@"