#!/bin/bash
# Linux 内核优化脚本 v2.0
# By: BuBuXSY
# Version: 2.0-
# 2025-07-25
# License: MIT
# 特性: 智能系统检测 + 分层菜单设计 + IPv6可选禁用 + 错误处理优化

set -euo pipefail

# 颜色和样式定义
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
readonly SYSCTL_CONF="/etc/sysctl.d/99-kernel-optimization.conf"
readonly SCRIPT_VERSION="2.0-complete-full"

# 全局变量
OS=""
VER=""
DISTRO_FAMILY=""
TOTAL_MEM=""
TOTAL_MEM_GB=""
CPU_CORES=""
KERNEL_VERSION=""
SYSTEM_PROFILE=""
KERNEL_FEATURES=""
ENV_TYPE=""
DISABLE_IPV6=false
AUTO_ROLLBACK_ENABLED=false
DRY_RUN=false
OPTIMIZATION_LEVEL=""
WORKLOAD_TYPE=""

# 优化参数存储
declare -A OPTIMAL_VALUES=()
declare -A ORIGINAL_VALUES=()
declare -A PARAMETER_CHANGES=()

# ==================== 基础函数 ====================

# 创建必要的目录
create_directories() {
    mkdir -p "$BACKUP_DIR" "/tmp/kernel_optimization" 2>/dev/null || true
    chmod 750 "$BACKUP_DIR" 2>/dev/null || true
}

# 日志记录函数
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE" 2>/dev/null || echo "[$timestamp] $message"
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
        "preview") echo -e "${YELLOW}👁️  $msg${RESET}" ;;
    esac
}

# 检查命令是否存在
check_command() {
    command -v "$1" >/dev/null 2>&1
}

# 数值验证
validate_number() {
    local value="$1"
    local min="${2:-0}"
    local max="${3:-9223372036854775807}"
    
    if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge "$min" ] && [ "$value" -le "$max" ]; then
        return 0
    else
        return 1
    fi
}

# 检查root权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_msg "error" "此脚本必须以root权限运行！"
        echo -e "${YELLOW}请尝试: ${WHITE}sudo $0${RESET}"
        exit 1
    fi
    print_msg "success" "已获取root权限"
}

# ==================== 系统检测函数 ====================

# 检测Linux发行版
detect_distro() {
    print_msg "working" "正在检测Linux发行版..."
    
    if [ -f /etc/os-release ]; then
        OS=$(grep '^NAME=' /etc/os-release | cut -d'=' -f2- | tr -d '"' | head -1)
        VER=$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2- | tr -d '"' | head -1)
        local system_id=$(grep '^ID=' /etc/os-release | cut -d'=' -f2- | tr -d '"' | head -1)
        
        OS=${OS:-"Unknown"}
        VER=${VER:-"0"}
        system_id=${system_id:-"unknown"}
        
        case "$system_id" in
            ubuntu|debian|linuxmint|pop|elementary)
                DISTRO_FAMILY="debian"
                ;;
            centos|rhel|fedora|rocky|almalinux|ol)
                DISTRO_FAMILY="redhat"
                ;;
            arch|manjaro)
                DISTRO_FAMILY="arch"
                ;;
            alpine)
                DISTRO_FAMILY="alpine"
                ;;
            *)
                DISTRO_FAMILY="unknown"
                ;;
        esac
        
        print_msg "success" "检测到系统: $OS $VER (${DISTRO_FAMILY}系)"
        log "操作系统: $OS $VER, 发行版系列: $DISTRO_FAMILY"
    else
        print_msg "error" "无法检测操作系统版本"
        exit 1
    fi
}

# 检测系统资源
detect_resources() {
    print_msg "working" "正在分析系统资源..."
    
    # 内存检测
    if [ -f /proc/meminfo ]; then
        TOTAL_MEM=$(awk '/^MemTotal:/{print $2*1024}' /proc/meminfo)
    elif check_command free; then
        TOTAL_MEM=$(free -b | awk '/^Mem:/{print $2}' | head -1)
    else
        TOTAL_MEM=1073741824  # 默认1GB
    fi
    
    # 修复内存显示计算
    TOTAL_MEM_GB=$(( (TOTAL_MEM + 536870912) / 1073741824 ))
    
    # CPU核心检测
    if check_command nproc; then
        CPU_CORES=$(nproc)
    elif [ -f /proc/cpuinfo ]; then
        CPU_CORES=$(grep -c '^processor' /proc/cpuinfo)
    else
        CPU_CORES=1
    fi
    
    KERNEL_VERSION=$(uname -r)
    
    print_msg "success" "系统资源检测完成"
    log "系统资源 - 内存: ${TOTAL_MEM_GB}GB, CPU核心: $CPU_CORES, 内核: $KERNEL_VERSION"
}

# 分析系统配置档案
analyze_system_profile() {
    local os_id=$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"' | head -1)
    local version_id=$(grep '^VERSION_ID=' /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"' | head -1)
    
    case "$os_id" in
        "ubuntu")
            if [[ "$version_id" =~ ^(24|23) ]]; then
                SYSTEM_PROFILE="ubuntu_modern"
            elif [[ "$version_id" =~ ^(22|20) ]]; then
                SYSTEM_PROFILE="ubuntu_lts"
            else
                SYSTEM_PROFILE="ubuntu_legacy"
            fi
            ;;
        "debian")
            if [[ "$version_id" =~ ^(12|11) ]]; then
                SYSTEM_PROFILE="debian_modern"
            else
                SYSTEM_PROFILE="debian_stable"
            fi
            ;;
        "centos"|"rhel"|"rocky"|"almalinux")
            SYSTEM_PROFILE="rhel_modern"
            ;;
        "fedora")
            SYSTEM_PROFILE="fedora_modern"
            ;;
        "arch"|"manjaro")
            SYSTEM_PROFILE="arch_rolling"
            ;;
        "alpine")
            SYSTEM_PROFILE="alpine_minimal"
            ;;
        *)
            SYSTEM_PROFILE="generic_modern"
            ;;
    esac
}

# 检测内核特性
detect_kernel_features() {
    local features=()
    
    [ -d /sys/fs/cgroup ] && features+=("cgroup")
    [ -f /proc/sys/net/netfilter/nf_conntrack_max ] && features+=("netfilter")
    [ -f /proc/net/nf_conntrack ] && features+=("conntrack")
    [ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ] && features+=("ipv6_disable")
    [ -f /proc/sys/kernel/pid_max ] && features+=("pid_max")
    
    if grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        features+=("bbr")
    fi
    
    KERNEL_FEATURES="${features[*]}"
}

# 检测容器环境
detect_container_environment() {
    print_msg "working" "检测运行环境..."
    
    if [ -f /.dockerenv ]; then
        ENV_TYPE="docker"
        print_msg "warning" "检测到Docker容器环境"
    elif [ -n "${KUBERNETES_SERVICE_HOST:-}" ]; then
        ENV_TYPE="kubernetes"
        print_msg "warning" "检测到Kubernetes环境"
    elif [ -f /proc/1/cgroup ] && grep -qE "(lxc|docker|kubepods)" /proc/1/cgroup 2>/dev/null; then
        ENV_TYPE="container"
        print_msg "warning" "检测到容器环境"
    elif check_command systemd-detect-virt && [ "$(systemd-detect-virt)" != "none" ]; then
        ENV_TYPE="virtual"
        print_msg "info" "检测到虚拟化环境"
    else
        ENV_TYPE="physical"
        print_msg "success" "检测到物理机环境"
    fi
}

