#!/bin/bash
# Linux 内核优化脚本
# BY BuBuXSY
# Version: 2025.07.19 


set -euo pipefail  # 严格模式：遇到错误立即退出

# 颜色和样式定义
readonly RED="\e[1;31m"
readonly GREEN="\e[1;32m"
readonly YELLOW="\e[1;33m"
readonly BLUE="\e[1;34m"
readonly PURPLE="\e[1;35m"
readonly CYAN="\e[1;36m"
readonly WHITE="\e[1;37m"
readonly BOLD="\e[1m"
readonly RESET="\e[0m"

# 全局配置
readonly LOG_FILE="/var/log/kernel_optimization.log"
readonly BACKUP_DIR="/var/backups/kernel_optimization"
readonly VERSION_DIR="/etc/kernel_optimization/versions"
readonly BENCHMARK_DIR="/var/log/kernel_optimization/benchmarks"
readonly EXPORT_DIR="/root/kernel_optimization_exports"
readonly TEMP_DIR="/tmp/kernel_optimization"

# 脚本版本和元信息
readonly SCRIPT_VERSION="5.0"
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

# 优化参数存储
declare -A OPTIMAL_VALUES
declare -A TEST_RESULTS
declare -A CURRENT_VALUES

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
    
    # 检查内核版本
    local kernel_ver=$(uname -r | cut -d. -f1,2)
    local min_ver_num=$(echo "$MIN_KERNEL_VERSION" | tr -d '.')
    local cur_ver_num=$(echo "$kernel_ver" | tr -d '.')
    
    if [ "${cur_ver_num:-0}" -lt "${min_ver_num:-0}" ]; then
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

# 安全的发行版检测（移除eval风险）
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
    
    # 验证所有计算结果
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
            OPTIMAL_VALUES["$key"]="$value"
        else
            print_msg "error" "参数计算失败: $key = $value"
            return 1
        fi
    done
    
    # 计算附加参数
    OPTIMAL_VALUES["tcp_rmem_max"]="$net_core_rmem_max"
    OPTIMAL_VALUES["tcp_wmem_max"]="$net_core_wmem_max"
    OPTIMAL_VALUES["netdev_max_backlog"]="32768"
    OPTIMAL_VALUES["tcp_max_syn_backlog"]="16384"
    OPTIMAL_VALUES["inotify_max_user_watches"]="524288"
    OPTIMAL_VALUES["aio_max_nr"]="1048576"
    
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
        CURRENT_VALUES["$param"]="$current_value"
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
        TEST_RESULTS["pre_check"]="PASS"
    elif [ $issues -eq 0 ]; then
        print_msg "warning" "系统状态良好，发现 $warnings 个警告"
        TEST_RESULTS["pre_check"]="WARN"
    else
        print_msg "error" "系统状态检查发现 $issues 个问题，$warnings 个警告"
        TEST_RESULTS["pre_check"]="FAIL"
        
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

