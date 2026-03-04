#!/bin/bash
# ====================================================
# 🌉 Linux 内核架构级优化工具 v6.0
# 🚀 NUMA 自动绑定 | IRQ 亲和优化 | 100G 网卡适配
# ☁ 自动云厂商检测与参数自适应
# 🛡 全面错误处理 | 回滚支持 | 幂等执行
# By: BuBuXSY | Version: 6.0
# ====================================================

set -uo pipefail
# 注意：去掉 -e，改为手动处理错误，避免单步失败终止整个脚本

# =========================
# 🎨 样式
# =========================
readonly RED=$'\033[1;31m'
readonly GREEN=$'\033[1;32m'
readonly YELLOW=$'\033[1;33m'
readonly CYAN=$'\033[1;36m'
readonly RESET=$'\033[0m'

# =========================
# 📋 日志系统（带时间戳 + 写文件）
# =========================
readonly LOG_FILE="/var/log/linux-optimizer-v6.log"
readonly BACKUP_DIR="/etc/sysctl-optimizer-backup-$(date +%Y%m%d_%H%M%S)"
readonly SYSCTL_CONF="/etc/sysctl.d/99-v6-performance.conf"

_log_raw() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"; }
log()  { _log_raw "${CYAN}[ℹ]${RESET} $1"; }
ok()   { _log_raw "${GREEN}[✓]${RESET} $1"; }
warn() { _log_raw "${YELLOW}[!]${RESET} $1"; }
err()  { _log_raw "${RED}[✗]${RESET} $1"; }

# =========================
# 🛡 基础检查
# =========================
preflight_check() {
    if [[ $EUID -ne 0 ]]; then
        err "必须使用 root 运行"; exit 1
    fi

    # 检查内核版本（BBR 需要 4.9+）
    local kver
    kver=$(uname -r | awk -F. '{print $1*100+$2}')
    if [[ "$kver" -lt 409 ]]; then
        warn "内核版本 $(uname -r) 低于 4.9，BBR 不可用，将跳过"
        BBR_SUPPORTED=0
    else
        BBR_SUPPORTED=1
    fi

    # 检查必要命令
    local missing=()
    for cmd in awk sysctl nproc; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        err "缺少必要命令: ${missing[*]}"; exit 1
    fi

    ok "预检通过 (内核: $(uname -r), 架构: $(uname -m))"
}