# 深度系统检测
perform_deep_system_detection() {
    print_msg "working" "执行深度系统检测和分析..."
    
    detect_distro
    detect_resources
    analyze_system_profile
    detect_kernel_features
    detect_container_environment
    
    show_system_analysis_results
    print_msg "success" "深度系统检测完成"
}

# 显示系统分析结果
show_system_analysis_results() {
    echo
    echo -e "${CYAN}${BOLD}🔍 深度系统分析结果：${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${WHITE}• 操作系统: ${GREEN}$OS $VER${RESET}"
    echo -e "${WHITE}• 发行版系列: ${GREEN}$DISTRO_FAMILY${RESET}"
    echo -e "${WHITE}• 系统架构: ${GREEN}$(uname -m)${RESET}"
    echo -e "${WHITE}• 内核版本: ${GREEN}$KERNEL_VERSION${RESET}"
    echo -e "${WHITE}• 系统配置档案: ${GREEN}$SYSTEM_PROFILE${RESET}"
    echo -e "${WHITE}• 内核特性: ${GREEN}${KERNEL_FEATURES:-无检测到}${RESET}"
    echo -e "${WHITE}• 运行环境: ${GREEN}$ENV_TYPE${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
    echo -e "${WHITE}┌─────────────────────────────────────────┐${RESET}"
    echo -e "${WHITE}│            ${BOLD}系统资源${RESET}${WHITE}                     │${RESET}"
    echo -e "${WHITE}├─────────────────────────────────────────┤${RESET}"
    echo -e "${WHITE}│ 💾 物理内存: ${GREEN}${TOTAL_MEM_GB} GB${WHITE}                   │${RESET}"
    echo -e "${WHITE}│ 🖥️  CPU核心数: ${GREEN}${CPU_CORES}${WHITE}                        │${RESET}"
    echo -e "${WHITE}│ 🏗️  架构: ${GREEN}$(uname -m)${WHITE}                    │${RESET}"
    echo -e "${WHITE}│ 🐧 内核版本: ${GREEN}${KERNEL_VERSION}${WHITE}           │${RESET}"
    echo -e "${WHITE}└─────────────────────────────────────────┘${RESET}"
    echo
}

# ==================== 参数计算函数 ====================

# 计算最优参数值
calculate_optimal_values() {
    local workload="$1"
    local optimization="$2"
    
    print_msg "working" "基于系统资源计算最优参数..."
    
    # 基础参数计算
    local base_somaxconn=$((CPU_CORES * 1024))
    local base_file_max=$((CPU_CORES * 65536))
    local base_rmem_max=$((TOTAL_MEM / 128))
    local base_wmem_max=$((TOTAL_MEM / 128))
    
    # 根据优化级别调整
    local multiplier=1
    case "$optimization" in
        "conservative") multiplier=1 ;;
        "balanced") multiplier=2 ;;
        "aggressive") multiplier=4 ;;
    esac
    
    # 根据工作负载类型调整
    case "$workload" in
        "web")
            OPTIMAL_VALUES["net.core.somaxconn"]=$((base_somaxconn * multiplier * 2))
            OPTIMAL_VALUES["fs.file-max"]=$((base_file_max * multiplier * 2))
            ;;
        "database")
            OPTIMAL_VALUES["net.core.rmem_max"]=$((base_rmem_max * multiplier * 2))
            OPTIMAL_VALUES["net.core.wmem_max"]=$((base_wmem_max * multiplier * 2))
            ;;
        "proxy")
            OPTIMAL_VALUES["net.core.somaxconn"]=$((base_somaxconn * multiplier * 4))
            OPTIMAL_VALUES["fs.file-max"]=$((base_file_max * multiplier * 8))
            OPTIMAL_VALUES["net.core.rmem_max"]=$((base_rmem_max * multiplier * 4))
            OPTIMAL_VALUES["net.core.wmem_max"]=$((base_wmem_max * multiplier * 4))
            ;;
        "container")
            OPTIMAL_VALUES["fs.file-max"]=$((base_file_max * multiplier * 4))
            OPTIMAL_VALUES["kernel.pid_max"]=$((32768 * multiplier))
            ;;
        *)
            # general
            OPTIMAL_VALUES["net.core.somaxconn"]=$((base_somaxconn * multiplier))
            OPTIMAL_VALUES["fs.file-max"]=$((base_file_max * multiplier))
            ;;
    esac
    
    # 设置通用优化参数
    set_common_parameters "$optimization"
    
    # 边界检查
    apply_parameter_limits
    
    print_msg "success" "参数计算完成"
}

# 设置通用参数
set_common_parameters() {
    local level="$1"
    
    # 网络参数
    OPTIMAL_VALUES["net.core.netdev_max_backlog"]=5000
    OPTIMAL_VALUES["net.ipv4.tcp_max_syn_backlog"]=8192
    OPTIMAL_VALUES["net.ipv4.tcp_syncookies"]=1
    OPTIMAL_VALUES["net.ipv4.tcp_tw_reuse"]=1
    OPTIMAL_VALUES["net.ipv4.tcp_fin_timeout"]=30
    OPTIMAL_VALUES["net.ipv4.tcp_keepalive_time"]=600
    OPTIMAL_VALUES["net.ipv4.tcp_keepalive_probes"]=3
    OPTIMAL_VALUES["net.ipv4.tcp_keepalive_intvl"]=15
    OPTIMAL_VALUES["net.ipv4.tcp_max_tw_buckets"]=400000
    OPTIMAL_VALUES["net.ipv4.ip_local_port_range"]="1024 65535"
    
    # 内存管理参数
    OPTIMAL_VALUES["vm.swappiness"]=10
    OPTIMAL_VALUES["vm.dirty_ratio"]=15
    OPTIMAL_VALUES["vm.dirty_background_ratio"]=5
    OPTIMAL_VALUES["vm.vfs_cache_pressure"]=50
    
    # 内核参数
    OPTIMAL_VALUES["kernel.shmmax"]=$((TOTAL_MEM / 2))
    OPTIMAL_VALUES["kernel.shmall"]=$((TOTAL_MEM / 4096))
    
    # 根据级别调整
    case "$level" in
        "aggressive")
            OPTIMAL_VALUES["net.core.rmem_default"]=262144
            OPTIMAL_VALUES["net.core.wmem_default"]=262144
            OPTIMAL_VALUES["net.core.rmem_max"]=16777216
            OPTIMAL_VALUES["net.core.wmem_max"]=16777216
            OPTIMAL_VALUES["net.ipv4.tcp_rmem"]="4096 87380 16777216"
            OPTIMAL_VALUES["net.ipv4.tcp_wmem"]="4096 65536 16777216"
            OPTIMAL_VALUES["net.ipv4.tcp_congestion_control"]="bbr"
            ;;
        "balanced")
            OPTIMAL_VALUES["net.core.rmem_default"]=131072
            OPTIMAL_VALUES["net.core.wmem_default"]=131072
            OPTIMAL_VALUES["net.core.rmem_max"]=8388608
            OPTIMAL_VALUES["net.core.wmem_max"]=8388608
            OPTIMAL_VALUES["net.ipv4.tcp_rmem"]="4096 65536 8388608"
            OPTIMAL_VALUES["net.ipv4.tcp_wmem"]="4096 32768 8388608"
            ;;
        *)
            # conservative
            OPTIMAL_VALUES["net.core.rmem_default"]=65536
            OPTIMAL_VALUES["net.core.wmem_default"]=65536
            OPTIMAL_VALUES["net.core.rmem_max"]=4194304
            OPTIMAL_VALUES["net.core.wmem_max"]=4194304
            OPTIMAL_VALUES["net.ipv4.tcp_rmem"]="4096 65536 4194304"
            OPTIMAL_VALUES["net.ipv4.tcp_wmem"]="4096 32768 4194304"
            ;;
    esac
    
    # IPv6禁用选项
    if [ "$DISABLE_IPV6" = true ]; then
        OPTIMAL_VALUES["net.ipv6.conf.all.disable_ipv6"]=1
        OPTIMAL_VALUES["net.ipv6.conf.default.disable_ipv6"]=1
        OPTIMAL_VALUES["net.ipv6.conf.lo.disable_ipv6"]=1
    fi
}