# 预览模式 - 显示将要应用的更改
show_preview() {
    local optimization_level="${1:-balanced}"
    
    echo
    print_msg "preview" "预览模式 - 即将应用的更改"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    # 确保已计算最优参数
    if [ ${#OPTIMAL_VALUES[@]} -eq 0 ]; then
        calculate_optimal_values "$TOTAL_MEM" "$CPU_CORES" "$WORKLOAD_TYPE"
    fi
    
    # 获取当前配置
    get_current_config
    
    echo -e "\n${CYAN}${BOLD}📊 参数对比预览：${RESET}"
    printf "${WHITE}%-30s %-15s %-15s %-10s${RESET}\n" "参数名称" "当前值" "新值" "变化"
    echo -e "${WHITE}──────────────────────────────────────────────────────────────────────────${RESET}"
    
    # 显示主要参数变化
    local preview_params=(
        "net.core.somaxconn:${OPTIMAL_VALUES["somaxconn"]}"
        "fs.file-max:${OPTIMAL_VALUES["file_max"]}"
        "net.core.rmem_max:${OPTIMAL_VALUES["net_core_rmem_max"]}"
        "net.core.wmem_max:${OPTIMAL_VALUES["net_core_wmem_max"]}"
        "net.core.netdev_max_backlog:${OPTIMAL_VALUES["netdev_max_backlog"]}"
    )
    
    for param_pair in "${preview_params[@]}"; do
        local param="${param_pair%:*}"
        local new_value="${param_pair#*:}"
        local current_value="${CURRENT_VALUES[$param]:-未设置}"
        
        # 计算变化
        local change_indicator=""
        if [ "$current_value" = "未设置" ]; then
            change_indicator="${GREEN}新增${RESET}"
        elif [ "$current_value" != "$new_value" ]; then
            if validate_number "$current_value" && validate_number "$new_value"; then
                if [ "$new_value" -gt "$current_value" ]; then
                    change_indicator="${GREEN}↑${RESET}"
                else
                    change_indicator="${RED}↓${RESET}"
                fi
            else
                change_indicator="${YELLOW}修改${RESET}"
            fi
        else
            change_indicator="${BLUE}相同${RESET}"
        fi
        
        printf "${WHITE}%-30s${RESET} ${RED}%-15s${RESET} ${GREEN}%-15s${RESET} %-10s\n" \
               "$param" "$current_value" "$new_value" "$change_indicator"
    done
    
    echo -e "${WHITE}──────────────────────────────────────────────────────────────────────────${RESET}"
    
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

# 安全的sysctl配置应用
safe_sysctl_apply() {
    local config_file="$1"
    local errors=0
    local applied=0
    
    print_msg "working" "验证并应用sysctl配置..."
    
    if [ ! -f "$config_file" ]; then
        print_msg "error" "配置文件不存在: $config_file"
        return 1
    fi
    
    # 创建临时验证文件
    local temp_verify
    temp_verify=$(mktemp "$TEMP_DIR/verify.XXXXXX") || {
        print_msg "error" "无法创建临时验证文件"
        return 1
    }
    
    # 逐行验证和准备配置
    while IFS= read -r line; do
        # 跳过注释和空行
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # 验证参数格式 - 更严格的正则表达式
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9._-]+)[[:space:]]*=[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
            local param="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            local param_path="/proc/sys/${param//./\/}"
            
            # 检查参数是否存在
            if [ -f "$param_path" ]; then
                # 检查当前值
                local current_value
                current_value=$(cat "$param_path" 2>/dev/null || echo "unknown")
                
                # 验证新值是否合理
                if validate_number "$value" 0; then
                    echo "$line" >> "$temp_verify"
                    print_msg "info" "✓ $param: $current_value → $value"
                else
                    print_msg "warning" "✗ 无效值: $param = $value"
                    ((errors++))
                fi
            else
                print_msg "warning" "✗ 参数不存在: $param"
                ((errors++))
            fi
        elif [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9._-]+)[[:space:]]*=[[:space:]]*([a-zA-Z0-9 ._-]+)[[:space:]]*$ ]]; then
            # 处理非数字参数
            local param="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            local param_path="/proc/sys/${param//./\/}"
            
            if [ -f "$param_path" ]; then
                echo "$line" >> "$temp_verify"
                print_msg "info" "✓ $param = $value"
            else
                print_msg "warning" "✗ 参数不存在: $param"
                ((errors++))
            fi
        else
            print_msg "warning" "✗ 无效格式: $line"
            ((errors++))
        fi
    done < "$config_file"
    
    # 检查验证结果
    if [ $errors -gt 0 ]; then
        print_msg "warning" "配置验证发现 $errors 个问题"
        echo -n "是否忽略错误继续应用? [y/N]: "
        read -r ignore_errors
        if [[ ! "$ignore_errors" =~ ^[Yy]$ ]]; then
            rm -f "$temp_verify"
            return 1
        fi
    fi
    
    # 应用验证通过的配置
    if [ -s "$temp_verify" ]; then
        print_msg "working" "应用sysctl配置..."
        
        if sysctl -p "$temp_verify" >/dev/null 2>&1; then
            applied=$(wc -l < "$temp_verify")
            print_msg "success" "成功应用 $applied 个参数配置"
            rm -f "$temp_verify"
            return 0
        else
            print_msg "error" "sysctl配置应用失败"
            
            # 尝试逐个应用，找出有问题的参数
            print_msg "working" "尝试逐个应用参数..."
            local line_num=0
            while IFS= read -r line; do
                ((line_num++))
                if ! sysctl "$line" >/dev/null 2>&1; then
                    print_msg "warning" "第 $line_num 行应用失败: $line"
                else
                    ((applied++))
                fi
            done < "$temp_verify"
            
            rm -f "$temp_verify"
            
            if [ $applied -gt 0 ]; then
                print_msg "warning" "部分应用成功: $applied 个参数"
                return 0
            else
                print_msg "error" "没有参数成功应用"
                return 1
            fi
        fi
    else
        print_msg "warning" "没有有效的配置可以应用"
        rm -f "$temp_verify"
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
        local check_result="${TEST_RESULTS["pre_check"]:-UNKNOWN}"
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
    
    # 创建安全的临时配置文件
    local temp_config
    temp_config=$(mktemp "$TEMP_DIR/sysctl_optimized.XXXXXX.conf") || {
        print_msg "error" "无法创建临时配置文件"
        return 1
    }
    
    # 设置安全权限
    chmod 600 "$temp_config"
    
    # 生成优化配置
    cat > "$temp_config" <<EOF
# Linux内核优化配置 - 安全增强版
# 生成时间: $(date)
# 脚本版本: $SCRIPT_VERSION
# 优化级别: $optimization_level
# 工作负载: $WORKLOAD_TYPE
# 系统信息: $OS $VER ($DISTRO_FAMILY)
# 内核版本: $KERNEL_VERSION
# 运行环境: $ENV_TYPE

# ==================== 网络核心设置 ====================
net.core.somaxconn = ${OPTIMAL_VALUES["somaxconn"]}
net.core.netdev_max_backlog = ${OPTIMAL_VALUES["netdev_max_backlog"]}
net.core.rmem_max = ${OPTIMAL_VALUES["net_core_rmem_max"]}
net.core.wmem_max = ${OPTIMAL_VALUES["net_core_wmem_max"]}
net.core.rmem_default = 262144
net.core.wmem_default = 262144

# ==================== TCP设置 ====================
net.ipv4.tcp_rmem = 4096 87380 ${OPTIMAL_VALUES["net_core_rmem_max"]}
net.ipv4.tcp_wmem = 4096 65536 ${OPTIMAL_VALUES["net_core_wmem_max"]}
net.ipv4.tcp_mem = 786432 1048576 ${OPTIMAL_VALUES["tcp_mem_max"]}
net.ipv4.tcp_max_syn_backlog = ${OPTIMAL_VALUES["tcp_max_syn_backlog"]}
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.ip_local_port_range = 1024 65535

# ==================== 文件系统设置 ====================
fs.file-max = ${OPTIMAL_VALUES["file_max"]}
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = ${OPTIMAL_VALUES["inotify_max_user_watches"]}
fs.aio-max-nr = ${OPTIMAL_VALUES["aio_max_nr"]}

# ==================== 安全设置 ====================
kernel.randomize_va_space = 2
kernel.core_uses_pid = 1
fs.suid_dumpable = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# ==================== 内存管理 ====================
EOF

    # 根据优化级别添加额外设置
    case "$optimization_level" in
        "conservative")
            cat >> "$temp_config" <<'EOF'
# 保守优化设置
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
vm.swappiness = 10
EOF
            ;;
        "balanced")
            cat >> "$temp_config" <<'EOF'