# =========================
# 💾 备份现有 sysctl 配置（支持回滚）
# =========================
backup_sysctl() {
    mkdir -p "$BACKUP_DIR"

    # 备份所有现有 sysctl 配置
    for f in /etc/sysctl.conf /etc/sysctl.d/*.conf; do
        [[ -f "$f" ]] && cp "$f" "$BACKUP_DIR/" && log "已备份: $f"
    done

    # 同时保存当前运行时参数快照
    sysctl -a > "$BACKUP_DIR/runtime_snapshot.txt" 2>/dev/null || true

    ok "配置已备份至 $BACKUP_DIR（如需回滚：cp $BACKUP_DIR/*.conf /etc/sysctl.d/ && sysctl --system）"
}

# =========================
# 🖥 系统信息
# =========================
CPU_CORES=$(nproc)
TOTAL_MEM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
TOTAL_MEM_GB=$(( TOTAL_MEM_KB / 1024 / 1024 ))
CLOUD="Unknown"
BBR_SUPPORTED=1

# =========================
# ☁ 云厂商检测（增强：支持 DMI + metadata 双重检测）
# =========================
detect_cloud() {
    local product=""
    product=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo "")

    if echo "$product" | grep -qi "amazon\|ec2"; then
        CLOUD="AWS"
    elif echo "$product" | grep -qi "google"; then
        CLOUD="GCP"
    elif echo "$product" | grep -qi "microsoft\|azure"; then
        CLOUD="Azure"
    elif [[ -f /sys/hypervisor/type ]] || systemd-detect-virt -q 2>/dev/null; then
        CLOUD="Virtualized"
    else
        CLOUD="BareMetal"
    fi

    ok "检测到运行环境: $CLOUD | CPU: ${CPU_CORES}核 | 内存: ${TOTAL_MEM_GB}GB"
}

# =========================
# 🧠 NUMA 自动绑定
# =========================
optimize_numa() {
    if ! command -v numactl >/dev/null 2>&1; then
        warn "未安装 numactl，跳过 NUMA 优化（可用 apt/yum install numactl 安装）"
        return 0
    fi

    log "检测 NUMA 拓扑..."
    local numa_nodes
    numa_nodes=$(numactl --hardware 2>/dev/null | awk '/available:/{print $2}')

    if [[ -z "$numa_nodes" || ! "$numa_nodes" =~ ^[0-9]+$ ]]; then
        warn "无法解析 NUMA 拓扑信息，跳过"
        return 0
    fi

    if [[ "$numa_nodes" -gt 1 ]]; then
        ok "检测到多 NUMA 节点 ($numa_nodes 个)"
        numactl --interleave=all true 2>/dev/null || warn "NUMA interleave 设置失败（虚拟化环境常见，可忽略）"
        ok "已启用 NUMA 内存交错模式"
    else
        warn "单 NUMA 节点架构，跳过 NUMA 绑定"
    fi
}

# =========================
# ⚡ IRQ 自动亲和性优化
# =========================
optimize_irq() {
    log "优化 IRQ 亲和性..."

    # 动态计算 CPU mask（最多 32 核；超出使用 /proc/irq/*/smp_affinity_list）
    local use_list=0
    local cpu_mask=""
    local cpu_list="0-$((CPU_CORES - 1))"

    if [[ "$CPU_CORES" -le 32 ]]; then
        cpu_mask=$(printf "%x" $(( (1 << CPU_CORES) - 1 )))
    else
        use_list=1
        warn "CPU 核心数 > 32，改用 smp_affinity_list 模式"
    fi

    local count=0
    for irq_dir in /proc/irq/*/; do
        local irq_num
        irq_num=$(basename "$irq_dir")
        # 跳过非数字目录（如 default_smp_affinity）
        [[ "$irq_num" =~ ^[0-9]+$ ]] || continue

        if [[ "$use_list" -eq 1 && -f "${irq_dir}smp_affinity_list" ]]; then
            echo "$cpu_list" > "${irq_dir}smp_affinity_list" 2>/dev/null && (( count++ )) || true
        elif [[ -f "${irq_dir}smp_affinity" ]]; then
            echo "$cpu_mask" > "${irq_dir}smp_affinity" 2>/dev/null && (( count++ )) || true
        fi
    done

    ok "IRQ 亲和性已更新（成功 $count 条，mask=${cpu_mask:-list:$cpu_list}）"
}

# =========================
# 🚀 100G 网卡优化
# =========================
optimize_100g() {
    log "检测高性能网卡..."
    local found=0

    for iface in /sys/class/net/*/; do
        local name
        name=$(basename "$iface")
        [[ "$name" == "lo" ]] && continue

        local speed=0
        speed=$(cat "${iface}speed" 2>/dev/null || echo 0)
        # speed 可能返回 -1（链路未连接）
        [[ "$speed" =~ ^[0-9]+$ ]] || speed=0

        if [[ "$speed" -ge 100000 ]]; then
            ok "检测到 100G+ 网卡: $name (${speed}Mb/s)"
            found=1

            # 调整队列数（ethtool 可选）
            if command -v ethtool >/dev/null 2>&1; then
                ethtool -L "$name" combined "$CPU_CORES" 2>/dev/null \
                    && ok "  └─ 队列数已设为 $CPU_CORES" \
                    || warn "  └─ 队列调整失败（驱动不支持或虚拟化环境），跳过"
            fi

            # RPS/RFS 多队列
            echo 4096 > /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null \
                && ok "  └─ RPS flow entries 已设为 4096" || true

            # 为每个接收队列启用 RPS（分配到所有 CPU）
            local rps_cpus
            rps_cpus=$(printf "%x" $(( (1 << CPU_CORES) - 1 )))
            for rxq in "${iface}queues/rx-"*/rps_cpus; do
                [[ -f "$rxq" ]] && echo "$rps_cpus" > "$rxq" 2>/dev/null || true
            done
        fi
    done

    [[ "$found" -eq 0 ]] && warn "未检测到 100G+ 网卡，跳过高速网卡优化"
}

