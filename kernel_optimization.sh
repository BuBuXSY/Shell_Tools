#!/bin/bash
# Linux 内核优化脚本
# BY BuBuXSY
# Version: 2025.07.19 

# 颜色和样式定义
RED="\e[1;31m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
BLUE="\e[1;34m"
PURPLE="\e[1;35m"
CYAN="\e[1;36m"
WHITE="\e[1;37m"
BOLD="\e[1m"
RESET="\e[0m"

# 全局配置
LOG_FILE="/var/log/kernel_optimization.log"
BACKUP_DIR="/var/backups/kernel_optimization"
VERSION_DIR="/etc/kernel_optimization/versions"
BENCHMARK_DIR="/var/log/kernel_optimization/benchmarks"
EXPORT_DIR="/root/kernel_optimization_exports"

# 创建必要的目录
mkdir -p "$BACKUP_DIR" "$VERSION_DIR" "$BENCHMARK_DIR" "$EXPORT_DIR" 2>/dev/null

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

# 优化参数存储
declare -A OPTIMAL_VALUES
declare -A TEST_RESULTS

# ==================== 基础函数 ====================

# 日志记录函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" 2>/dev/null || echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
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
    esac
}

# 检查命令是否存在
check_command() {
    command -v "$1" >/dev/null 2>&1
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

# ==================== 系统检测函数 ====================

# 检测Linux发行版详细信息
detect_distro() {
    print_msg "working" "正在检测Linux发行版..."
    
    if [ -f /etc/os-release ]; then
        # 安全地读取os-release文件
        eval "$(grep -E '^(NAME|VERSION_ID|ID)=' /etc/os-release 2>/dev/null || echo 'NAME="Unknown"; VERSION_ID="0"; ID="unknown"')"
        OS="${NAME:-Unknown}"
        VER="${VERSION_ID:-0}"
        local system_id="${ID:-unknown}"
        
        # 检测发行版系列
        case "$system_id" in
            ubuntu|debian|linuxmint|pop|elementary)
                DISTRO_FAMILY="debian"
                ;;
            centos|rhel|fedora|rocky|almalinux|ol)
                DISTRO_FAMILY="redhat"
                ;;
            arch|manjaro|endeavouros)
                DISTRO_FAMILY="arch"
                ;;
            opensuse*|sles)
                DISTRO_FAMILY="suse"
                ;;
            alpine)
                DISTRO_FAMILY="alpine"
                ;;
            *)
                DISTRO_FAMILY="unknown"
                ;;
        esac
        
        print_msg "success" "检测到系统: $OS $VER (${DISTRO_FAMILY}系) 🐧"
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
    if check_command free; then
        TOTAL_MEM=$(free -b 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")
        if [ "$TOTAL_MEM" -gt 0 ]; then
            TOTAL_MEM_GB=$((TOTAL_MEM / 1024 / 1024 / 1024))
        else
            TOTAL_MEM_GB="0"
        fi
    else
        TOTAL_MEM="0"
        TOTAL_MEM_GB="0"
    fi
    
    # CPU核心检测
    if check_command nproc; then
        CPU_CORES=$(nproc 2>/dev/null || echo "1")
    else
        CPU_CORES=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "1")
    fi
    
    # 内核版本检测
    KERNEL_VERSION=$(uname -r 2>/dev/null || echo "unknown")
    
    echo -e "${WHITE}┌─────────────────────────────────────────┐${RESET}"
    echo -e "${WHITE}│            ${BOLD}系统信息${RESET}${WHITE}                     │${RESET}"
    echo -e "${WHITE}├─────────────────────────────────────────┤${RESET}"
    echo -e "${WHITE}│ 💾 内存: ${GREEN}${TOTAL_MEM_GB} GB${WHITE}                       │${RESET}"
    echo -e "${WHITE}│ 🖥️  CPU核心数: ${GREEN}${CPU_CORES}${WHITE}                        │${RESET}"
    echo -e "${WHITE}│ 🐧 内核版本: ${GREEN}${KERNEL_VERSION}${WHITE}           │${RESET}"
    echo -e "${WHITE}│ 📦 发行版系列: ${GREEN}${DISTRO_FAMILY}${WHITE}                     │${RESET}"
    echo -e "${WHITE}└─────────────────────────────────────────┘${RESET}"
    echo
    
    log "系统资源 - 内存: ${TOTAL_MEM_GB}GB, CPU核心: $CPU_CORES, 内核: $KERNEL_VERSION"
}