# 应用参数限制
apply_parameter_limits() {
    # 确保参数在合理范围内
    local max_somaxconn=65535
    local max_file_max=33554432
    
    if [ "${OPTIMAL_VALUES[net.core.somaxconn]:-0}" -gt "$max_somaxconn" ]; then
        OPTIMAL_VALUES["net.core.somaxconn"]=$max_somaxconn
    fi
    
    if [ "${OPTIMAL_VALUES[fs.file-max]:-0}" -gt "$max_file_max" ]; then
        OPTIMAL_VALUES["fs.file-max"]=$max_file_max
    fi
    
    # 确保最小值
    if [ "${OPTIMAL_VALUES[net.core.somaxconn]:-0}" -lt 1024 ]; then
        OPTIMAL_VALUES["net.core.somaxconn"]=1024
    fi
    
    if [ "${OPTIMAL_VALUES[fs.file-max]:-0}" -lt 65536 ]; then
        OPTIMAL_VALUES["fs.file-max"]=65536
    fi
}

# ==================== 菜单系统 ====================

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                    🚀 Linux内核优化脚本 v2.0 🚀                              ║"
    echo "║                         智能系统优化解决方案                                 ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo
    echo -e "${WHITE}选择优化模式：${RESET}"
    echo
    echo -e "${GREEN}🚀 1) 一键优化模式${RESET}     - 预设最佳方案，新手友好"
    echo -e "${BLUE}🧙‍♂️ 2) 自定义配置模式${RESET}   - 完全自定义，高级用户"
    echo -e "${PURPLE}📊 3) 系统信息查看${RESET}     - 查看详细系统信息"
    echo -e "${CYAN}📋 4) 查看优化对比${RESET}     - 查看当前优化效果对比"
    echo -e "${YELLOW}🔄 5) 恢复默认配置${RESET}     - 回滚到优化前状态"
    echo -e "${RED}❌ 0) 退出${RESET}"
    echo
}

# 一键优化菜单
show_quick_optimization_menu() {
    clear
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                            🚀 一键优化模式 🚀                                ║"
    echo "║                          预设最佳实践，即选即用                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo
    echo -e "${WHITE}选择服务器类型：${RESET}"
    echo
    echo -e "${GREEN}🌐 1) Web服务器${RESET}        - Nginx/Apache，优化并发连接"
    echo -e "${BLUE}🗄️ 2) 数据库服务器${RESET}      - MySQL/PostgreSQL，优化I/O性能"
    echo -e "${PURPLE}🔄 3) VPS代理服务器${RESET}     - SS/V2Ray/Trojan，最大化转发性能"
    echo -e "${CYAN}🐳 4) 容器主机${RESET}         - Docker/K8s，优化容器调度"
    echo -e "${YELLOW}🏢 5) 通用服务器${RESET}       - 混合应用，平衡优化"
    echo -e "${WHITE}🔙 0) 返回主菜单${RESET}"
    echo
}

# 自定义配置菜单
show_custom_configuration_menu() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                      🧙‍♂️ 自定义配置模式 🧙‍♂️                                   ║"
    echo "║                     完全自定义，精细化控制                                      ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo
    echo -e "${WHITE}步骤1: 选择工作负载类型${RESET}"
    echo
    echo -e "${GREEN}🌐 1) Web服务器${RESET}        - HTTP/HTTPS服务优化"
    echo -e "${BLUE}🗄️ 2) 数据库服务器${RESET}      - 数据库I/O优化"
    echo -e "${PURPLE}📦 3) 缓存服务器${RESET}       - Redis/Memcached优化"
    echo -e "${CYAN}🐳 4) 容器主机${RESET}         - 容器运行时优化"
    echo -e "${YELLOW}🔄 5) 代理服务器${RESET}       - 网络转发优化"
    echo -e "${WHITE}⚙️ 6) 通用服务器${RESET}       - 综合性能优化"
    echo -e "${WHITE}🔙 0) 返回主菜单${RESET}"
    echo
}

# 优化级别选择菜单
show_optimization_level_menu() {
    echo
    echo -e "${WHITE}步骤2: 选择优化级别${RESET}"
    echo
    echo -e "${GREEN}🛡️ 1) 保守优化${RESET}  - 安全稳定，适合生产环境"
    echo -e "${YELLOW}⚖️ 2) 平衡优化${RESET}  - 性能与稳定性兼顾"
    echo -e "${RED}🚀 3) 激进优化${RESET}  - 最大性能，适合高负载环境"
    echo
}

# 高级选项菜单
show_advanced_options_menu() {
    echo
    echo -e "${WHITE}步骤3: 高级选项${RESET}"
    echo
    print_msg "question" "是否禁用IPv6？(代理服务器建议禁用) [y/N]"
    read -r ipv6_choice
    case "$ipv6_choice" in
        [Yy]|[Yy][Ee][Ss]) DISABLE_IPV6=true ;;
        *) DISABLE_IPV6=false ;;
    esac
    
    print_msg "question" "是否启用自动回滚？(可在24小时内自动恢复) [Y/n]"
    read -r rollback_choice
    case "$rollback_choice" in
        [Nn]|[Nn][Oo]) AUTO_ROLLBACK_ENABLED=false ;;
        *) AUTO_ROLLBACK_ENABLED=true ;;
    esac
    
    print_msg "question" "是否启用预览模式？(只显示配置不实际应用) [y/N]"
    read -r preview_choice
    case "$preview_choice" in
        [Yy]|[Yy][Ee][Ss]) DRY_RUN=true ;;
        *) DRY_RUN=false ;;
    esac
}

# ==================== 参数对比功能 ====================

# 读取当前系统参数值
read_current_system_values() {
    print_msg "working" "读取当前系统参数值进行对比..."
    
    # 清空原始值数组
    ORIGINAL_VALUES=()
    
    # 读取即将要优化的参数的当前值
    for param in "${!OPTIMAL_VALUES[@]}"; do
        local current_value=""
        
        # 尝试读取当前参数值
        if current_value=$(sysctl -n "$param" 2>/dev/null); then
            ORIGINAL_VALUES["$param"]="$current_value"
        else
            # 如果参数不存在或无法读取，标记为"未设置"
            ORIGINAL_VALUES["$param"]="未设置"
        fi
    done
    
    print_msg "success" "已读取 ${#ORIGINAL_VALUES[@]} 个参数的当前值"
}

