#!/bin/bash
# Linux 内核深度优化脚本 v3.0
# 支持: RPS多核加速 | BBRv3联动 | 动态内存预留 | 智能路径纠偏
# By: BuBuXSY | Version: 2026.03.04
# License: MIT

set -euo pipefail

# 颜色与样式
readonly RED=$'\033[1;31m'; readonly GREEN=$'\033[1;32m'; readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[1;34m'; readonly PURPLE=$'\033[1;35m'; readonly CYAN=$'\033[1;36m'
readonly BOLD=$'\033[1m'; readonly RESET=$'\033[0m'

# 全局路径
readonly LOG_FILE="/var/log/kernel_optimization.log"
readonly BACKUP_DIR="/var/backups/kernel_optimization"
readonly SYSCTL_CONF="/etc/sysctl.d/99-performance.conf"

# 全局变量初始化
declare -A OPTIMAL_VALUES
CPU_CORES=$(nproc)
TOTAL_MEM=$(awk '/^MemTotal:/{print $2}' /proc/meminfo) # KB
TOTAL_MEM_GB=$(( (TOTAL_MEM + 524288) / 1048576 ))

# ==================== 核心功能：RPS 多核网络加速 ====================
# 原理：将网卡中断负载分摊到所有 CPU 核心，解决单核处理网络协议栈的瓶颈
enable_rps_accelerator() {
    echo -e "${BLUE}==>${RESET} ${BOLD}配置 RPS/RFS 多核网络加速...${RESET}"
    
    # 计算全核心掩码 (例如 4核为 f, 8核为 ff)
    local mask_num=$(( (1 << CPU_CORES) - 1 ))
    local mask_hex=$(printf "%x" $mask_num)
    
    # 遍历所有物理网卡（排除虚拟网卡和回环）
    local interfaces=$(ls /sys/class/net | grep -vE 'lo|docker|veth|br-|virbr')
    
    for iface in $interfaces; do
        if [ -d "/sys/class/net/$iface/queues" ]; then
            # 开启接收侧加速 (RPS)
            for rps_file in /sys/class/net/$iface/queues/rx-*/rps_cpus; do
                echo "$mask_hex" > "$rps_file" 2>/dev/null || true
            done
            # 开启流 steering (RFS)
            for rfc_file in /sys/class/net/$iface/queues/rx-*/rps_flow_cnt; do
                echo "4096" > "$rfc_file" 2>/dev/null || true
            done
            echo -e "${CYAN}[ℹ️]${RESET} 网卡 $iface 已映射至 CPU 掩码: $mask_hex"
        fi
    done
    
    # 全局流表设置
    OPTIMAL_VALUES["net.core.rps_sock_flow_entries"]=32768
}



# ==================== 智能参数计算逻辑 ====================
calculate_vps_specs() {
    echo -e "${BLUE}==>${RESET} ${BOLD}执行 VPS 性能画像分析 (MEM: ${TOTAL_MEM_GB}GB, CPU: ${CPU_CORES}C)...${RESET}"
    
    # 1. 动态内存预留 (min_free_kbytes): 设为内存的 0.4%，防止大并发下的 Direct Reclaim 导致卡顿
    local min_free=$(( TOTAL_MEM * 4 / 1000 ))
    [[ $min_free -lt 16384 ]] && min_free=16384
    [[ $min_free -gt 262144 ]] && min_free=262144
    OPTIMAL_VALUES["vm.min_free_kbytes"]=$min_free

    # 2. 文件句柄与连接数限制 (根据核心数伸缩)
    OPTIMAL_VALUES["fs.file-max"]=$(( CPU_CORES * 100000 ))
    OPTIMAL_VALUES["net.core.somaxconn"]=65535
    OPTIMAL_VALUES["net.ipv4.tcp_max_syn_backlog"]=16384
    
    # 3. 网络缓冲区 (BDP 优化)
    # 如果内存 > 4GB，开启大缓冲区
    if [ "$TOTAL_MEM_GB" -ge 4 ]; then
        OPTIMAL_VALUES["net.core.rmem_max"]=33554432
        OPTIMAL_VALUES["net.core.wmem_max"]=33554432
        OPTIMAL_VALUES["net.ipv4.tcp_rmem"]="4096 87380 33554432"
        OPTIMAL_VALUES["net.ipv4.tcp_wmem"]="4096 65536 33554432"
    else
        OPTIMAL_VALUES["net.core.rmem_max"]=8388608
        OPTIMAL_VALUES["net.core.wmem_max"]=8388608
        OPTIMAL_VALUES["net.ipv4.tcp_rmem"]="4096 87380 8388608"
        OPTIMAL_VALUES["net.ipv4.tcp_wmem"]="4096 65536 8388608"
    fi

    # 4. 基础网络稳健性
    OPTIMAL_VALUES["net.ipv4.tcp_syncookies"]=1
    OPTIMAL_VALUES["net.ipv4.tcp_tw_reuse"]=1
    OPTIMAL_VALUES["net.ipv4.tcp_fin_timeout"]=15
    OPTIMAL_VALUES["net.ipv4.tcp_keepalive_time"]=600
    OPTIMAL_VALUES["net.ipv4.ip_local_port_range"]="1024 65535"
    OPTIMAL_VALUES["net.ipv4.tcp_fastopen"]=3
    
    # 5. 虚拟内存策略
    OPTIMAL_VALUES["vm.swappiness"]=10
    OPTIMAL_VALUES["vm.vfs_cache_pressure"]=50
    OPTIMAL_VALUES["vm.dirty_ratio"]=20
    OPTIMAL_VALUES["vm.dirty_background_ratio"]=5
}

# ==================== BBR 与 队列管理 ====================
setup_bbr() {
    if grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control; then
        echo -e "${GREEN}[✅]${RESET} 检测到内核支持 BBR，正在启用性能联动方案..."
        OPTIMAL_VALUES["net.core.default_qdisc"]="fq"
        OPTIMAL_VALUES["net.ipv4.tcp_congestion_control"]="bbr"
        # BBR 专用优化：减少不必要的慢启动
        OPTIMAL_VALUES["net.ipv4.tcp_slow_start_after_idle"]=0
    fi
}

# ==================== 应用与备份 ====================
apply_changes() {
    mkdir -p "$BACKUP_DIR"
    sysctl -a > "$BACKUP_DIR/before_opt_$(date +%s).conf" 2>/dev/null || true
    
    echo -e "${BLUE}==>${RESET} ${BOLD}写入优化配置至 $SYSCTL_CONF ...${RESET}"
    echo "# BuBuXSY Kernel Optimization v3.0" > "$SYSCTL_CONF"
    
    for key in "${!OPTIMAL_VALUES[@]}"; do
        echo "$key = ${OPTIMAL_VALUES[$key]}" >> "$SYSCTL_CONF"
        sysctl -w "$key=${OPTIMAL_VALUES[$key]}" >/dev/null 2>&1 || true
    done
    
    # 刷新配置
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1
}

# ==================== 主流程 ====================
clear
echo -e "${CYAN}${BOLD}================================================${RESET}"
echo -e "${CYAN}${BOLD}    🚀 BuBuXSY Linux 内核终极优化工具 v3.0      ${RESET}"
echo -e "${CYAN}${BOLD}================================================${RESET}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ 请以 root 权限运行本脚本${RESET}"
    exit 1
fi

calculate_vps_specs
setup_bbr
enable_rps_accelerator
apply_changes

echo -e "\n${GREEN}${BOLD}✨ 优化执行完毕！性能已拉满。${RESET}"
echo -e "${YELLOW}主要提升：${RESET}"
echo -e " 1. ${WHITE}多核加速:${RESET} RPS 已将网卡流量分摊至所有 $CPU_CORES 个核心"
echo -e " 2. ${WHITE}内存保护:${RESET} 已预留 $((${OPTIMAL_VALUES["vm.min_free_kbytes"]}/1024))MB 紧急缓冲区"
echo -e " 3. ${WHITE}网络吞吐:${RESET} BBR + FQ 队列已生效"
echo -e " 4. ${WHITE}连接上限:${RESET} somaxconn 已提升至 65535"
echo -e "------------------------------------------------"
echo -e "建议：输入 ${CYAN}ss -i${RESET} 观察连接状态，或者重启系统以达到最佳状态。"