# 检测虚拟化环境
detect_virtualization() {
    print_msg "working" "检测虚拟化环境..."
    
    if [ -f /.dockerenv ]; then
        ENV_TYPE="docker"
        print_msg "warning" "检测到Docker容器环境，某些参数可能无法修改"
    elif check_command systemd-detect-virt; then
        local virt_type=$(systemd-detect-virt 2>/dev/null || echo "none")
        if [ "$virt_type" != "none" ]; then
            ENV_TYPE="virtual"
            print_msg "info" "检测到虚拟化环境: $virt_type"
        else
            ENV_TYPE="physical"
            print_msg "success" "检测到物理机环境"
        fi
    else
        ENV_TYPE="physical"
        print_msg "success" "检测到物理机环境"
    fi
    
    log "运行环境: $ENV_TYPE"
}

# ==================== 智能参数计算 ====================

# 智能计算最优参数
calculate_optimal_values() {
    local total_mem_bytes="${1:-$TOTAL_MEM}"
    local cpu_cores="${2:-$CPU_CORES}"
    local workload_type="${3:-general}"
    
    print_msg "working" "基于系统资源计算最优参数..."
    
    # 确保输入有效
    total_mem_bytes=${total_mem_bytes:-1073741824}  # 默认1GB
    cpu_cores=${cpu_cores:-1}
    
    # 基础计算
    local tcp_mem_max=$((total_mem_bytes / 32))
    local net_core_rmem_max=$((total_mem_bytes / 128))
    local net_core_wmem_max=$((total_mem_bytes / 128))
    local somaxconn=$((cpu_cores * 8192))
    local file_max=$((cpu_cores * 65536))
    
    # 根据工作负载类型调整
    case "$workload_type" in
        "web")
            somaxconn=$((somaxconn * 2))
            file_max=$((file_max * 2))
            ;;
        "database")
            tcp_mem_max=$((tcp_mem_max * 2))
            net_core_rmem_max=$((net_core_rmem_max * 2))
            ;;
        "cache")
            tcp_mem_max=$((tcp_mem_max * 3))
            somaxconn=$((somaxconn * 3))
            ;;
    esac
    
    # 确保值在合理范围内
    [ $tcp_mem_max -gt 268435456 ] && tcp_mem_max=268435456
    [ $tcp_mem_max -lt 4194304 ] && tcp_mem_max=4194304
    
    [ $net_core_rmem_max -gt 134217728 ] && net_core_rmem_max=134217728
    [ $net_core_rmem_max -lt 1048576 ] && net_core_rmem_max=1048576
    
    [ $net_core_wmem_max -gt 134217728 ] && net_core_wmem_max=134217728
    [ $net_core_wmem_max -lt 1048576 ] && net_core_wmem_max=1048576
    
    [ $somaxconn -gt 65535 ] && somaxconn=65535
    [ $somaxconn -lt 1024 ] && somaxconn=1024
    
    [ $file_max -gt 2097152 ] && file_max=2097152
    [ $file_max -lt 65536 ] && file_max=65536
    
    # 存储计算结果
    OPTIMAL_VALUES["tcp_mem_max"]="$tcp_mem_max"
    OPTIMAL_VALUES["net_core_rmem_max"]="$net_core_rmem_max"
    OPTIMAL_VALUES["net_core_wmem_max"]="$net_core_wmem_max"
    OPTIMAL_VALUES["somaxconn"]="$somaxconn"
    OPTIMAL_VALUES["file_max"]="$file_max"
    
    print_msg "success" "参数计算完成"
    log "智能参数计算: tcp_mem_max=$tcp_mem_max, somaxconn=$somaxconn, file_max=$file_max"
}