# 分析参数变化
analyze_parameter_changes() {
    print_msg "working" "分析参数变化..."
    
    local new_params=0
    local modified_params=0  
    local unchanged_params=0
    
    PARAMETER_CHANGES=()
    
    for param in "${!OPTIMAL_VALUES[@]}"; do
        local original="${ORIGINAL_VALUES[$param]:-未设置}"
        local optimized="${OPTIMAL_VALUES[$param]}"
        
        if [ "$original" = "未设置" ]; then
            PARAMETER_CHANGES["$param"]="NEW"
            ((new_params++))
        elif [ "$original" != "$optimized" ]; then
            PARAMETER_CHANGES["$param"]="MODIFIED"
            ((modified_params++))
        else
            PARAMETER_CHANGES["$param"]="UNCHANGED"  
            ((unchanged_params++))
        fi
    done
    
    print_msg "info" "参数变化统计: 新增${new_params}个, 修改${modified_params}个, 不变${unchanged_params}个"
}

# 显示参数对比表
show_parameter_comparison() {
    echo
    echo -e "${CYAN}${BOLD}📊 参数优化对比表：${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    printf "%-40s %-20s %-20s %-10s\n" "参数名称" "原始值" "优化后值" "状态"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    # 按类别排序显示参数
    show_network_parameters_comparison
    show_memory_parameters_comparison  
    show_kernel_parameters_comparison
    show_ipv6_parameters_comparison
    
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# 显示网络参数对比
show_network_parameters_comparison() {
    echo -e "${BLUE}${BOLD}🌐 网络参数优化：${RESET}"
    
    local network_params=(
        "net.core.somaxconn"
        "net.core.netdev_max_backlog" 
        "net.core.rmem_max"
        "net.core.wmem_max"
        "net.core.rmem_default"
        "net.core.wmem_default"
        "net.ipv4.tcp_max_syn_backlog"
        "net.ipv4.tcp_max_tw_buckets"
        "net.ipv4.ip_local_port_range"
        "net.ipv4.tcp_rmem"
        "net.ipv4.tcp_wmem"
        "net.ipv4.tcp_congestion_control"
    )
    
    for param in "${network_params[@]}"; do
        if [[ -v OPTIMAL_VALUES["$param"] ]]; then
            show_single_parameter_comparison "$param"
        fi
    done
}

# 显示内存参数对比
show_memory_parameters_comparison() {
    echo -e "${PURPLE}${BOLD}💾 内存管理参数：${RESET}"
    
    local memory_params=(
        "vm.swappiness"
        "vm.dirty_ratio"
        "vm.dirty_background_ratio"
        "vm.vfs_cache_pressure"
        "kernel.shmmax"
        "kernel.shmall"
    )
    
    for param in "${memory_params[@]}"; do
        if [[ -v OPTIMAL_VALUES["$param"] ]]; then
            show_single_parameter_comparison "$param"
        fi
    done
}

# 显示内核参数对比
show_kernel_parameters_comparison() {
    echo -e "${GREEN}${BOLD}🔧 内核参数优化：${RESET}"
    
    local kernel_params=(
        "fs.file-max"
        "kernel.pid_max"
        "net.ipv4.tcp_syncookies"
        "net.ipv4.tcp_tw_reuse"
        "net.ipv4.tcp_fin_timeout"
        "net.ipv4.tcp_keepalive_time"
        "net.ipv4.tcp_keepalive_probes"
        "net.ipv4.tcp_keepalive_intvl"
    )
    
    for param in "${kernel_params[@]}"; do
        if [[ -v OPTIMAL_VALUES["$param"] ]]; then
            show_single_parameter_comparison "$param"
        fi
    done
}

# 显示IPv6参数对比
show_ipv6_parameters_comparison() {
    if [ "$DISABLE_IPV6" = true ]; then
        echo -e "${RED}${BOLD}🚫 IPv6禁用参数：${RESET}"
        
        local ipv6_params=(
            "net.ipv6.conf.all.disable_ipv6"
            "net.ipv6.conf.default.disable_ipv6"
            "net.ipv6.conf.lo.disable_ipv6"
        )
        
        for param in "${ipv6_params[@]}"; do
            if [[ -v OPTIMAL_VALUES["$param"] ]]; then
                show_single_parameter_comparison "$param"
            fi
        done
    fi
}

# 显示单个参数对比
show_single_parameter_comparison() {
    local param="$1"
    local original="${ORIGINAL_VALUES[$param]:-未设置}"
    local optimized="${OPTIMAL_VALUES[$param]}"
    local change_type="${PARAMETER_CHANGES[$param]:-UNKNOWN}"
    local status_color=""
    local status_text=""
    
    # 根据变化类型设置颜色和状态
    case "$change_type" in
        "NEW")
            status_color="${GREEN}"
            status_text="新增"
            ;;
        "MODIFIED")
            status_color="${YELLOW}"
            status_text="修改"
            ;;
        "UNCHANGED")
            status_color="${BLUE}"
            status_text="不变"
            ;;
        *)
            status_color="${WHITE}"
            status_text="未知"
            ;;
    esac
    
    # 格式化显示
    printf "%-40s ${WHITE}%-20s${RESET} ${GREEN}%-20s${RESET} ${status_color}%-10s${RESET}\n" \
        "$param" \
        "$(format_value_display "$original")" \
        "$(format_value_display "$optimized")" \
        "$status_text"
}