# 平衡优化设置
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.swappiness = 5
EOF
            ;;
        "aggressive")
            cat >> "$temp_config" <<'EOF'
# 激进优化设置
vm.dirty_ratio = 10
vm.dirty_background_ratio = 3
vm.swappiness = 1
vm.vfs_cache_pressure = 50
EOF
            ;;
    esac
    
    # 根据工作负载添加专门设置
    case "$WORKLOAD_TYPE" in
        "web")
            cat >> "$temp_config" <<'EOF'

# Web服务器专用优化
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1
EOF
            ;;
        "database")
            cat >> "$temp_config" <<'EOF'

# 数据库服务器专用优化
kernel.shmmax = 68719476736
kernel.shmall = 4294967296
EOF
            ;;
        "cache")
            cat >> "$temp_config" <<'EOF'

# 缓存服务器专用优化
net.ipv4.tcp_max_tw_buckets = 6000
vm.overcommit_memory = 1
EOF
            ;;
    esac
    
    # 应用配置
    if safe_sysctl_apply "$temp_config"; then
        # 将配置添加到系统配置文件
        echo -e "\n# === 内核优化配置 ($(date)) ===" >> /etc/sysctl.conf
        cat "$temp_config" >> /etc/sysctl.conf
        
        print_msg "success" "优化设置应用成功！🎉"
        
        # 显示应用的关键参数
        echo
        echo -e "${CYAN}${BOLD}📊 已应用的关键参数：${RESET}"
        echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        printf "${WHITE}%-30s ${GREEN}%15s${RESET}\n" "网络连接队列" "${OPTIMAL_VALUES["somaxconn"]}"
        printf "${WHITE}%-30s ${GREEN}%15s${RESET}\n" "文件句柄限制" "${OPTIMAL_VALUES["file_max"]}"
        printf "${WHITE}%-30s ${GREEN}%15s${RESET}\n" "网络接收缓冲(MB)" "$((${OPTIMAL_VALUES["net_core_rmem_max"]} / 1024 / 1024))"
        printf "${WHITE}%-30s ${GREEN}%15s${RESET}\n" "TCP内存限制(MB)" "$((${OPTIMAL_VALUES["tcp_mem_max"]} / 1024 / 1024))"
        printf "${WHITE}%-30s ${GREEN}%15s${RESET}\n" "优化级别" "$optimization_level"
        printf "${WHITE}%-30s ${GREEN}%15s${RESET}\n" "工作负载" "$WORKLOAD_TYPE"
        echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        
        # 保存版本
        version_control "应用优化设置: $optimization_level 级别, 工作负载: $WORKLOAD_TYPE"
        
        # 清理临时文件
        rm -f "$temp_config"
        
        # 给出后续建议
        echo
        print_msg "info" "🔍 建议接下来："
        echo -e "${WHITE}• 监控系统性能和稳定性${RESET}"
        echo -e "${WHITE}• 运行性能测试验证效果${RESET}"
        echo -e "${WHITE}• 如有问题可使用回滚功能${RESET}"
        
        log "优化配置应用成功: $optimization_level 级别, 工作负载: $WORKLOAD_TYPE"
        return 0
    else
        print_msg "error" "配置应用失败"
        rm -f "$temp_config"
        return 1
    fi
}