# ==================== 系统检查 ====================

# 系统状态预检查
pre_optimization_check() {
    local issues=0
    
    print_msg "test" "执行系统状态预检查..."
    
    # 检查系统负载
    if check_command uptime; then
        local load_info=$(uptime 2>/dev/null)
        if [ -n "$load_info" ]; then
            local load_avg=$(echo "$load_info" | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',' 2>/dev/null || echo "0")
            local load_int=$(echo "$load_avg" | cut -d. -f1)
            if [ "${load_int:-0}" -gt 5 ]; then
                print_msg "warning" "系统负载较高 ($load_avg)，建议在低峰期进行优化"
                ((issues++))
            fi
        fi
    fi
    
    # 检查磁盘空间
    if check_command df; then
        local disk_usage=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
        if [ "${disk_usage:-0}" -gt 90 ]; then
            print_msg "warning" "根分区使用率过高 (${disk_usage}%)"
            ((issues++))
        fi
    fi
    
    # 检查内存使用
    if check_command free; then
        local mem_usage=$(free 2>/dev/null | awk 'NR==2{printf "%.0f", $3*100/$2}' || echo "0")
        if [ "${mem_usage:-0}" -gt 95 ]; then
            print_msg "error" "内存使用率过高 (${mem_usage}%)"
            ((issues++))
        fi
    fi
    
    if [ $issues -eq 0 ]; then
        print_msg "success" "系统状态检查通过"
        TEST_RESULTS["pre_check"]="PASS"
    else
        print_msg "warning" "发现 $issues 个潜在问题"
        TEST_RESULTS["pre_check"]="WARN"
    fi
    
    log "系统状态预检查完成，发现 $issues 个问题"
    return $issues
}

# ==================== 配置应用函数 ====================

# 备份文件
backup_file() {
    local file="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup="${BACKUP_DIR}/$(basename "$file").${timestamp}"
    
    if [ -f "$file" ]; then
        if cp -p "$file" "$backup" 2>/dev/null; then
            print_msg "success" "已备份: $(basename "$file") 💾"
            log "创建备份: $backup"
        else
            print_msg "warning" "备份失败: $file"
        fi
    fi
}