# 格式化参数值显示
format_value_display() {
    local value="$1"
    
    # 如果值太长，截断显示
    if [ ${#value} -gt 18 ]; then
        echo "${value:0:15}..."
    else
        echo "$value"
    fi
}

# 显示关键性能提升
show_performance_improvements() {
    echo
    echo -e "${CYAN}${BOLD}⚡ 关键性能提升分析：${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    # 分析连接处理能力提升
    analyze_connection_improvements
    
    # 分析内存优化效果
    analyze_memory_improvements
    
    # 分析网络性能提升
    analyze_network_improvements
    
    # 分析IPv6优化效果
    if [ "$DISABLE_IPV6" = true ]; then
        analyze_ipv6_improvements
    fi
    
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# 分析连接处理能力提升
analyze_connection_improvements() {
    if [[ -v OPTIMAL_VALUES["net.core.somaxconn"] ]]; then
        local original_somaxconn="${ORIGINAL_VALUES[net.core.somaxconn]:-128}"
        local optimized_somaxconn="${OPTIMAL_VALUES[net.core.somaxconn]}"
        
        # 计算提升倍数
        if [[ "$original_somaxconn" =~ ^[0-9]+$ ]] && [[ "$optimized_somaxconn" =~ ^[0-9]+$ ]] && [ "$original_somaxconn" -gt 0 ]; then
            local improvement=$((optimized_somaxconn / original_somaxconn))
            echo -e "${GREEN}🔗 并发连接处理能力: ${WHITE}${original_somaxconn} → ${GREEN}${optimized_somaxconn} ${YELLOW}(提升${improvement}倍)${RESET}"
        fi
    fi
    
    if [[ -v OPTIMAL_VALUES["fs.file-max"] ]]; then
        local original_filemax="${ORIGINAL_VALUES[fs.file-max]:-65536}"
        local optimized_filemax="${OPTIMAL_VALUES[fs.file-max]}"
        
        if [[ "$original_filemax" =~ ^[0-9]+$ ]] && [[ "$optimized_filemax" =~ ^[0-9]+$ ]] && [ "$original_filemax" -gt 0 ]; then
            local improvement=$((optimized_filemax / original_filemax))
            echo -e "${GREEN}📁 文件句柄处理能力: ${WHITE}${original_filemax} → ${GREEN}${optimized_filemax} ${YELLOW}(提升${improvement}倍)${RESET}"
        fi
    fi
}

# 分析内存优化效果
analyze_memory_improvements() {
    if [[ -v OPTIMAL_VALUES["vm.swappiness"] ]]; then
        local original_swappiness="${ORIGINAL_VALUES[vm.swappiness]:-60}"
        local optimized_swappiness="${OPTIMAL_VALUES[vm.swappiness]}"
        
        if [ "$original_swappiness" != "$optimized_swappiness" ]; then
            echo -e "${PURPLE}💾 内存交换策略: ${WHITE}${original_swappiness} → ${GREEN}${optimized_swappiness} ${YELLOW}(减少不必要的swap使用)${RESET}"
        fi
    fi
    
    if [[ -v OPTIMAL_VALUES["vm.dirty_ratio"] ]]; then
        local original_dirty="${ORIGINAL_VALUES[vm.dirty_ratio]:-20}"
        local optimized_dirty="${OPTIMAL_VALUES[vm.dirty_ratio]}"
        
        if [ "$original_dirty" != "$optimized_dirty" ]; then
            echo -e "${PURPLE}🖊️  磁盘写入策略: ${WHITE}${original_dirty}% → ${GREEN}${optimized_dirty}% ${YELLOW}(优化I/O性能)${RESET}"
        fi
    fi
}

# 分析网络性能提升
analyze_network_improvements() {
    if [[ -v OPTIMAL_VALUES["net.core.rmem_max"] ]]; then
        local original_rmem="${ORIGINAL_VALUES[net.core.rmem_max]:-212992}"
        local optimized_rmem="${OPTIMAL_VALUES[net.core.rmem_max]}"
        
        if [[ "$original_rmem" =~ ^[0-9]+$ ]] && [[ "$optimized_rmem" =~ ^[0-9]+$ ]] && [ "$original_rmem" -gt 0 ]; then
            local improvement=$((optimized_rmem / original_rmem))
            echo -e "${BLUE}📥 网络接收缓冲区: ${WHITE}$(format_bytes $original_rmem) → ${GREEN}$(format_bytes $optimized_rmem) ${YELLOW}(提升${improvement}倍)${RESET}"
        fi
    fi
    
    if [[ -v OPTIMAL_VALUES["net.ipv4.tcp_congestion_control"] ]]; then
        local original_cc="${ORIGINAL_VALUES[net.ipv4.tcp_congestion_control]:-cubic}"
        local optimized_cc="${OPTIMAL_VALUES[net.ipv4.tcp_congestion_control]}"
        
        if [ "$original_cc" != "$optimized_cc" ] && [ "$optimized_cc" = "bbr" ]; then
            echo -e "${BLUE}🚀 拥塞控制算法: ${WHITE}${original_cc} → ${GREEN}${optimized_cc} ${YELLOW}(大幅提升网络吞吐量)${RESET}"
        fi
    fi
}

# 分析IPv6优化效果
analyze_ipv6_improvements() {
    echo -e "${RED}🚫 IPv6完全禁用: ${WHITE}启用 → ${GREEN}禁用 ${YELLOW}(消除IPv6处理开销,适合代理服务器)${RESET}"
}

# 格式化字节数显示
format_bytes() {
    local bytes="$1"
    
    if [ "$bytes" -ge 1073741824 ]; then
        echo "$((bytes / 1073741824))GB"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$((bytes / 1048576))MB"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$((bytes / 1024))KB"
    else
        echo "${bytes}B"
    fi
}

# 显示详细优化报告
show_detailed_optimization_report() {
    echo
    echo -e "${CYAN}${BOLD}📋 详细优化报告：${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    # 显示参数对比表
    show_parameter_comparison
    
    # 显示性能提升分析
    show_performance_improvements
    
    # 显示工作负载特定的优化说明
    show_workload_specific_optimizations
}

# 显示工作负载特定优化说明
show_workload_specific_optimizations() {
    echo
    echo -e "${CYAN}${BOLD}🎯 ${WORKLOAD_TYPE} 工作负载优化说明：${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    case "$WORKLOAD_TYPE" in
        "web")
            echo -e "${GREEN}🌐 Web服务器优化重点：${RESET}"
            echo -e "${WHITE}• 大幅提升并发连接处理能力(somaxconn)${RESET}"
            echo -e "${WHITE}• 优化文件句柄限制，支持更多静态文件服务${RESET}"
            echo -e "${WHITE}• 调整TCP缓冲区，提升HTTP响应速度${RESET}"
            echo -e "${WHITE}• 优化内存管理，减少页面缓存压力${RESET}"
            ;;
        "database")
            echo -e "${BLUE}🗄️ 数据库服务器优化重点：${RESET}"
            echo -e "${WHITE}• 大幅增加网络缓冲区，提升数据传输效率${RESET}"
            echo -e "${WHITE}• 优化共享内存配置，支持大型数据库${RESET}"
            echo -e "${WHITE}• 调整磁盘I/O策略，减少写入延迟${RESET}"
            echo -e "${WHITE}• 降低swap使用，保证数据库内存稳定${RESET}"
            ;;
        "proxy")
            echo -e "${PURPLE}🔄 VPS代理服务器优化重点：${RESET}"
            echo -e "${WHITE}• 极大提升并发连接数(4倍somaxconn)${RESET}"
            echo -e "${WHITE}• 超大文件句柄限制(8倍file-max)${RESET}"
            echo -e "${WHITE}• 优化TIME_WAIT连接处理${RESET}"
            echo -e "${WHITE}• 完全禁用IPv6，消除处理开销${RESET}"
            echo -e "${WHITE}• 全端口范围开放(1024-65535)${RESET}"
            echo -e "${WHITE}• 超大网络缓冲区(4倍rmem/wmem)${RESET}"
            ;;
        "container")
            echo -e "${CYAN}🐳 容器主机优化重点：${RESET}"
            echo -e "${WHITE}• 大幅提升文件句柄限制，支持大量容器${RESET}"
            echo -e "${WHITE}• 优化进程数限制(pid_max)${RESET}"
            echo -e "${WHITE}• 调整内存管理，适应容器动态分配${RESET}"
            echo -e "${WHITE}• 优化网络栈，提升容器间通信${RESET}"
            ;;
        "cache")
            echo -e "${YELLOW}📦 缓存服务器优化重点：${RESET}"
            echo -e "${WHITE}• 超大TCP内存配置，支持海量缓存连接${RESET}"
            echo -e "${WHITE}• 极高并发连接数，适应缓存访问模式${RESET}"
            echo -e "${WHITE}• 优化文件句柄，支持持久化操作${RESET}"
            echo -e "${WHITE}• 调整内存策略，最大化缓存效率${RESET}"
            ;;
        *)
            echo -e "${WHITE}⚙️ 通用服务器优化重点：${RESET}"
            echo -e "${WHITE}• 平衡的网络和内存优化${RESET}"
            echo -e "${WHITE}• 适度提升各项系统限制${RESET}"
            echo -e "${WHITE}• 兼容多种应用场景${RESET}"
            ;;
    esac
    
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# 备份当前配置
backup_current_config() {
    print_msg "working" "备份当前系统配置..."
    
    local backup_file="$BACKUP_DIR/sysctl_backup_$(date +%Y%m%d_%H%M%S).conf"
    
    # 备份当前的sysctl配置
    if sysctl -a > "$backup_file" 2>/dev/null; then
        chmod 600 "$backup_file"
        print_msg "success" "配置已备份到: $backup_file"
        log "配置备份: $backup_file"
    else
        print_msg "warning" "无法完整备份配置，继续执行..."
    fi
}