# 版本控制增强
version_control() {
    local description="${1:-自动保存}"
    local version="v$(date +%Y%m%d_%H%M%S)"
    local version_dir="$VERSION_DIR/$version"
    
    if mkdir -p "$version_dir" 2>/dev/null; then
        # 保存当前配置
        local config_files=(
            "/etc/sysctl.conf"
            "/etc/security/limits.conf"
            "/etc/systemd/system.conf"
        )
        
        for config_file in "${config_files[@]}"; do
            if [ -f "$config_file" ]; then
                if cp "$config_file" "$version_dir/" 2>/dev/null; then
                    # 计算文件校验和
                    md5sum "$config_file" >> "$version_dir/checksums.md5" 2>/dev/null
                fi
            fi
        done
        
        # 保存系统状态
        {
            echo "# 系统状态快照 - $version"
            echo "Date: $(date)"
            echo "Uptime: $(uptime)"
            echo "Kernel: $(uname -a)"
            echo "Load: $(cat /proc/loadavg 2>/dev/null || echo 'N/A')"
            echo "Memory: $(free -h 2>/dev/null || echo 'N/A')"
            echo "Disk: $(df -h / 2>/dev/null || echo 'N/A')"
        } > "$version_dir/system_state.txt"
        
        # 保存当前sysctl参数
        sysctl -a > "$version_dir/current_sysctl.conf" 2>/dev/null || true
        
        # 记录详细版本信息
        cat > "$version_dir/info.txt" <<EOF
版本: $version
创建时间: $(date)
脚本版本: $SCRIPT_VERSION
优化级别: ${OPTIMIZATION:-未知}
工作负载: ${WORKLOAD_TYPE:-未知}
系统信息: $OS $VER ($DISTRO_FAMILY)
内核版本: $KERNEL_VERSION
运行环境: $ENV_TYPE
系统资源: ${TOTAL_MEM_GB}GB内存, ${CPU_CORES}核CPU
描述: $description
操作用户: $(whoami)
进程ID: $$
命令行: $0 $*
EOF

        # 保存优化参数
        if [ ${#OPTIMAL_VALUES[@]} -gt 0 ]; then
            echo -e "\n# 应用的优化参数:" >> "$version_dir/info.txt"
            for key in "${!OPTIMAL_VALUES[@]}"; do
                echo "$key = ${OPTIMAL_VALUES[$key]}" >> "$version_dir/info.txt"
            done
        fi
        
        # 设置合适的权限
        chmod -R 640 "$version_dir" 2>/dev/null || true
        
        print_msg "success" "配置版本已保存: $version"
        log "创建配置版本: $version - $description"
        
        # 清理旧版本（保留最近10个）
        cleanup_old_versions
        
        return 0
    else
        print_msg "warning" "无法创建版本目录: $version_dir"
        return 1
    fi
}

# 清理旧版本
cleanup_old_versions() {
    if [ -d "$VERSION_DIR" ]; then
        local version_count
        version_count=$(find "$VERSION_DIR" -maxdepth 1 -type d -name "v*" | wc -l)
        
        if [ "$version_count" -gt 10 ]; then
            print_msg "info" "清理旧版本配置..."
            
            # 删除最旧的版本，保留最新的10个
            find "$VERSION_DIR" -maxdepth 1 -type d -name "v*" -printf '%T@ %p\n' | \
            sort -n | head -n -10 | cut -d' ' -f2- | \
            while read -r old_version; do
                if rm -rf "$old_version" 2>/dev/null; then
                    print_msg "info" "已清理旧版本: $(basename "$old_version")"
                fi
            done
        fi
    fi
}

# 智能回滚功能
rollback_changes() {
    echo
    print_msg "warning" "🔄 正在启动智能回滚程序..."
    
    # 检查可用版本
    if [ ! -d "$VERSION_DIR" ] || [ -z "$(ls -A "$VERSION_DIR" 2>/dev/null)" ]; then
        print_msg "error" "未找到任何备份版本"
        return 1
    fi
    
    echo -e "${CYAN}📋 可用的备份版本:${RESET}"
    echo -e "${WHITE}──────────────────────────────────────────────────────────────${RESET}"
    
    local versions=()
    local count=0
    
    # 列出版本并收集信息
    for version_dir in $(find "$VERSION_DIR" -maxdepth 1 -type d -name "v*" | sort -r); do
        if [ $count -ge 5 ]; then break; fi  # 只显示最近5个版本
        
        local version_name=$(basename "$version_dir")
        local info_file="$version_dir/info.txt"
        local create_time="未知时间"
        local description="无描述"
        
        if [ -f "$info_file" ]; then
            create_time=$(grep "^创建时间:" "$info_file" | cut -d: -f2- | xargs)
            description=$(grep "^描述:" "$info_file" | cut -d: -f2- | xargs)
        fi
        
        versions+=("$version_dir")
        echo -e "${GREEN}$((count + 1)))${RESET} ${WHITE}$version_name${RESET}"
        echo -e "   ${BLUE}时间:${RESET} $create_time"
        echo -e "   ${BLUE}描述:${RESET} $description"
        echo
        
        ((count++))
    done
    
    if [ $count -eq 0 ]; then
        print_msg "error" "未找到有效的备份版本"
        return 1
    fi
    
    echo -e "${WHITE}──────────────────────────────────────────────────────────────${RESET}"
    echo -e "${GREEN}0)${RESET} ${WHITE}取消回滚${RESET}"
    echo
    
    # 用户选择版本
    while true; do
        echo -n "请选择要回滚的版本 [0-$count]: "
        read -r version_choice
        
        if ! validate_user_input "$version_choice" "$(seq 0 $count | tr '\n' ' ')"; then
            print_msg "error" "无效选择，请输入 0-$count"
            continue
        fi
        
        if [ "$version_choice" = "0" ]; then
            print_msg "info" "已取消回滚操作"
            return 0
        fi
        
        break
    done
    
    # 获取选择的版本
    local selected_version="${versions[$((version_choice - 1))]}"
    local version_name=$(basename "$selected_version")
    
    print_msg "warning" "准备回滚到版本: $version_name"
    
    # 显示回滚详情
    if [ -f "$selected_version/info.txt" ]; then
        echo -e "\n${CYAN}版本详情:${RESET}"
        grep -E "^(创建时间|描述|优化级别|工作负载)" "$selected_version/info.txt" | \
        while IFS=: read -r key value; do
            echo -e "${WHITE}$key:${RESET}$value"
        done
    fi
    
    echo
    echo -n "确认回滚到此版本? [y/N]: "
    read -r confirm_choice
    
    if [[ ! "$confirm_choice" =~ ^[Yy]$ ]]; then
        print_msg "info" "已取消回滚操作"
        return 0
    fi
    
    # 执行回滚
    print_msg "working" "正在执行回滚..."
    
    # 备份当前配置
    backup_file "/etc/sysctl.conf" "回滚前自动备份"
    
    # 恢复配置文件
    local restore_success=true
    local restored_files=0
    
    for config_file in "/etc/sysctl.conf" "/etc/security/limits.conf"; do
        local backup_file="$selected_version/$(basename "$config_file")"
        
        if [ -f "$backup_file" ]; then
            if cp "$backup_file" "$config_file" 2>/dev/null; then
                print_msg "success" "已恢复: $(basename "$config_file")"
                ((restored_files++))
                log "回滚恢复: $config_file 从版本 $version_name"
            else
                print_msg "error" "恢复失败: $(basename "$config_file")"
                restore_success=false
            fi
        fi
    done
    
    if [ "$restore_success" = true ] && [ $restored_files -gt 0 ]; then
        # 重新加载sysctl配置
        if sysctl -p >/dev/null 2>&1; then
            print_msg "success" "sysctl配置重新加载成功"
        else
            print_msg "warning" "sysctl配置重新加载失败，可能需要重启"
        fi
        
        print_msg "success" "回滚完成！🔄"
        print_msg "info" "已恢复 $restored_files 个配置文件"
        
        # 创建回滚记录
        version_control "回滚到版本 $version_name"
        
        echo
        print_msg "info" "建议重启应用程序以使配置完全生效"
        
        return 0
    else
        print_msg "error" "回滚失败"
        return 1
    fi
}

# ==================== 配置向导 ====================

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

# ==================== 性能测试和验证 ====================

# 简单的性能基准测试
run_performance_test() {
    echo
    print_msg "test" "🧪 运行性能基准测试..."
    
    local test_results_file="$BENCHMARK_DIR/benchmark_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "# 性能基准测试报告"
        echo "# 测试时间: $(date)"
        echo "# 系统信息: $OS $VER"
        echo "# 内核版本: $KERNEL_VERSION"
        echo "# 优化配置: ${OPTIMIZATION:-未应用} - ${WORKLOAD_TYPE:-未配置}"
        echo
    } > "$test_results_file"
    
    # 网络连接测试
    print_msg "working" "测试网络连接能力..."
    local current_somaxconn
    current_somaxconn=$(sysctl -n net.core.somaxconn 2>/dev/null || echo "unknown")
    echo "net.core.somaxconn = $current_somaxconn" >> "$test_results_file"
    
    # 文件句柄测试
    print_msg "working" "测试文件处理能力..."
    local current_file_max
    current_file_max=$(sysctl -n fs.file-max 2>/dev/null || echo "unknown")
    echo "fs.file-max = $current_file_max" >> "$test_results_file"
    
    # 内存信息
    print_msg "working" "检测内存配置..."
    if check_command free; then
        echo "# 内存信息" >> "$test_results_file"
        free -h >> "$test_results_file" 2>/dev/null
    fi
    
    # TCP配置
    print_msg "working" "检测TCP配置..."
    echo "# TCP配置" >> "$test_results_file"
    {
        echo "tcp_rmem: $(sysctl -n net.ipv4.tcp_rmem 2>/dev/null || echo 'unknown')"
        echo "tcp_wmem: $(sysctl -n net.ipv4.tcp_wmem 2>/dev/null || echo 'unknown')"
        echo "tcp_mem: $(sysctl -n net.ipv4.tcp_mem 2>/dev/null || echo 'unknown')"
    } >> "$test_results_file"
    
    # 网络连接统计
    if check_command ss; then
        print_msg "working" "统计网络连接..."
        echo "# 当前网络连接统计" >> "$test_results_file"
        ss -s >> "$test_results_file" 2>/dev/null || echo "ss命令不可用" >> "$test_results_file"
    fi
    
    # 简单的磁盘IO测试（小文件，避免影响系统）
    print_msg "working" "测试磁盘I/O性能..."
    if check_command dd; then
        local io_test_result
        io_test_result=$(dd if=/dev/zero of=/tmp/speedtest bs=1M count=10 oflag=direct 2>&1 | grep "copied" || echo "测试失败")
        echo "# 磁盘I/O测试结果" >> "$test_results_file"
        echo "$io_test_result" >> "$test_results_file"
        rm -f /tmp/speedtest 2>/dev/null
    fi
    
    # 显示结果摘要
    echo
    print_msg "success" "性能测试完成！"
    echo -e "${CYAN}测试结果已保存到: ${WHITE}$test_results_file${RESET}"
    
    # 显示关键指标
    echo -e "\n${CYAN}${BOLD}🎯 关键性能指标：${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${WHITE}网络连接队列: ${GREEN}$current_somaxconn${RESET}"
    echo -e "${WHITE}文件句柄限制: ${GREEN}$current_file_max${RESET}"
    echo -e "${WHITE}系统内存: ${GREEN}${TOTAL_MEM_GB}GB${RESET}"
    echo -e "${WHITE}CPU核心数: ${GREEN}$CPU_CORES${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    log "性能测试完成，结果保存到: $test_results_file"
}

# 系统健康检查
system_health_check() {
    echo
    print_msg "test" "🔍 执行系统健康检查..."
    
    local health_score=100
    local issues=0
    
    # 检查系统负载
    if check_command uptime; then
        local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',' 2>/dev/null)
        if [ -n "$load_avg" ]; then
            local load_int=${load_avg%.*}
            if validate_number "$load_int"; then
                if [ "$load_int" -gt 20 ]; then
                    print_msg "error" "系统负载过高: $load_avg"
                    health_score=$((health_score - 30))
                    ((issues++))
                elif [ "$load_int" -gt 10 ]; then
                    print_msg "warning" "系统负载较高: $load_avg"
                    health_score=$((health_score - 15))
                elif [ "$load_int" -gt 5 ]; then
                    print_msg "info" "系统负载正常偏高: $load_avg"
                    health_score=$((health_score - 5))
                else
                    print_msg "success" "系统负载正常: $load_avg"
                fi
            fi
        fi
    fi
    
    # 检查内存使用
    if check_command free; then
        local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}' 2>/dev/null)
        if validate_number "${mem_usage:-0}"; then
            if [ "$mem_usage" -gt 95 ]; then
                print_msg "error" "内存使用率危险: ${mem_usage}%"
                health_score=$((health_score - 25))
                ((issues++))
            elif [ "$mem_usage" -gt 85 ]; then
                print_msg "warning" "内存使用率较高: ${mem_usage}%"
                health_score=$((health_score - 10))
            elif [ "$mem_usage" -gt 70 ]; then
                print_msg "info" "内存使用率正常偏高: ${mem_usage}%"
                health_score=$((health_score - 5))
            else
                print_msg "success" "内存使用率正常: ${mem_usage}%"
            fi
        fi
    fi
    
    # 检查磁盘空间
    if check_command df; then
        local disk_usage=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
        if validate_number "${disk_usage:-0}"; then
            if [ "$disk_usage" -gt 95 ]; then
                print_msg "error" "磁盘空间不足: ${disk_usage}%"
                health_score=$((health_score - 25))
                ((issues++))
            elif [ "$disk_usage" -gt 85 ]; then
                print_msg "warning" "磁盘空间紧张: ${disk_usage}%"
                health_score=$((health_score - 10))
            elif [ "$disk_usage" -gt 75 ]; then
                print_msg "info" "磁盘使用率较高: ${disk_usage}%"
                health_score=$((health_score - 5))
            else
                print_msg "success" "磁盘空间充足: ${disk_usage}%"
            fi
        fi
    fi
    
    # 检查重要进程
    local critical_services=("sshd" "systemd")
    for service in "${critical_services[@]}"; do
        if pgrep "$service" >/dev/null 2>&1; then
            print_msg "success" "关键服务运行正常: $service"
        else
            print_msg "warning" "关键服务状态异常: $service"
            health_score=$((health_score - 5))
        fi
    done
    
    # 检查网络连通性
    if check_command ping; then
        if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
            print_msg "success" "网络连通性正常"
        else
            print_msg "warning" "网络连通性可能存在问题"
            health_score=$((health_score - 10))
        fi
    fi
    
    # 健康评分
    echo
    echo -e "${CYAN}${BOLD}🎯 系统健康评分${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    if [ $health_score -ge 90 ]; then
        echo -e "${GREEN}${BOLD}健康评分: $health_score/100 - 优秀 🌟${RESET}"
        print_msg "success" "系统状态非常健康"
    elif [ $health_score -ge 75 ]; then
        echo -e "${YELLOW}${BOLD}健康评分: $health_score/100 - 良好 👍${RESET}"
        print_msg "info" "系统状态良好"
    elif [ $health_score -ge 60 ]; then
        echo -e "${YELLOW}${BOLD}健康评分: $health_score/100 - 一般 ⚠️${RESET}"
        print_msg "warning" "系统状态一般，建议关注"
    else
        echo -e "${RED}${BOLD}健康评分: $health_score/100 - 需要关注 🚨${RESET}"
        print_msg "error" "系统状态需要immediate attention"
    fi
    
    echo -e "${WHITE}发现问题: $issues 个${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    log "系统健康检查完成: 评分=$health_score, 问题数=$issues"
    return $issues
}

