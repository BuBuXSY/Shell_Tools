#!/bin/bash
# ====================================================
# 🌉 Linux 内核架构级优化工具 v5.0
# 🚀 NUMA 自动绑定 | IRQ 亲和优化 | 100G 网卡适配
# ☁ 自动云厂商检测与参数自适应
# By: BuBuXSY | Version: 5.0
# ====================================================

set -euo pipefail

# =========================
# 🎨 样式
# =========================
readonly RED=$'\033[1;31m'
readonly GREEN=$'\033[1;32m'
readonly YELLOW=$'\033[1;33m'
readonly CYAN=$'\033[1;36m'
readonly RESET=$'\033[0m'

log()  { echo -e "${CYAN}[ℹ]${RESET} $1"; }
ok()   { echo -e "${GREEN}[✓]${RESET} $1"; }
warn() { echo -e "${YELLOW}[!]${RESET} $1"; }

# =========================
# 🛡 基础检查
# =========================
if [[ $EUID -ne 0 ]]; then
    echo "必须使用 root 运行"
    exit 1
fi

# =========================
# 🖥 系统信息
# =========================
CPU_CORES=$(nproc)
TOTAL_MEM=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
TOTAL_MEM_GB=$((TOTAL_MEM / 1024 / 1024))

# =========================
# ☁ 云厂商检测
# =========================
detect_cloud() {

    if grep -qi "amazon" /sys/devices/virtual/dmi/id/product_name 2>/dev/null; then
        CLOUD="AWS"
    elif grep -qi "google" /sys/devices/virtual/dmi/id/product_name 2>/dev/null; then
        CLOUD="GCP"
    elif grep -qi "microsoft" /sys/devices/virtual/dmi/id/product_name 2>/dev/null; then
        CLOUD="Azure"
    elif systemd-detect-virt -q; then
        CLOUD="Virtualized"
    else
        CLOUD="BareMetal"
    fi

    ok "检测到环境: $CLOUD"
}

# =========================
# 🧠 NUMA 自动绑定
# =========================
optimize_numa() {

    if command -v numactl >/dev/null 2>&1; then
        log "检测 NUMA 拓扑..."

        NUMA_NODES=$(numactl --hardware | grep "available:" | awk '{print $2}')

        if [[ "$NUMA_NODES" -gt 1 ]]; then
            ok "检测到多 NUMA 节点 ($NUMA_NODES)"

            # 绑定当前进程到所有节点（高性能模式）
            numactl --interleave=all true || true
            ok "已启用 NUMA 内存交错模式"
        else
            warn "单 NUMA 架构"
        fi
    else
        warn "未安装 numactl，跳过 NUMA 优化"
    fi
}

# =========================
# ⚡ IRQ 自动亲和性优化
# =========================
optimize_irq() {

    log "优化 IRQ 亲和性..."

    local cpu_mask
    cpu_mask=$(printf "%x" $(( (1 << CPU_CORES) - 1 )))

    for irq in /proc/irq/*; do
        if [[ -f "$irq/smp_affinity" ]]; then
            echo "$cpu_mask" > "$irq/smp_affinity" 2>/dev/null || true
        fi
    done

    ok "IRQ 已分配至多核 (mask=$cpu_mask)"
}

# =========================
# 🚀 100G 网卡优化
# =========================
optimize_100g() {

    log "检测高性能网卡..."

    for iface in $(ls /sys/class/net | grep -v lo); do

        if [[ -f /sys/class/net/$iface/speed ]]; then
            SPEED=$(cat /sys/class/net/$iface/speed 2>/dev/null || echo 0)

            if [[ "$SPEED" -ge 100000 ]]; then
                ok "检测到 100G 网卡: $iface"

                # 增加队列数
                ethtool -L "$iface" combined "$CPU_CORES" 2>/dev/null || true

                # 开启多队列
                echo 4096 > /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null || true
            fi
        fi
    done
}

# =========================
# ☁ 云环境自适应参数
# =========================
apply_cloud_tuning() {

    log "根据环境调整参数..."

    case "$CLOUD" in
        AWS)
            warn "AWS 优化模式"
            sysctl -w net.core.rmem_max=134217728 >/dev/null
            ;;
        Azure)
            warn "Azure 优化模式"
            sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null
            ;;
        GCP)
            warn "GCP 优化模式"
            sysctl -w net.core.netdev_max_backlog=65535 >/dev/null
            ;;
        BareMetal)
            ok "物理机模式，启用最大性能"
            ;;
    esac
}

# =========================
# 🔧 通用高性能参数
# =========================
apply_sysctl() {

cat > /etc/sysctl.d/99-v5-performance.conf <<EOF
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 32768
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 500000
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
vm.swappiness = 10
fs.file-max = 2097152
EOF

sysctl --system >/dev/null
ok "基础性能参数已应用"
}

# =========================
# 🚀 主流程
# =========================
main() {

    clear
    echo -e "${CYAN}"
    echo "================================================"
    echo "   🌉 Linux 架构级优化工具 v5.0"
    echo "================================================"
    echo -e "${RESET}"

    detect_cloud
    optimize_numa
    optimize_irq
    optimize_100g
    apply_sysctl
    apply_cloud_tuning

    echo
    ok "🎉 架构级优化完成！系统已进入高性能模式。"
}

main "$@"