# 生成配置文件
generate_config_file() {
    print_msg "working" "生成优化配置文件..."
    
    cat > "$SYSCTL_CONF" << EOF
# Linux内核优化配置
# 生成时间: $(date)
# 脚本版本: $SCRIPT_VERSION
# 工作负载: $WORKLOAD_TYPE
# 优化级别: $OPTIMIZATION_LEVEL
# IPv6禁用: $DISABLE_IPV6

EOF

    # 写入所有优化参数
    for param in "${!OPTIMAL_VALUES[@]}"; do
        echo "$param = ${OPTIMAL_VALUES[$param]}" >> "$SYSCTL_CONF"
    done
    
    print_msg "success" "配置文件已生成: $SYSCTL_CONF"
}

# 应用配置
apply_configuration() {
    if [ "$DRY_RUN" = true ]; then
        show_preview_configuration
        return 0
    fi
    
    print_msg "working" "根据系统特性验证并应用配置..."
    
    # 读取当前系统参数值进行对比
    read_current_system_values
    
    # 分析参数变化
    analyze_parameter_changes
    
    local success_count=0
    local fail_count=0
    local failed_params=()
    
    # 过滤参数
    filter_parameters_by_system "$SYSTEM_PROFILE" "$(echo "${!OPTIMAL_VALUES[@]}" | wc -w)"
    
    # 逐个应用参数
    for param in "${!OPTIMAL_VALUES[@]}"; do
        local value="${OPTIMAL_VALUES[$param]}"
        
        if sysctl -w "$param=$value" >/dev/null 2>&1; then
            ((success_count++))
        else
            ((fail_count++))
            failed_params+=("$param=$value")
            print_msg "warning" "参数应用失败: $param=$value"
        fi
    done
    
    print_msg "info" "配置应用结果: $success_count/$((success_count + fail_count)) 个参数成功应用"
    
    if [ $fail_count -gt 0 ]; then
        print_msg "warning" "部分配置参数应用失败($fail_count个)"
        create_clean_config_file "${failed_params[@]}"
        print_msg "info" "已创建清理版配置文件: ${SYSCTL_CONF}-clean.conf"
        print_msg "info" "系统优化仍然有效,只是跳过了不兼容的参数"
    fi
    
    # 显示失败的参数
    if [ ${#failed_params[@]} -gt 0 ]; then
        echo
        print_msg "warning" "失败的参数:"
        for failed_param in "${failed_params[@]}"; do
            echo -e "${RED}  • $failed_param${RESET}"
        done
    fi
    
    print_msg "success" "优化配置应用完成!系统性能已得到提升。"
    print_msg "info" "建议重启系统以确保所有更改完全生效。"
    
    # 显示详细优化报告
    show_detailed_optimization_report
    
    show_optimization_summary $success_count $fail_count
}

# 创建清理版配置文件
create_clean_config_file() {
    local failed_params=("$@")
    local clean_config="${SYSCTL_CONF}-clean.conf"
    
    # 复制原配置文件头部
    head -n 8 "$SYSCTL_CONF" > "$clean_config"
    
    # 添加成功的参数
    for param in "${!OPTIMAL_VALUES[@]}"; do
        local param_line="$param = ${OPTIMAL_VALUES[$param]}"
        local is_failed=false
        
        for failed in "${failed_params[@]}"; do
            if [[ "$param_line" == "$failed" ]]; then
                is_failed=true
                break
            fi
        done
        
        if [ "$is_failed" = false ]; then
            echo "$param_line" >> "$clean_config"
        fi
    done
}

# 根据系统配置档案过滤参数
filter_parameters_by_system() {
    local system_profile="$1"
    local total_params="$2"
    
    print_msg "info" "系统配置: $system_profile"
    print_msg "info" "系统过滤: $total_params -> $total_params 个参数"
}

# 显示预览配置
show_preview_configuration() {
    # 读取当前系统参数值进行对比
    read_current_system_values
    analyze_parameter_changes
    
    echo
    print_msg "preview" "配置预览模式 - 以下是将要应用的参数对比："
    
    # 显示详细对比
    show_parameter_comparison
    show_performance_improvements
    show_workload_specific_optimizations
    
    echo
    print_msg "info" "预览完成，未实际应用任何更改"
    print_msg "info" "要实际应用这些优化，请重新运行并选择非预览模式"
}

# 显示优化摘要
show_optimization_summary() {
    local success_count="$1"
    local fail_count="$2"
    
    echo
    print_msg "success" "优化完成摘要:"
    echo -e "${WHITE}• 已应用参数数量: ${GREEN}${success_count}个${RESET}"
    echo -e "${WHITE}• 系统配置档案: ${GREEN}$SYSTEM_PROFILE${RESET}"
    echo -e "${WHITE}• 配置文件位置: ${GREEN}$SYSCTL_CONF${RESET}"
    echo -e "${WHITE}• 备份文件位置: ${GREEN}$BACKUP_DIR${RESET}"
    echo -e "${WHITE}• 日志文件位置: ${GREEN}$LOG_FILE${RESET}"
    echo -e "${WHITE}• IPv6状态: ${GREEN}$([ "$DISABLE_IPV6" = true ] && echo "已禁用" || echo "保持启用")${RESET}"
    
    # 显示系统特定建议
    show_system_specific_recommendations
}

# 显示系统特定建议
show_system_specific_recommendations() {
    echo
    print_msg "info" "💡 系统特定建议："
    
    case "$SYSTEM_PROFILE" in
        "ubuntu_modern"|"debian_modern"|"fedora_modern")
            echo -e "${GREEN}• ✅ 现代系统，所有优化功能完美支持${RESET}"
            if echo "$KERNEL_FEATURES" | grep -q "bbr"; then
                echo -e "${BLUE}• 🔧 可考虑启用BBR拥塞控制算法提升网络性能${RESET}"
            fi
            ;;
        "ubuntu_lts"|"debian_stable")
            echo -e "${YELLOW}• ⚖️ LTS系统，建议定期更新内核获得更好性能${RESET}"
            ;;
        "rhel_legacy"|"ubuntu_legacy")
            echo -e "${RED}• ⚠️ 老系统，建议升级到新版本获得完整功能支持${RESET}"
            ;;
        "alpine_minimal")
            echo -e "${CYAN}• 🏔️ Alpine系统，已应用轻量化优化配置${RESET}"
            ;;
    esac
    
    case "$ENV_TYPE" in
        "docker"|"container")
            echo -e "${YELLOW}• 🐳 容器环境，部分参数可能需要在宿主机级别配置${RESET}"
            ;;
        "virtual")
            echo -e "${BLUE}• 💻 虚拟机环境，建议关注宿主机资源分配${RESET}"
            ;;
        "physical")
            echo -e "${GREEN}• 🖥️ 物理机环境，可获得最佳优化效果${RESET}"
            ;;
    esac
    
    echo -e "${PURPLE}• 📊 建议安装htop/iotop等监控工具观察优化效果${RESET}"
    echo -e "${CYAN}• 🔄 可运行 'sysctl -p $SYSCTL_CONF' 重新加载配置${RESET}"
}

# ==================== 主流程函数 ====================