# ==================== 主菜单系统 ====================

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${PURPLE}${BOLD}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                    Linux 内核优化脚本                        ║
║                   Security Enhanced v1.0                    ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${RESET}"
    
    echo -e "${CYAN}${BOLD}🖥️ 系统信息:${RESET} ${WHITE}$OS $VER | 内存: ${TOTAL_MEM_GB}GB | CPU: ${CPU_CORES}核 | 环境: $ENV_TYPE${RESET}"
    echo
    
    echo -e "${WHITE}${BOLD}主菜单选项:${RESET}"
    echo -e "${GREEN}1)${RESET} ${WHITE}🧙‍♂️ 智能配置向导${RESET}     - 引导式优化配置"
    echo -e "${GREEN}2)${RESET} ${WHITE}⚡ 快速优化${RESET}         - 使用推荐设置快速优化"
    echo -e "${GREEN}3)${RESET} ${WHITE}👁️ 预览优化效果${RESET}      - 查看优化参数不实际应用"
    echo -e "${GREEN}4)${RESET} ${WHITE}🔄 回滚配置${RESET}         - 恢复到之前的配置"
    echo -e "${GREEN}5)${RESET} ${WHITE}🧪 性能测试${RESET}         - 运行系统性能基准测试"
    echo -e "${GREEN}6)${RESET} ${WHITE}🔍 系统健康检查${RESET}      - 检查系统状态和健康度"
    echo -e "${GREEN}7)${RESET} ${WHITE}📊 当前配置查看${RESET}      - 显示当前内核参数"
    echo -e "${GREEN}8)${RESET} ${WHITE}💾 配置管理${RESET}         - 备份、导入、导出配置"
    echo -e "${GREEN}9)${RESET} ${WHITE}❓ 帮助信息${RESET}         - 显示详细帮助"
    echo -e "${GREEN}0)${RESET} ${WHITE}🚪 退出程序${RESET}         - 安全退出"
    echo
}