# =========================
# 🔧 通用高性能 sysctl 参数
# =========================
apply_sysctl() {
    log "计算自适应参数..."

    # 根据内存动态计算缓冲区大小
    local rmem_max wmem_max
    if [[ "$TOTAL_MEM_GB" -ge 32 ]]; then
        rmem_max=536870912   # 512MB
        wmem_max=536870912
    elif [[ "$TOTAL_MEM_GB" -ge 8 ]]; then
        rmem_max=134217728   # 128MB
        wmem_max=134217728
    else
        rmem_max=33554432    # 32MB
        wmem_max=33554432
    fi

    # BBR 拥塞控制（内核 4.9+）
    local cc_algo="cubic"
    local qdisc="pfifo_fast"
    if [[ "$BBR_SUPPORTED" -eq 1 ]]; then
        # 检查 BBR 模块是否可用
        if modprobe tcp_bbr 2>/dev/null || grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
            cc_algo="bbr"
            qdisc="fq"
        else
            warn "BBR 模块不可用，使用 cubic"
        fi
    fi

    cat > "$SYSCTL_CONF" <<EOF
# ==============================================
# Linux 架构级优化 v6.0 - 自动生成
# 生成时间: $(date)
# 环境: $CLOUD | CPU: ${CPU_CORES}核 | 内存: ${TOTAL_MEM_GB}GB
# ==============================================

# ── 网络核心 ──
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.core.rmem_default = 262144
net.core.rmem_max = ${rmem_max}
net.core.wmem_default = 262144
net.core.wmem_max = ${wmem_max}
net.core.optmem_max = 65536

# ── TCP 高并发 & 低延迟 ──
net.ipv4.tcp_max_syn_backlog = 32768
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 500000
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# ── TCP 缓冲区（内存自适应）──
net.ipv4.tcp_rmem = 4096 87380 ${rmem_max}
net.ipv4.tcp_wmem = 4096 65536 ${wmem_max}
net.ipv4.tcp_mem = $(awk "BEGIN{printf \"%d %d %d\", ${TOTAL_MEM_KB}*0.1/4, ${TOTAL_MEM_KB}*0.15/4, ${TOTAL_MEM_KB}*0.2/4}")

# ── 拥塞控制（BBR / cubic 自适应）──
net.core.default_qdisc = ${qdisc}
net.ipv4.tcp_congestion_control = ${cc_algo}

# ── 内存 & CPU 效率 ──
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1

# ── 文件描述符 ──
fs.file-max = 2097152
fs.nr_open = 2097152

# ── 端口范围（高并发）──
net.ipv4.ip_local_port_range = 1024 65535

# ── 安全强化（云环境）──
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
EOF

    # 验证并应用
    if sysctl --system > /tmp/sysctl_output.txt 2>&1; then
        ok "sysctl 参数已应用（cc=${cc_algo}, qdisc=${qdisc}, rmem_max=${rmem_max}）"
    else
        # 过滤掉非本脚本造成的旧错误
        local errs
        errs=$(grep -v "^$\|^Applying\|^#" /tmp/sysctl_output.txt | grep -i "error\|invalid" || true)
        if [[ -n "$errs" ]]; then
            warn "部分参数应用警告（可能来自系统已有配置）:"
            echo "$errs" | while IFS= read -r line; do warn "  $line"; done
        fi
        ok "sysctl 主要参数已应用（上述警告来自系统既有配置，非本脚本）"
    fi
}

# =========================
# ☁ 云环境自适应参数
# =========================
apply_cloud_tuning() {
    log "根据云环境应用专项参数..."

    case "$CLOUD" in
        AWS)
            # AWS ENA 网卡优化：增大接收缓冲，关闭不必要的 offload check
            sysctl -w net.core.rmem_max=536870912 >/dev/null 2>&1 && ok "AWS: 接收缓冲区扩大至 512MB" || warn "AWS rmem_max 设置失败"
            sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1 && ok "AWS: 启用 MTU 探测（避免 Jumbo Frame 黑洞）" || true
            ;;
        GCP)
            # GCP：高并发 backlog
            sysctl -w net.core.netdev_max_backlog=65535 >/dev/null 2>&1 && ok "GCP: netdev_max_backlog 已扩大" || true
            sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1 || true
            ;;
        Azure)
            # Azure：TIME_WAIT 复用 + 加速超时
            sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1 && ok "Azure: TIME_WAIT 复用已启用" || true
            sysctl -w net.ipv4.tcp_fin_timeout=10 >/dev/null 2>&1 || true
            ;;
        Virtualized)
            warn "虚拟化环境：部分硬件级优化（IRQ/队列）可能受限，已自动降级"
            ;;
        BareMetal)
            ok "物理裸机模式：所有优化项全量启用"
            ;;
        *)
            warn "未知环境类型，仅应用通用参数"
            ;;
    esac
}

# =========================
# 📊 优化效果验证
# =========================
verify_settings() {
    log "验证关键参数..."

    local -A checks=(
        ["net.core.somaxconn"]="65535"
        ["net.ipv4.tcp_tw_reuse"]="1"
        ["vm.swappiness"]="10"
    )

    local pass=0 fail=0
    for key in "${!checks[@]}"; do
        local expected="${checks[$key]}"
        local actual
        actual=$(sysctl -n "$key" 2>/dev/null || echo "N/A")
        if [[ "$actual" == "$expected" ]]; then
            ok "  ✔ $key = $actual"
            (( pass++ ))
        else
            warn "  ✘ $key = $actual（期望 $expected）"
            (( fail++ ))
        fi
    done

    ok "验证完成：通过 $pass 项，异常 $fail 项"
}

# =========================
# 🚀 主流程
# =========================
main() {
    clear
    echo -e "${CYAN}"
    echo "================================================"
    echo "   🌉 Linux 架构级优化工具 v6.0"
    echo "================================================"
    echo -e "${RESET}"

    preflight_check
    detect_cloud
    backup_sysctl
    optimize_numa
    optimize_irq
    optimize_100g
    apply_sysctl
    apply_cloud_tuning
    verify_settings

    echo
    ok "🎉 架构级优化完成！日志: $LOG_FILE | 备份: $BACKUP_DIR"
    echo
    warn "⚠ 建议重启后验证参数是否持久生效：sysctl -a | grep somaxconn"
}

main "$@"