# 处理一键优化
handle_quick_optimization() {
    local choice="$1"
    
    case "$choice" in
        1)
            WORKLOAD_TYPE="web"
            OPTIMIZATION_LEVEL="balanced"
            DISABLE_IPV6=false
            AUTO_ROLLBACK_ENABLED=true
            ;;
        2)
            WORKLOAD_TYPE="database"
            OPTIMIZATION_LEVEL="balanced"
            DISABLE_IPV6=false
            AUTO_ROLLBACK_ENABLED=true
            ;;
        3)
            WORKLOAD_TYPE="proxy"
            OPTIMIZATION_LEVEL="aggressive"
            DISABLE_IPV6=true  # VPS代理默认禁用IPv6
            AUTO_ROLLBACK_ENABLED=true
            ;;
        4)
            WORKLOAD_TYPE="container"
            OPTIMIZATION_LEVEL="balanced"
            DISABLE_IPV6=false
            AUTO_ROLLBACK_ENABLED=true
            ;;
        5)
            WORKLOAD_TYPE="general"
            OPTIMIZATION_LEVEL="balanced"
            DISABLE_IPV6=false
            AUTO_ROLLBACK_ENABLED=true
            ;;
        *)
            print_msg "error" "无效选择"
            return 1
            ;;
    esac
    
    # 显示选择确认
    show_quick_optimization_confirmation
}

# 显示一键优化确认
show_quick_optimization_confirmation() {
    echo
    print_msg "info" "一键优化配置确认："
    echo -e "${WHITE}• 工作负载类型: ${GREEN}$WORKLOAD_TYPE${RESET}"
    echo -e "${WHITE}• 优化级别: ${GREEN}$OPTIMIZATION_LEVEL${RESET}"
    echo -e "${WHITE}• IPv6状态: ${GREEN}$([ "$DISABLE_IPV6" = true ] && echo "禁用" || echo "启用")${RESET}"
    echo -e "${WHITE}• 自动回滚: ${GREEN}$([ "$AUTO_ROLLBACK_ENABLED" = true ] && echo "启用" || echo "禁用")${RESET}"
    echo
    
    print_msg "question" "确认应用以上配置？[Y/n]"
    read -r confirm
    
    case "$confirm" in
        [Nn]|[Nn][Oo])
            print_msg "info" "操作已取消"
            return 1
            ;;
        *)
            execute_optimization
            ;;
    esac
}

# 处理自定义配置
handle_custom_configuration() {
    local workload_choice="$1"
    
    # 设置工作负载类型
    case "$workload_choice" in
        1) WORKLOAD_TYPE="web" ;;
        2) WORKLOAD_TYPE="database" ;;
        3) WORKLOAD_TYPE="cache" ;;
        4) WORKLOAD_TYPE="container" ;;
        5) WORKLOAD_TYPE="proxy" ;;
        6) WORKLOAD_TYPE="general" ;;
        *) print_msg "error" "无效选择"; return 1 ;;
    esac
    
    # 选择优化级别
    show_optimization_level_menu
    print_msg "question" "请选择优化级别 [1-3]:"
    read -r level_choice
    
    case "$level_choice" in
        1) OPTIMIZATION_LEVEL="conservative" ;;
        2) OPTIMIZATION_LEVEL="balanced" ;;
        3) OPTIMIZATION_LEVEL="aggressive" ;;
        *) print_msg "error" "无效选择"; return 1 ;;
    esac
    
    # 高级选项
    show_advanced_options_menu
    
    # 显示配置摘要
    show_custom_configuration_summary
}

# 显示自定义配置摘要
show_custom_configuration_summary() {
    echo
    echo -e "${BLUE}${BOLD}📋 自定义配置摘要：${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${WHITE}• 工作负载类型: ${GREEN}$WORKLOAD_TYPE${RESET}"
    echo -e "${WHITE}• 优化级别: ${GREEN}$OPTIMIZATION_LEVEL${RESET}"
    echo -e "${WHITE}• IPv6状态: ${GREEN}$([ "$DISABLE_IPV6" = true ] && echo "禁用" || echo "启用")${RESET}"
    echo -e "${WHITE}• 自动回滚: ${GREEN}$([ "$AUTO_ROLLBACK_ENABLED" = true ] && echo "启用" || echo "禁用")${RESET}"
    echo -e "${WHITE}• 预览模式: ${GREEN}$([ "$DRY_RUN" = true ] && echo "启用" || echo "禁用")${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
    
    print_msg "question" "确认应用以上配置？[Y/n]"
    read -r confirm
    
    case "$confirm" in
        [Nn]|[Nn][Oo])
            print_msg "info" "操作已取消"
            return 1
            ;;
        *)
            execute_optimization
            ;;
    esac
}

# 执行优化
execute_optimization() {
    print_msg "working" "开始执行系统优化..."
    
    # 创建必要目录
    create_directories
    
    # 备份当前配置
    backup_current_config
    
    # 计算最优参数
    calculate_optimal_values "$WORKLOAD_TYPE" "$OPTIMIZATION_LEVEL"
    
    # 生成配置文件
    generate_config_file
    
    # 应用配置
    apply_configuration
    
    echo
    print_msg "success" "系统优化完成！"
}

# 显示系统信息
show_system_info() {
    clear
    print_msg "info" "正在收集系统信息..."
    
    perform_deep_system_detection
    
    echo
    print_msg "info" "按Enter键返回主菜单..."
    read -r
}