# 主菜单循环
main_menu() {
    while true; do
        show_main_menu
        
        echo -n "请选择选项 [0-9]: "
        read -r choice
        
        # 验证输入
        if choice=$(validate_user_input "$choice" "0 1 2 3 4 5 6 7 8 9"); then
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
                4)
                    rollback_changes
                    echo
                    echo -n "按Enter键继续..."
                    read -r
                    ;;
                5)
                    run_performance_test
                    echo
                    echo -n "按Enter键继续..."
                    read -r
                    ;;
                6)
                    system_health_check
                    echo
                    echo -n "按Enter键继续..."
                    read -r
                    ;;
                7)
                    show_current_config
                    echo
                    echo -n "按Enter键继续..."
                    read -r
                    ;;
                8)
                    config_management_menu
                    ;;
                9)
                    show_help
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
            print_msg "error" "无效的选择: [$choice]，请选择0-9"
            sleep 1
        fi
    done
}

# 显示当前配置
show_current_config() {
    echo
    print_msg "info" "📊 当前系统内核配置"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    # 获取关键参数
    local params=(
        "net.core.somaxconn:网络连接队列"
        "fs.file-max:文件句柄限制"
        "net.core.rmem_max:网络接收缓冲区"
        "net.core.wmem_max:网络发送缓冲区"
        "net.core.netdev_max_backlog:网络设备队列"
        "net.ipv4.tcp_max_syn_backlog:TCP SYN队列"
        "fs.inotify.max_user_watches:文件监控限制"
        "vm.swappiness:交换倾向"
        "net.ipv4.tcp_syncookies:SYN Cookies"
        "net.ipv4.tcp_tw_reuse:TIME_WAIT重用"
    )
    
    printf "${WHITE}%-35s %-15s %-s${RESET}\n" "参数名称" "当前值" "描述"
    echo -e "${WHITE}────────────────────────────────────────────────────────────────────────${RESET}"
    
    for param_desc in "${params[@]}"; do
        local param="${param_desc%:*}"
        local desc="${param_desc#*:}"
        local value=$(sysctl -n "$param" 2>/dev/null || echo "未设置")
        
        printf "${WHITE}%-35s ${GREEN}%-15s${RESET} %-s\n" "$param" "$value" "$desc"
    done
    
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# 配置管理菜单
config_management_menu() {
    while true; do
        echo
        echo -e "${CYAN}${BOLD}💾 配置管理${RESET}"
        echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${GREEN}1)${RESET} ${WHITE}手动备份当前配置${RESET}"
        echo -e "${GREEN}2)${RESET} ${WHITE}查看备份历史${RESET}"
        echo -e "${GREEN}3)${RESET} ${WHITE}导出配置到文件${RESET}"
        echo -e "${GREEN}4)${RESET} ${WHITE}清理旧备份${RESET}"
        echo -e "${GREEN}0)${RESET} ${WHITE}返回主菜单${RESET}"
        echo
        
        echo -n "请选择选项 [0-4]: "
        read -r config_choice
        
        if config_choice=$(validate_user_input "$config_choice" "0 1 2 3 4"); then
            case "$config_choice" in
                1)
                    backup_file "/etc/sysctl.conf" "手动备份"
                    ;;
                2)
                    show_backup_history
                    ;;
                3)
                    export_config
                    ;;
                4)
                    cleanup_old_versions
                    print_msg "success" "旧备份清理完成"
                    ;;
                0)
                    break
                    ;;
            esac
        else
            print_msg "error" "无效选择，请输入0-4"
        fi
        
        echo
        echo -n "按Enter键继续..."
        read -r
    done
}