# 应用优化设置
apply_optimizations() {
    local optimization_level="${1:-balanced}"
    
    print_msg "working" "开始应用优化设置..."
    
    # 备份原始配置
    backup_file "/etc/sysctl.conf"
    
    # 计算最优参数
    calculate_optimal_values "$TOTAL_MEM" "$CPU_CORES" "$WORKLOAD_TYPE"
    
    # 创建优化配置
    local temp_config="/tmp/sysctl_optimized_$$.conf"
    
    cat > "$temp_config" <<EOF
# Linux内核优化配置 - 生成时间: $(date)
# 优化级别: $optimization_level
# 工作负载: $WORKLOAD_TYPE

# 网络核心设置
net.core.somaxconn = ${OPTIMAL_VALUES["somaxconn"]}
net.core.netdev_max_backlog = 32768
net.core.rmem_max = ${OPTIMAL_VALUES["net_core_rmem_max"]}
net.core.wmem_max = ${OPTIMAL_VALUES["net_core_wmem_max"]}

# TCP设置
net.ipv4.tcp_rmem = 4096 87380 ${OPTIMAL_VALUES["net_core_rmem_max"]}
net.ipv4.tcp_wmem = 4096 65536 ${OPTIMAL_VALUES["net_core_wmem_max"]}
net.ipv4.tcp_mem = 786432 1048576 ${OPTIMAL_VALUES["tcp_mem_max"]}
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 1024 65535

# 文件系统设置
fs.file-max = ${OPTIMAL_VALUES["file_max"]}
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
fs.aio-max-nr = 1048576

# 基础安全设置
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
EOF

    # 根据级别添加额外设置
    if [[ "$optimization_level" == "aggressive" ]]; then
        cat >> "$temp_config" <<'EOF'

# 激进优化设置
vm.dirty_ratio = 10
vm.dirty_background_ratio = 3
vm.swappiness = 1
EOF
    fi
    
    # 应用配置
    if sysctl -p "$temp_config" >/dev/null 2>&1; then
        cat "$temp_config" >> /etc/sysctl.conf
        print_msg "success" "优化设置应用成功！🎉"
        
        # 显示关键参数
        echo
        echo -e "${CYAN}${BOLD}📊 应用的关键参数：${RESET}"
        echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${WHITE}网络连接队列: ${GREEN}${OPTIMAL_VALUES["somaxconn"]}${RESET}"
        echo -e "${WHITE}文件句柄限制: ${GREEN}${OPTIMAL_VALUES["file_max"]}${RESET}"
        echo -e "${WHITE}网络接收缓冲: ${GREEN}${OPTIMAL_VALUES["net_core_rmem_max"]} 字节${RESET}"
        echo -e "${WHITE}TCP内存限制: ${GREEN}${OPTIMAL_VALUES["tcp_mem_max"]} 字节${RESET}"
        echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        
        # 保存版本
        version_control "应用优化设置: $optimization_level 级别"
        
        rm -f "$temp_config"
        return 0
    else
        print_msg "error" "配置应用失败"
        rm -f "$temp_config"
        return 1
    fi
}

# 版本控制
version_control() {
    local description="${1:-自动保存}"
    local version="v$(date +%Y%m%d_%H%M%S)"
    local version_dir="$VERSION_DIR/$version"
    
    if mkdir -p "$version_dir" 2>/dev/null; then
        # 保存当前配置
        for config_file in "/etc/sysctl.conf" "/etc/security/limits.conf"; do
            if [ -f "$config_file" ]; then
                cp "$config_file" "$version_dir/" 2>/dev/null
            fi
        done
        
        # 记录版本信息
        cat > "$version_dir/info.txt" <<EOF
版本: $version
创建时间: $(date)
优化级别: ${OPTIMIZATION:-未知}
工作负载: ${WORKLOAD_TYPE:-未知}
系统信息: $OS $VER
内核版本: $KERNEL_VERSION
运行环境: $ENV_TYPE
描述: $description
操作用户: $(whoami)
EOF
        
        print_msg "success" "配置版本已保存: $version"
        log "创建配置版本: $version - $description"
    else
        print_msg "warning" "无法创建版本目录: $version_dir"
    fi
}

# 回滚更改
rollback_changes() {
    echo
    print_msg "warning" "🔄 正在启动回滚程序..."
    
    # 显示可用版本
    if [ -d "$VERSION_DIR" ] && [ "$(ls -A "$VERSION_DIR" 2>/dev/null)" ]; then
        echo -e "${CYAN}可用的备份版本:${RESET}"
        ls -lt "$VERSION_DIR" 2>/dev/null | head -5
    else
        print_msg "error" "未找到备份版本"
        return 1
    fi
    
    echo
    echo -n "是否回滚到最新备份? [y/N]: "
    read -r confirm_choice
    
    if [[ "$confirm_choice" =~ ^[Yy]$ ]]; then
        # 找到最新的版本
        local latest_version=$(ls -t "$VERSION_DIR" 2>/dev/null | head -1)
        
        if [ -n "$latest_version" ] && [ -d "$VERSION_DIR/$latest_version" ]; then
            # 恢复配置文件
            if [ -f "$VERSION_DIR/$latest_version/sysctl.conf" ]; then
                if cp "$VERSION_DIR/$latest_version/sysctl.conf" "/etc/sysctl.conf" 2>/dev/null; then
                    print_msg "success" "已恢复: sysctl.conf"
                    log "回滚: sysctl.conf 从版本 $latest_version"
                    
                    # 应用配置
                    if sysctl -p >/dev/null 2>&1; then
                        print_msg "success" "回滚完成！🔄"
                        version_control "回滚到版本 $latest_version"
                    else
                        print_msg "warning" "配置文件已恢复，但应用失败"
                    fi
                else
                    print_msg "error" "文件恢复失败"
                    return 1
                fi
            else
                print_msg "error" "备份文件不存在"
                return 1
            fi
        else
            print_msg "error" "未找到有效的备份版本"
            return 1
        fi
    else
        print_msg "info" "已取消回滚操作"
    fi
}