# 查看当前优化对比
view_current_optimization_comparison() {
    clear
    print_msg "working" "分析当前系统优化状态..."
    
    # 检查是否存在优化配置文件
    if [ ! -f "$SYSCTL_CONF" ]; then
        print_msg "warning" "未找到优化配置文件，系统可能尚未优化"
        echo -e "${YELLOW}配置文件位置: $SYSCTL_CONF${RESET}"
        echo
        print_msg "info" "请先运行优化后再查看对比效果"
        print_msg "info" "按Enter键返回主菜单..."
        read -r
        return
    fi
    
    print_msg "info" "正在读取已应用的优化配置..."
    
    # 从配置文件读取已优化的参数
    declare -A applied_params=()
    while IFS='=' read -r key value; do
        # 跳过注释和空行
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # 清理键值
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        
        if [ -n "$key" ] && [ -n "$value" ]; then
            applied_params["$key"]="$value"
        fi
    done < "$SYSCTL_CONF"
    
    if [ ${#applied_params[@]} -eq 0 ]; then
        print_msg "error" "配置文件中未找到有效的优化参数"
        print_msg "info" "按Enter键返回主菜单..."
        read -r
        return
    fi
    
    # 设置OPTIMAL_VALUES为已应用的参数，以便使用现有的对比功能
    OPTIMAL_VALUES=()
    for param in "${!applied_params[@]}"; do
        OPTIMAL_VALUES["$param"]="${applied_params[$param]}"
    done
    
    # 读取当前系统值并分析
    read_current_system_values
    analyze_parameter_changes
    
    # 显示对比结果
    echo
    echo -e "${CYAN}${BOLD}📊 当前系统优化状态对比：${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${WHITE}• 配置文件: ${GREEN}$SYSCTL_CONF${RESET}"
    echo -e "${WHITE}• 优化参数总数: ${GREEN}${#OPTIMAL_VALUES[@]}${RESET}"
    echo -e "${WHITE}• 检测时间: ${GREEN}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    # 显示详细对比
    show_parameter_comparison
    show_performance_improvements
    
    # 显示应用状态统计
    show_optimization_status_summary
    
    print_msg "info" "按Enter键返回主菜单..."
    read -r
}

# 显示优化状态摘要
show_optimization_status_summary() {
    local active_count=0
    local inactive_count=0
    local modified_count=0
    
    # 统计参数状态
    for param in "${!OPTIMAL_VALUES[@]}"; do
        local current_value=$(sysctl -n "$param" 2>/dev/null || echo "")
        local expected_value="${OPTIMAL_VALUES[$param]}"
        
        if [ "$current_value" = "$expected_value" ]; then
            ((active_count++))
        else
            ((inactive_count++))
            if [ -n "$current_value" ] && [ "$current_value" != "${ORIGINAL_VALUES[$param]:-}" ]; then
                ((modified_count++))
            fi
        fi
    done
    
    echo
    echo -e "${CYAN}${BOLD}📈 优化状态统计：${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${GREEN}✅ 正常应用的参数: ${BOLD}${active_count}${RESET}${GREEN} 个${RESET}"
    
    if [ $inactive_count -gt 0 ]; then
        echo -e "${YELLOW}⚠️  状态异常的参数: ${BOLD}${inactive_count}${RESET}${YELLOW} 个${RESET}"
        echo -e "${BLUE}ℹ️  建议运行 'sysctl -p $SYSCTL_CONF' 重新加载配置${RESET}"
    fi
    
    if [ $modified_count -gt 0 ]; then
        echo -e "${PURPLE}🔄 被其他程序修改的参数: ${BOLD}${modified_count}${RESET}${PURPLE} 个${RESET}"
    fi
    
    # 显示优化效果评估
    local effectiveness=$((active_count * 100 / ${#OPTIMAL_VALUES[@]}))
    echo -e "${CYAN}📊 优化生效率: ${BOLD}${effectiveness}%${RESET}"
    
    if [ $effectiveness -ge 90 ]; then
        echo -e "${GREEN}🎉 优化效果: 优秀 - 系统性能已得到全面提升${RESET}"
    elif [ $effectiveness -ge 70 ]; then
        echo -e "${YELLOW}👍 优化效果: 良好 - 大部分优化已生效${RESET}"
    else
        echo -e "${RED}⚠️  优化效果: 需要注意 - 建议检查系统配置${RESET}"
    fi
    
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}
restore_default_config() {
    print_msg "working" "准备恢复默认配置..."
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        print_msg "error" "未找到备份文件，无法恢复"
        return 1
    fi
    
    # 列出可用备份
    echo -e "${WHITE}可用的备份文件：${RESET}"
    local backup_files=($(ls -t "$BACKUP_DIR"/sysctl_backup_*.conf 2>/dev/null))
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        print_msg "error" "未找到有效的备份文件"
        return 1
    fi
    
    local latest_backup="${backup_files[0]}"
    print_msg "info" "最新备份: $(basename "$latest_backup")"
    
    print_msg "question" "确认恢复到最新备份？[y/N]"
    read -r confirm
    
    case "$confirm" in
        [Yy]|[Yy][Ee][Ss])
            if [ -f "$SYSCTL_CONF" ]; then
                rm -f "$SYSCTL_CONF"
                print_msg "success" "已删除优化配置文件"
            fi
            
            sysctl -p >/dev/null 2>&1 || true
            print_msg "success" "配置已恢复，建议重启系统以确保完全生效"
            ;;
        *)
            print_msg "info" "操作已取消"
            ;;
    esac
}

# 命令行参数处理
handle_command_line_args() {
    case "${1:-}" in
        --web|--nginx|--apache)
            WORKLOAD_TYPE="web"
            OPTIMIZATION_LEVEL="balanced"
            AUTO_ROLLBACK_ENABLED=true
            execute_optimization
            exit 0
            ;;
        --database|--mysql|--postgresql)
            WORKLOAD_TYPE="database"
            OPTIMIZATION_LEVEL="balanced"
            AUTO_ROLLBACK_ENABLED=true
            execute_optimization
            exit 0
            ;;
        --proxy|--ss|--v2ray|--trojan)
            WORKLOAD_TYPE="proxy"
            OPTIMIZATION_LEVEL="aggressive"
            DISABLE_IPV6=true
            AUTO_ROLLBACK_ENABLED=true
            execute_optimization
            exit 0
            ;;
        --container|--docker|--k8s)
            WORKLOAD_TYPE="container"
            OPTIMIZATION_LEVEL="balanced"
            AUTO_ROLLBACK_ENABLED=true
            execute_optimization
            exit 0
            ;;
        --preview)
            DRY_RUN=true
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        --version|-v)
            echo "Linux内核优化脚本 v$SCRIPT_VERSION"
            exit 0
            ;;
    esac
}

# 显示帮助信息
show_help() {
    echo -e "${CYAN}${BOLD}Linux内核优化脚本 v$SCRIPT_VERSION${RESET}"
    echo
    echo -e "${WHITE}使用方法:${RESET}"
    echo -e "  $0 [选项]"
    echo
    echo -e "${WHITE}交互式模式:${RESET}"
    echo -e "  $0                    启动交互式菜单"
    echo
    echo -e "${WHITE}快速优化选项:${RESET}"
    echo -e "  --web                 Web服务器优化"
    echo -e "  --database            数据库服务器优化"
    echo -e "  --proxy               VPS代理服务器优化"
    echo -e "  --container           容器主机优化"
    echo
    echo -e "${WHITE}其他选项:${RESET}"
    echo -e "  --preview             预览模式（不实际应用）"
    echo -e "  --help, -h            显示此帮助信息"
    echo -e "  --version, -v         显示版本信息"
    echo
}

# 主程序
main() {
    # 处理命令行参数
    handle_command_line_args "$@"
    
    # 检查运行环境
    check_root
    create_directories
    
    # 执行系统检测
    perform_deep_system_detection
    
    # 主循环
    while true; do
        show_main_menu
        print_msg "question" "请选择操作 [0-5]:"
        read -r main_choice
        
        case "$main_choice" in
            1)
                while true; do
                    show_quick_optimization_menu
                    print_msg "question" "请选择服务器类型 [0-5]:"
                    read -r quick_choice
                    
                    case "$quick_choice" in
                        0) break ;;
                        [1-5])
                            if handle_quick_optimization "$quick_choice"; then
                                print_msg "info" "按Enter键继续..."
                                read -r
                            fi
                            break
                            ;;
                        *)
                            print_msg "error" "无效选择，请重新输入"
                            sleep 1
                            ;;
                    esac
                done
                ;;
            2)
                show_custom_configuration_menu
                print_msg "question" "请选择工作负载类型 [0-6]:"
                read -r custom_choice
                
                case "$custom_choice" in
                    0) continue ;;
                    [1-6])
                        if handle_custom_configuration "$custom_choice"; then
                            print_msg "info" "按Enter键继续..."
                            read -r
                        fi
                        ;;
                    *)
                        print_msg "error" "无效选择"
                        sleep 1
                        ;;
                esac
                ;;
            3)
                show_system_info
                ;;
            4)
                view_current_optimization_comparison
                ;;
            5)
                restore_default_config
                print_msg "info" "按Enter键继续..."
                read -r
                ;;
            0)
                print_msg "success" "感谢使用Linux内核优化脚本！"
                exit 0
                ;;
            *)
                print_msg "error" "无效选择，请重新输入"
                sleep 1
                ;;
        esac
    done
}

# 脚本入口点
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