# 显示备份历史
show_backup_history() {
    echo
    print_msg "info" "📚 配置备份历史"
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        print_msg "warning" "未找到任何备份文件"
        return
    fi
    
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    printf "${WHITE}%-25s %-20s %-15s %-s${RESET}\n" "备份文件" "创建时间" "大小" "描述"
    echo -e "${WHITE}────────────────────────────────────────────────────────────────────────${RESET}"
    
    find "$BACKUP_DIR" -name "*.conf.*" -type f | sort -r | head -10 | while read -r backup_file; do
        local filename=$(basename "$backup_file")
        local filesize=$(stat -c%s "$backup_file" 2>/dev/null || echo "0")
        local filesize_kb=$((filesize / 1024))
        local modify_time=$(stat -c%y "$backup_file" 2>/dev/null | cut -d. -f1 || echo "未知")
        local info_file="${backup_file}.info"
        local description="手动备份"
        
        if [ -f "$info_file" ]; then
            description=$(grep "^描述:" "$info_file" 2>/dev/null | cut -d: -f2- | xargs || echo "手动备份")
        fi
        
        printf "${WHITE}%-25s %-20s ${GREEN}%-15s${RESET} %-s\n" \
               "${filename:0:24}" "${modify_time:5:14}" "${filesize_kb}KB" "${description:0:20}"
    done
    
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# 导出配置
export_config() {
    local export_file="$EXPORT_DIR/kernel_config_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    print_msg "working" "正在导出配置..."
    
    # 创建临时目录
    local temp_export
    temp_export=$(mktemp -d "$TEMP_DIR/export.XXXXXX") || {
        print_msg "error" "无法创建临时目录"
        return 1
    }
    
    # 复制配置文件
    local export_files=(
        "/etc/sysctl.conf:system_sysctl.conf"
        "/etc/security/limits.conf:security_limits.conf"
        "/proc/version:kernel_version.txt"
    )
    
    for file_mapping in "${export_files[@]}"; do
        local src_file="${file_mapping%:*}"
        local dst_file="${file_mapping#*:}"
        
        if [ -f "$src_file" ]; then
            cp "$src_file" "$temp_export/$dst_file" 2>/dev/null || true
        fi
    done
    
    # 创建配置说明
    cat > "$temp_export/README.txt" <<EOF
Linux内核优化配置导出
=====================

导出时间: $(date)
系统信息: $OS $VER
内核版本: $KERNEL_VERSION
脚本版本: $SCRIPT_VERSION
运行环境: $ENV_TYPE

文件说明:
- system_sysctl.conf: 系统内核参数配置
- security_limits.conf: 安全限制配置
- kernel_version.txt: 内核版本信息
- current_values.txt: 导出时的参数值
- system_info.txt: 详细系统信息

使用方法:
1. 解压配置文件包
2. 根据需要复制配置文件到目标系统
3. 使用 sysctl -p 重新加载配置
4. 重启相关服务使配置生效

注意事项:
- 请确保目标系统与源系统兼容
- 建议在应用前先备份目标系统配置
- 某些参数可能需要根据硬件调整
EOF
    
    # 导出当前参数值
    sysctl -a > "$temp_export/current_values.txt" 2>/dev/null || echo "无法获取当前参数值" > "$temp_export/current_values.txt"
    
    # 导出系统信息
    {
        echo "操作系统: $OS $VER"
        echo "发行版系列: $DISTRO_FAMILY"
        echo "内核版本: $KERNEL_VERSION"
        echo "系统架构: $(uname -m)"
        echo "CPU核心数: $CPU_CORES"
        echo "内存大小: ${TOTAL_MEM_GB}GB"
        echo "运行环境: $ENV_TYPE"
        echo "系统启动时间: $(uptime -s 2>/dev/null || echo '未知')"
        echo "负载平均: $(uptime | awk -F'load average:' '{print $2}' || echo '未知')"
    } > "$temp_export/system_info.txt"
    
    # 创建压缩包
    if tar -czf "$export_file" -C "$temp_export" . 2>/dev/null; then
        print_msg "success" "配置导出成功！"
        echo -e "${WHITE}导出文件: ${GREEN}$export_file${RESET}"
        echo -e "${WHITE}文件大小: ${GREEN}$(stat -c%s "$export_file" 2>/dev/null | numfmt --to=iec || echo '未知')${RESET}"
    else
        print_msg "error" "配置导出失败"
    fi
    
    # 清理临时文件
    rm -rf "$temp_export"
}

# 帮助信息
show_help() {
    echo
    echo -e "${PURPLE}${BOLD}❓ Linux内核优化脚本帮助${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    echo -e "\n${CYAN}${BOLD}📖 脚本功能:${RESET}"
    echo -e "${WHITE}• 智能检测系统配置并推荐最优参数${RESET}"
    echo -e "${WHITE}• 支持多种工作负载类型的专门优化${RESET}"
    echo -e "${WHITE}• 提供三种优化级别：保守、平衡、激进${RESET}"
    echo -e "${WHITE}• 完整的配置备份和一键回滚功能${RESET}"
    echo -e "${WHITE}• 支持预览模式，先查看后应用${RESET}"
    echo -e "${WHITE}• 提供性能测试和系统健康检查${RESET}"
    
    echo -e "\n${CYAN}${BOLD}🎯 工作负载类型:${RESET}"
    echo -e "${WHITE}• Web服务器: 优化网络连接和文件处理性能${RESET}"
    echo -e "${WHITE}• 数据库服务器: 优化内存和I/O性能${RESET}"
    echo -e "${WHITE}• 缓存服务器: 优化内存使用和网络性能${RESET}"
    echo -e "${WHITE}• 容器主机: 优化容器调度和资源管理${RESET}"
    echo -e "${WHITE}• 通用服务器: 平衡各方面性能表现${RESET}"
    
    echo -e "\n${CYAN}${BOLD}⚡ 优化级别:${RESET}"
    echo -e "${WHITE}• 保守模式: 最小化风险，适合关键生产环境${RESET}"
    echo -e "${WHITE}• 平衡模式: 性能与稳定性兼顾，推荐选择${RESET}"
    echo -e "${WHITE}• 激进模式: 最大化性能，适合高性能计算${RESET}"
    
    echo -e "\n${CYAN}${BOLD}🔧 命令行选项:${RESET}"
    echo -e "${WHITE}• --help, -h: 显示帮助信息${RESET}"
    echo -e "${WHITE}• --version: 显示版本信息${RESET}"
    echo -e "${WHITE}• --quick: 快速优化（平衡+通用）${RESET}"
    echo -e "${WHITE}• --preview: 预览模式${RESET}"
    echo -e "${WHITE}• --check: 系统健康检查${RESET}"
    echo -e "${WHITE}• --rollback: 回滚到最近备份${RESET}"
    
    echo -e "\n${CYAN}${BOLD}⚠️ 注意事项:${RESET}"
    echo -e "${WHITE}• 建议在测试环境中先验证优化效果${RESET}"
    echo -e "${WHITE}• 所有更改前会自动创建配置备份${RESET}"
    echo -e "${WHITE}• 容器环境中某些参数可能无法修改${RESET}"
    echo -e "${WHITE}• 优化后请监控系统性能和稳定性${RESET}"
    
    echo -e "\n${CYAN}${BOLD}📁 相关文件:${RESET}"
    echo -e "${WHITE}• 日志文件: $LOG_FILE${RESET}"
    echo -e "${WHITE}• 备份目录: $BACKUP_DIR${RESET}"
    echo -e "${WHITE}• 版本控制: $VERSION_DIR${RESET}"
    echo -e "${WHITE}• 测试结果: $BENCHMARK_DIR${RESET}"
    
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# ==================== 命令行参数处理 ====================

# 显示版本信息
show_version() {
    echo -e "${PURPLE}${BOLD}Linux内核优化脚本${RESET} ${GREEN}v${SCRIPT_VERSION}${RESET}"
    echo -e "${WHITE}Security Enhanced Edition${RESET}"
    echo
    echo -e "${CYAN}特性:${RESET}"
    echo -e "${WHITE}• 🔒 安全增强 - 移除代码注入风险${RESET}"
    echo -e "${WHITE}• 🛡️ 输入验证 - 严格的参数验证${RESET}"
    echo -e "${WHITE}• 📋 预览模式 - 先预览后应用${RESET}"
    echo -e "${WHITE}• 🔄 智能回滚 - 版本控制和自动恢复${RESET}"
    echo -e "${WHITE}• 🧪 性能测试 - 内置基准测试${RESET}"
    echo -e "${WHITE}• 🎯 多负载支持 - 5种工作负载优化${RESET}"
    echo
    echo -e "${WHITE}作者: Claude (Anthropic) | 许可: MIT License${RESET}"
}

# 命令行参数处理
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
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
            --check)
                system_health_check
                exit 0
                ;;
            --rollback)
                rollback_changes
                exit 0
                ;;
            --test)
                run_performance_test
                exit 0
                ;;
            --aggressive)
                OPTIMIZATION="aggressive"
                ;;
            --conservative)
                OPTIMIZATION="conservative"
                ;;
            --web)
                WORKLOAD_TYPE="web"
                ;;
            --database)
                WORKLOAD_TYPE="database"
                ;;
            --cache)
                WORKLOAD_TYPE="cache"
                ;;
            --container)
                WORKLOAD_TYPE="container"
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
    ║  智能 • 安全 • 高效 • 可靠                                      ║
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
Smart, efficient model for everyday use Learn more

Artifacts