# ==================== 交互式配置向导 ====================

# 交互式配置向导
interactive_config_wizard() {
    echo
    echo -e "${CYAN}${BOLD}🧙‍♂️ 智能配置向导${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    print_msg "info" "向导将根据您的需求推荐最佳配置"
    echo
    
    # 工作负载类型选择
    echo -e "${BLUE}请选择主要工作负载类型:${RESET}"
    echo -e "${GREEN}1)${RESET} Web服务器 (Nginx/Apache)"
    echo -e "${GREEN}2)${RESET} 数据库服务器 (MySQL/PostgreSQL)"
    echo -e "${GREEN}3)${RESET} 缓存服务器 (Redis/Memcached)"
    echo -e "${GREEN}4)${RESET} 通用服务器"
    echo -e "${GREEN}5)${RESET} 容器主机 (Docker/K8s)"
    echo
    
    echo -n "请选择 [1-5]: "
    read -r workload_choice
    
    case "$workload_choice" in
        1) WORKLOAD_TYPE="web"; print_msg "info" "已选择: Web服务器优化" ;;
        2) WORKLOAD_TYPE="database"; print_msg "info" "已选择: 数据库服务器优化" ;;
        3) WORKLOAD_TYPE="cache"; print_msg "info" "已选择: 缓存服务器优化" ;;
        4) WORKLOAD_TYPE="general"; print_msg "info" "已选择: 通用服务器优化" ;;
        5) WORKLOAD_TYPE="container"; print_msg "info" "已选择: 容器主机优化" ;;
        *) WORKLOAD_TYPE="general"; print_msg "info" "默认选择: 通用服务器优化" ;;
    esac
    
    echo
    # 性能/稳定性平衡
    echo -e "${BLUE}请选择性能/稳定性偏好:${RESET}"
    echo -e "${GREEN}1)${RESET} 最大稳定性 (保守优化，适合生产环境)"
    echo -e "${GREEN}2)${RESET} 平衡模式 (性能与稳定性兼顾)"
    echo -e "${GREEN}3)${RESET} 最大性能 (激进优化，需要充分测试)"
    echo
    
    echo -n "请选择 [1-3]: "
    read -r performance_choice
    
    case "$performance_choice" in
        1) OPTIMIZATION="conservative"; print_msg "info" "已选择: 保守优化模式" ;;
        2) OPTIMIZATION="balanced"; print_msg "info" "已选择: 平衡优化模式" ;;
        3) OPTIMIZATION="aggressive"; print_msg "info" "已选择: 激进优化模式" ;;
        *) OPTIMIZATION="balanced"; print_msg "info" "默认选择: 平衡优化模式" ;;
    esac
    
    # 显示配置摘要
    echo
    echo -e "${CYAN}${BOLD}📋 配置摘要${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${WHITE}工作负载类型: ${GREEN}$WORKLOAD_TYPE${RESET}"
    echo -e "${WHITE}优化级别: ${GREEN}$OPTIMIZATION${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    log "配置向导完成: workload=$WORKLOAD_TYPE, optimization=$OPTIMIZATION"
}

# ==================== 显示功能 ====================

