#!/bin/bash
# ====================================================
# 🌉 Linux 内核深度优化脚本 v3.0 
# 🚀 支持: RPS/RFS 多核加速 | BBR 联动 | 动态内存预留
# By: BuBuXSY | Version: 2026.03.04
# ====================================================

set -euo pipefail

# --- 样式定义 ---
readonly RED=$'\033[1;31m'; readonly GREEN=$'\033[1;32m'; readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[1;34m'; readonly CYAN=$'\033[1;36m'; readonly BOLD=$'\033[1m'; readonly RESET=$'\033[0m'

# --- 路径配置 ---
readonly LOG_FILE="/var/log/kernel_optimization.log"
readonly BACKUP_DIR="/var/backups/kernel_optimization"
readonly SYSCTL_CONF="/etc/sysctl.d/99-performance.conf"

# --- 全局变量 ---
declare -A OPTIMAL_VALUES
CPU_CORES=$(nproc)
TOTAL_MEM=$(awk '/^MemTotal:/{print $2}' /proc/meminfo) # KB

log() { echo -e "${CYAN}[ℹ️]${RESET} $1" | tee -a "$LOG_FILE"; }
ok()  { echo -e "${GREEN}[✅]${RESET} $1" | tee -a "$LOG_FILE"; }
err() { echo -e "${RED}[❌]${RESET} $1" | tee -a "$LOG_FILE"; }

# 1. 环境预检
check_env() {
    [[ $EUID -ne 0 ]] && { err "必须以 root 权限运行"; exit 1; }
    mkdir -p "$BACKUP_DIR"
    log "正在分析 VPS 性能画像 (CPU: $CPU_CORES Cores, MEM: $((TOTAL_MEM/1024))MB)..."
}

# 2. RPS/RFS 多核网络加速 (根据核心数自动计算掩码)
enable_rps() {
    log "正在配置 RPS/RFS 多核网络加速..."
    local mask_num=$(( (1 << CPU_CORES) - 1 ))
    local mask_hex=$(printf "%x" $mask_num)
    local interfaces=$(ls /sys/class/net | grep -vE 'lo|docker|veth|br-|virbr')

    for iface in $interfaces; do
        if [ -d "/sys/class/net/$iface/queues" ]; then
            for rps_file in /sys/class/net/$iface/queues/rx-*/rps_cpus; do
                echo "$mask_hex" > "$rps_file" 2>/dev/null || true
            done
            log "网卡 $iface 已绑定至 CPU 掩码: $mask_hex"
        fi
    done
    OPTIMAL_VALUES["net.core.rps_sock_flow_entries"]=32768
}

[Image of Linux network stack RPS RFS acceleration]

# 3. 动态计算最优参数
calc_params() {
    # 内存预留: 设为内存的 0.4%, 防止大并发触发 Direct Reclaim 导致卡顿
    local min_free=$(( TOTAL_MEM * 4 / 1000 ))
    [[ $min_free -lt 16384 ]] && min_free=16384
    [[ $min_free -gt 262144 ]] && min_free=262144
    OPTIMAL_VALUES["vm.min_free_kbytes"]=$min_free

    # 基础性能参数
    OPTIMAL_VALUES["net.core.somaxconn"]=65535
    OPTIMAL_VALUES["net.ipv4.tcp_max_syn_backlog"]=16384
    OPTIMAL_VALUES["net.ipv4.tcp_tw_reuse"]=1
    OPTIMAL_VALUES["net.ipv4.tcp_fin_timeout"]=15
    OPTIMAL_VALUES["net.ipv4.ip_local_port_range"]="1024 65535"
    OPTIMAL_VALUES["vm.swappiness"]=10
    
    # BBR 联动
    if grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control; then
        OPTIMAL_VALUES["net.core.default_qdisc"]="fq"
        OPTIMAL_VALUES["net.ipv4.tcp_congestion_control"]="bbr"
        OPTIMAL_VALUES["net.ipv4.tcp_slow_start_after_idle"]=0
        ok "BBR 拥塞控制联动已就绪"
    fi
}

# 4. 执行应用
apply_all() {
    sysctl -a > "$BACKUP_DIR/backup_$(date +%s).conf" 2>/dev/null || true
    for key in "${!OPTIMAL_VALUES[@]}"; do
        echo "$key = ${OPTIMAL_VALUES[$key]}" >> "$SYSCTL_CONF"
        sysctl -w "$key=${OPTIMAL_VALUES[$key]}" >/dev/null 2>&1 || true
    done
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1
    ok "内核优化已成功应用！"
}

# --- 主流程 ---
clear
echo -e "${CYAN}${BOLD}================================================${RESET}"
echo -e "${CYAN}${BOLD}    🚀 Linux 内核深度优化工具 v3.0     ${RESET}"
echo -e "${CYAN}${BOLD}================================================${RESET}"
check_env
enable_rps
calc_params
apply_all
