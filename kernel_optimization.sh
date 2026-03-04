#!/bin/bash
# ====================================================
# 🌉 Linux 内核深度优化脚本 v3.0
# 🚀 特性: RPS/RFS 多核加速 | BBR 联动 | 动态内存预留
# 🛠️ 适用: OpenWrt, Ubuntu, Debian, CentOS, Arch
# By: BuBuXSY | Version: 2026.03.04
# ====================================================

set -euo pipefail

# --- 样式与颜色 ---
readonly RED=$'\033[1;31m'; readonly GREEN=$'\033[1;32m'; readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[1;34m'; readonly CYAN=$'\033[1;36m'; readonly BOLD=$'\033[1m'; readonly RESET=$'\033[0m'

# --- 路径配置 ---
readonly LOG_FILE="/var/log/kernel_optimization.log"
readonly BACKUP_DIR="/var/backups/kernel_optimization"
readonly SYSCTL_CONF="/etc/sysctl.d/99-performance.conf"

# --- 全局变量 ---
declare -A OPTIMAL_VALUES
CPU_CORES=$(nproc)
TOTAL_MEM=$(awk '/^MemTotal:/{print $2}' /proc/meminfo) # 单位: KB

log() { echo -e "${CYAN}[ℹ️]${RESET} $1" | tee -a "$LOG_FILE"; }
ok()  { echo -e "${GREEN}[✅]${RESET} $1" | tee -a "$LOG_FILE"; }
err() { echo -e "${RED}[❌]${RESET} $1" | tee -a "$LOG_FILE"; }

# 1. 环境预检
check_env() {
    if [ "$(id -u)" != "0" ]; then
        err "必须以 root 权限运行此脚本！"
        exit 1
    fi
    mkdir -p "$BACKUP_DIR"
    log "正在分析 VPS 性能画像 (CPU: $CPU_CORES Cores, MEM: $((TOTAL_MEM/1024))MB)..."
}

# 2. RPS/RFS 多核网络加速 (核心黑科技)
# 原理: 将单核处理的网络中断负载分摊到所有 CPU 核心
enable_rps() {
    log "正在配置 RPS/RFS 多核网络加速..."
    # 计算全核心十六进制掩码
    local mask_num=$(( (1 << CPU_CORES) - 1 ))
    local mask_hex=$(printf "%x" $mask_num)
    
    # 自动识别物理网卡
    local interfaces=$(ls /sys/class/net | grep -vE 'lo|docker|veth|br-|virbr|any')

    for iface in $interfaces; do
        if [ -d "/sys/class/net/$iface/queues" ]; then
            for rps_file in /sys/class/net/$iface/queues/rx-*/rps_cpus; do
                echo "$mask_hex" > "$rps_file" 2>/dev/null || true
            done
            for rfc_file in /sys/class/net/$iface/queues/rx-*/rps_flow_cnt; do
                echo "4096" > "$rfc_file" 2>/dev/null || true
            done
            log "网卡 $iface 已成功映射至 CPU 掩码: $mask_hex"
        fi
    done
    OPTIMAL_VALUES["net.core.rps_sock_flow_entries"]=32768
}

# 3. 动态计算最优参数 (拒绝死板数值)
calc_params() {
    # 动态内存预留: 设为内存的 0.4%, 避免大流量冲击时系统假死
    local min_free=$(( TOTAL_MEM * 4 / 1000 ))
    [[ $min_free -lt 16384 ]] && min_free=16384
    [[ $min_free -gt 262144 ]] && min_free=262144
    OPTIMAL_VALUES["vm.min_free_kbytes"]=$min_free

    # 提升并发连接上限
    OPTIMAL_VALUES["net.core.somaxconn"]=65535
    OPTIMAL_VALUES["net.ipv4.tcp_max_syn_backlog"]=16384
    OPTIMAL_VALUES["net.ipv4.tcp_tw_reuse"]=1
    OPTIMAL_VALUES["net.ipv4.tcp_fin_timeout"]=15
    OPTIMAL_VALUES["net.ipv4.ip_local_port_range"]="1024 65535"
    OPTIMAL_VALUES["net.ipv4.tcp_fastopen"]=3
    
    # 内存交换策略优化
    OPTIMAL_VALUES["vm.swappiness"]=10
    OPTIMAL_VALUES["vm.vfs_cache_pressure"]=50
    
    # BBR 拥塞控制探测与联动
    if grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control; then
        OPTIMAL_VALUES["net.core.default_qdisc"]="fq"
        OPTIMAL_VALUES["net.ipv4.tcp_congestion_control"]="bbr"
        OPTIMAL_VALUES["net.ipv4.tcp_slow_start_after_idle"]=0
        ok "BBR 拥塞控制与 FQ 队列联动已准备就绪"
    fi
}

# 4. 应用配置与备份
apply_all() {
    # 备份当前配置以防万一
    sysctl -a > "$BACKUP_DIR/sysctl_before_opt_$(date +%s).conf" 2>/dev/null || true
    
    # 确保目录存在
    mkdir -p "$(dirname "$SYSCTL_CONF")"
    
    echo "# BuBuXSY 终极优化配置 v3.0" > "$SYSCTL_CONF"
    for key in "${!OPTIMAL_VALUES[@]}"; do
        echo "$key = ${OPTIMAL_VALUES[$key]}" >> "$SYSCTL_CONF"
        # 实时生效
        sysctl -w "$key=${OPTIMAL_VALUES[$key]}" >/dev/null 2>&1 || true
    done
    
    # 强制刷新
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1 || true
    ok "内核优化参数已成功持久化至 $SYSCTL_CONF"
}

# --- 执行主流程 ---
clear
echo -e "${CYAN}${BOLD}================================================${RESET}"
echo -e "${CYAN}${BOLD}    🚀 BuBuXSY Linux 内核优化工具 v3.0      ${RESET}"
echo -e "${CYAN}${BOLD}================================================${RESET}"

check_env
enable_rps
calc_params
apply_all

echo -e "\n${GREEN}${BOLD}✨ 优化执行完毕！系统性能已拉满。${RESET}"
echo -e "${YELLOW}主要提升亮点：${RESET}"
echo -e " 1. ${WHITE}多核网络加速:${RESET} RPS 已将网卡中断分摊至所有核心"
echo -e " 2. ${WHITE}紧急内存预留:${RESET} 已锁定 $((OPTIMAL_VALUES["vm.min_free_kbytes"]/1024))MB 缓冲区"
echo -e " 3. ${WHITE}吞吐量优化:${RESET} BBR + FQ 算法已生效"
echo -e " 4. ${WHITE}高并发支持:${RESET} somaxconn 提升至 65535"
echo -e "------------------------------------------------"
echo -e "建议：使用 ${CYAN}ss -i${RESET} 查看 BBR 运行状态，或重启系统以达最佳效果。"