# 显示当前配置
show_current_config() {
    echo
    echo -e "${CYAN}${BOLD}📋 当前系统配置${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    # 显示关键sysctl参数
    local key_params=(
        "net.core.somaxconn"
        "fs.file-max"
        "net.core.rmem_max"
        "net.core.wmem_max"
        "net.ipv4.tcp_syncookies"
        "vm.swappiness"
    )
    
    for param in "${key_params[@]}"; do
        local current_value=$(sysctl -n "$param" 2>/dev/null || echo "未设置")
        printf "${WHITE}%-25s${RESET} = ${GREEN}%s${RESET}\n" "$param" "$current_value"
    done
    
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
    echo -n "按任意键返回主菜单..."
    read -r
}

# 显示系统信息
show_system_info() {
    echo
    echo -e "${CYAN}${BOLD}ℹ️ 详细系统信息${RESET}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    echo -e "${BLUE}基础信息:${RESET}"
    echo "  操作系统: $OS $VER ($DISTRO_FAMILY系)"
    echo "  内核版本: $KERNEL_VERSION"
    echo "  主机名: $(hostname)"
    echo "  运行环境: $ENV_TYPE"
    
    echo -e "\n${BLUE}硬件资源:${RESET}"
    echo "  CPU核心: $CPU_CORES"
    echo "  物理内存: ${TOTAL_MEM_GB} GB"
    
    echo -e "\n${BLUE}当前配置:${RESET}"
    echo "  优化级别: ${OPTIMIZATION:-未设置}"
    echo "  工作负载: ${WORKLOAD_TYPE:-未设置}"
    
    if [ ${#OPTIMAL_VALUES[@]} -gt 0 ]; then
        echo -e "\n${BLUE}计算的最优参数:${RESET}"
        for key in "${!OPTIMAL_VALUES[@]}"; do
            echo "  $key: ${OPTIMAL_VALUES[$key]}"
        done
    fi
    
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
    echo -n "按任意键返回主菜单..."
    read -r
}

# ==================== 主菜单 ====================

# 打印横幅
print_banner() {
    clear
    echo -e "${CYAN}╔═════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║        ${BOLD}🚀 Linux 内核优化脚本 v4.3 Fixed 🚀${RESET}${CYAN}              ║${RESET}"
    echo -e "${CYAN}║                    ${WHITE}菜单修复中文版${CYAN}                                ║${RESET}"
    echo -e "${CYAN}║   ${YELLOW}✨ 修复：菜单输入 | 交互逻辑 | 错误处理 ✨${CYAN}   ║${RESET}"
    echo -e "${CYAN}╚═════════════════════════════════════════════════════════════════════╝${RESET}"
    echo
}

# 主菜单
main_menu() {
    while true; do
        echo
        echo -e "${CYAN}${BOLD}📋 主菜单 - v4.3 Fixed${RESET}"
        echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${GREEN}1)${RESET} 🧙‍♂️ 智能配置向导 (推荐)"
        echo -e "${GREEN}2)${RESET} 🚀 快速优化 (使用默认配置)"
        echo -e "${BLUE}3)${RESET} 🧪 系统状态检查"
        echo -e "${BLUE}4)${RESET} 📊 显示当前配置"
        echo -e "${YELLOW}5)${RESET} 🔄 回滚更改"
        echo -e "${YELLOW}6)${RESET} 💾 备份配置"
        echo -e "${WHITE}7)${RESET} ℹ️ 系统信息"
        echo -e "${RED}8)${RESET} 🚪 退出"
        echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        
        echo -n "请选择选项 [1-8]: "
        read -r choice
        
        echo  # 添加空行
        
        case "$choice" in
            1) 
                interactive_config_wizard
                echo
                echo -n "是否立即应用配置? [Y/n]: "
                read -r apply_choice
                if [[ ! "$apply_choice" =~ ^[Nn]$ ]]; then
                    apply_optimizations "$OPTIMIZATION"
                fi
                ;;
            2) 
                OPTIMIZATION="balanced"
                WORKLOAD_TYPE="general"
                print_msg "info" "使用默认配置: 平衡模式 / 通用服务器"
                apply_optimizations "$OPTIMIZATION"
                ;;
            3) 
                pre_optimization_check
                echo
                echo -n "按任意键返回主菜单..."
                read -r
                ;;
            4) 
                show_current_config 
                ;;
            5) 
                rollback_changes 
                ;;
            6) 
                version_control "手动备份"
                echo
                echo -n "按任意键返回主菜单..."
                read -r
                ;;
            7) 
                show_system_info 
                ;;
            8) 
                echo
                print_msg "info" "感谢使用Linux内核优化脚本 v4.3 Fixed！👋"
                exit 0
                ;;
            *) 
                print_msg "error" "无效的选择: [$choice]，请选择1-8"
                sleep 1
                ;;
        esac
    done
}

# ==================== 初始化和主函数 ====================

# 初始化函数
init_system() {
    check_root
    detect_distro
    detect_resources
    detect_virtualization
    
    log "系统初始化完成"
}

# 清理函数
cleanup() {
    # 清理临时文件
    rm -f /tmp/*sysctl*$$.conf 2>/dev/null
}

# 信号处理
trap 'echo; print_msg "warning" "脚本被中断"; cleanup; exit 1' INT TERM
trap 'cleanup' EXIT

# 主函数
main() {
    log "修复版脚本由 $(whoami) 启动"
    
    case "${1:-}" in
        "--help"|"-h")
            echo "修复版Linux内核优化脚本 v4.3 - 使用帮助"
            echo ""
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --quick                 快速设置（使用默认配置）"
            echo "  --wizard                智能配置向导"
            echo "  --check                 系统状态检查"
            echo "  --rollback             回滚配置"
            echo "  --backup               备份当前配置"
            echo "  --version              显示版本信息"
            echo "  --help                 显示帮助信息"
            echo ""
            echo "本次修复内容:"
            echo "  ✅ 修复菜单输入无响应问题"
            echo "  ✅ 简化交互逻辑"
            echo "  ✅ 改进错误处理"
            echo "  ✅ 优化用户体验"
            exit 0
            ;;
        "--version")
            echo "修复版Linux内核优化脚本 v4.3 Fixed"
            echo "主要修复: 菜单输入逻辑问题"
            exit 0
            ;;
        "--quick")
            init_system
            OPTIMIZATION="balanced"
            WORKLOAD_TYPE="general"
            apply_optimizations "$OPTIMIZATION"
            ;;
        "--wizard")
            init_system
            interactive_config_wizard
            apply_optimizations "$OPTIMIZATION"
            ;;
        "--check")
            init_system
            pre_optimization_check
            ;;
        "--rollback")
            rollback_changes
            ;;
        "--backup")
            version_control "手动备份"
            ;;
        "")
            print_banner
            echo
            print_msg "info" "欢迎使用修复版内核优化脚本！"
            echo
            print_msg "question" "选择运行模式:"
            echo -e "${GREEN}1)${RESET} 🧙‍♂️ 智能配置向导 (推荐)"
            echo -e "${GREEN}2)${RESET} 🚀 快速优化 (使用默认配置)"
            echo -e "${BLUE}3)${RESET} 📋 完整功能菜单"
            echo
            
            echo -n "请选择 [1-3]: "
            read -r mode_choice
            
            init_system
            
            case "$mode_choice" in
                1) 
                    interactive_config_wizard
                    apply_optimizations "$OPTIMIZATION"
                    ;;
                2) 
                    OPTIMIZATION="balanced"
                    WORKLOAD_TYPE="general"
                    apply_optimizations "$OPTIMIZATION"
                    ;;
                3|*) 
                    main_menu 
                    ;;
            esac
            ;;
        *)
            print_msg "error" "未知选项: $1"
            echo "使用 --help 查看帮助信息"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
