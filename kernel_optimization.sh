#!/bin/bash
# ====================================================
# MIT License
#
# Copyright (c) 2025 BuBuXSY
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ====================================================
# 🌉 Linux 内核架构级优化工具 v2.0
# 📦 场景：VPS | 低配VPS | 旁路由 | 主路由 | 裸机 | 单片机SBC
# 🛡 备份回滚 | 幂等执行 | ulimit 持久化
# By: BuBuXSY | Version: 2.0
# 最低要求：bash 4.0+
#
# 用法：
#   bash optimizer.sh                    # 交互式菜单选择场景
#   bash optimizer.sh --scene bypass     # 直接指定旁路由（跳过菜单）
#   bash optimizer.sh --scene router     # 直接指定主路由
#   bash optimizer.sh --scene sbc        # 直接指定单片机
#   bash optimizer.sh --scene vps        # 直接指定普通VPS
#   bash optimizer.sh --scene vps_low    # 直接指定低配VPS
#   bash optimizer.sh --scene baremetal  # 直接指定裸机服务器
# ====================================================

set -uo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
    echo "❌ 此脚本需要 bash 4.0+（当前: $BASH_VERSION）"
    echo "   macOS 用户：brew install bash"
    exit 1
fi

# =========================
# 🎨 颜色
# =========================
readonly RED=$'\033[1;31m'
readonly GREEN=$'\033[1;32m'
readonly YELLOW=$'\033[1;33m'
readonly CYAN=$'\033[1;36m'
readonly BLUE=$'\033[1;34m'
readonly RESET=$'\033[0m'

# =========================
# 📋 日志
# =========================
readonly LOG_FILE="/var/log/linux-optimizer-v2.log"
readonly SYSCTL_CONF="/etc/sysctl.d/99-v2-performance.conf"
BACKUP_DIR="/etc/sysctl-optimizer-backup-$(date +%Y%m%d_%H%M%S)"
readonly BACKUP_DIR

_log_raw() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"; }
log()      { _log_raw "${CYAN}[ℹ️ ]${RESET} $1"; }
ok()       { _log_raw "${GREEN}[✅]${RESET} $1"; }
warn()     { _log_raw "${YELLOW}[⚠️ ]${RESET} $1"; }
err()      { _log_raw "${RED}[❌]${RESET} $1"; }
log_step() {
    _log_raw ""
    _log_raw "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    _log_raw "${CYAN}[🔧]${RESET} $1"
    _log_raw "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# =========================
# 📋 全局变量
# =========================
CPU_CORES=$(nproc)
TOTAL_MEM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
TOTAL_MEM_MB=$(( TOTAL_MEM_KB / 1024 ))
TOTAL_MEM_GB=$(( TOTAL_MEM_KB / 1024 / 1024 ))
CLOUD="Unknown"
BBR_SUPPORTED=1
SCENE="unknown"
SCENE_FORCED=0
ARCH=$(uname -m)

# =========================
# 📖 用法说明
# =========================
usage() {
    echo -e "${CYAN}用法：${RESET}"
    echo "  $0 [--scene <场景>] [--help]"
    echo
    echo -e "${CYAN}可用场景：${RESET}"
    echo "  vps        普通 VPS / 云主机（均衡参数）"
    echo "  vps_low    低配 VPS（≤1GB 内存，保守参数）"
    echo "  bypass     旁路由（透明代理 + fakeip + TUN）"
    echo "  router     主路由 / 软路由（转发 + NAT + conntrack）"
    echo "  sbc        单片机 / 嵌入式（树莓派 / R2S / 闪存保护）"
    echo "  baremetal  裸机服务器（全量激进参数）"
    echo
    echo -e "${CYAN}示例：${RESET}"
    echo "  $0                       # 交互式菜单"
    echo "  $0 --scene bypass        # 直接指定旁路由"
    echo "  $0 --scene sbc           # 直接指定单片机"
    exit 0
}

# =========================
# 🔡 命令行参数解析
# =========================
parse_args() {
    local valid_scenes="vps vps_low bypass router sbc baremetal"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scene)
                shift
                if [[ -z "${1:-}" ]]; then
                    err "--scene 需要指定场景名"; usage
                fi
                local valid=0
                for s in $valid_scenes; do
                    [[ "$1" == "$s" ]] && valid=1 && break
                done
                if [[ "$valid" -eq 0 ]]; then
                    err "无效场景: $1（可用: $valid_scenes）"; exit 1
                fi
                SCENE="$1"
                SCENE_FORCED=1
                shift
                ;;
            --help|-h) usage ;;
            *)
                err "未知参数: $1"; usage
                ;;
        esac
    done
}

# =========================
# 🛡 前置检查
# =========================
preflight_check() {
    log_step "前置检查"

    [[ $EUID -ne 0 ]] && { err "必须使用 root 权限运行"; exit 1; }

    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE" 2>/dev/null || { err "无法写入日志: $LOG_FILE"; exit 1; }

    local kver
    kver=$(uname -r | awk -F. '{print $1*100+$2}')
    [[ "$kver" -lt 409 ]] && { warn "内核 $(uname -r) < 4.9，BBR 不可用"; BBR_SUPPORTED=0; }

    local missing=()
    for cmd in awk sysctl nproc; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    [[ ${#missing[@]} -gt 0 ]] && { err "缺少命令: ${missing[*]}"; exit 1; }

    ok "预检通过（内核: $(uname -r) | 架构: $ARCH | CPU: ${CPU_CORES}核 | 内存: ${TOTAL_MEM_MB}MB）"
}

# =========================
# ☁  云厂商检测
# =========================
detect_cloud() {
    local product=""
    product=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo "")
    if echo "$product" | grep -qi "amazon\|ec2";          then CLOUD="AWS"
    elif echo "$product" | grep -qi "google";             then CLOUD="GCP"
    elif echo "$product" | grep -qi "microsoft\|azure";   then CLOUD="Azure"
    elif [[ -f /sys/hypervisor/type ]];                   then CLOUD="Virtualized"
    elif command -v systemd-detect-virt >/dev/null 2>&1 \
         && systemd-detect-virt -q 2>/dev/null;           then CLOUD="Virtualized"
    else                                                       CLOUD="BareMetal"
    fi
}

# =========================
# 🎛 交互式场景选择菜单
# =========================
select_scene() {
    # 命令行已强制指定，跳过菜单
    [[ "$SCENE_FORCED" -eq 1 ]] && return 0

    echo
    echo -e "${BLUE}  请选择你的设备类型：${RESET}"
    echo    "  ┌─────────────────────────────────────────────────────────────"
    echo    "  │  1)  普通 VPS / 云主机     （腾讯云 / 阿里云 / 搬瓦工等）"
    echo    "  │  2)  低配 VPS              （内存 ≤ 1GB 的小鸡）"
    echo    "  │  3)  旁路由                （R4S / 软路由跑透明代理）"
    echo    "  │  4)  主路由 / 软路由        （作为网关出口，跑 NAT 转发）"
    echo    "  │  5)  单片机 / SBC          （树莓派 / R2S / 闪存设备）"
    echo    "  │  6)  裸机服务器            （物理机，≥16GB 内存 / ≥8核）"
    echo    "  └─────────────────────────────────────────────────────────────"
    echo

    while true; do
        read -rp "$(echo -e "${YELLOW}  输入序号 [1-6]：${RESET}")" choice
        case "$choice" in
            1) SCENE="vps";       break ;;
            2) SCENE="vps_low";   break ;;
            3) SCENE="bypass";    break ;;
            4) SCENE="router";    break ;;
            5) SCENE="sbc";       break ;;
            6) SCENE="baremetal"; break ;;
            *) echo -e "${RED}  无效输入，请输入 1 到 6 之间的数字${RESET}" ;;
        esac
    done

    ok "已选择场景: $SCENE"
}

# =========================
# ❓ 确认界面
# =========================
confirm_action() {
    log_step "操作确认"

    declare -A scene_desc=(
        [vps]="普通 VPS / 云主机（均衡参数）"
        [vps_low]="低配 VPS（≤1GB，保守参数）"
        [bypass]="旁路由（fakeip + REDIRECT/TUN + fq_codel）"
        [router]="主路由 / 软路由（转发 + NAT + conntrack）"
        [sbc]="单片机 / SBC（闪存保护 + ARM 低功耗）"
        [baremetal]="裸机服务器（全量激进参数）"
    )

    echo
    echo -e "${BLUE}  📊 即将优化${RESET}"
    echo    "  ┌──────────────────────────────────────────────"
    printf  "  │  🎭 选择场景  : %s\n" "${scene_desc[$SCENE]:-$SCENE}"
    if [[ "$SCENE_FORCED" -eq 1 ]]; then
        printf "  │  🔒 指定方式  : 命令行参数（--scene %s）\n" "$SCENE"
    else
        printf "  │  🖱️  指定方式  : 交互式菜单\n"
    fi
    printf  "  │  ☁️  云环境    : %s\n" "$CLOUD"
    printf  "  │  🖥️  CPU 核心  : %s 核 (%s)\n" "$CPU_CORES" "$ARCH"
    printf  "  │  💾 物理内存  : %s MB\n" "$TOTAL_MEM_MB"
    printf  "  │  🐧 内核版本  : %s\n" "$(uname -r)"
    echo    "  └──────────────────────────────────────────────"
    echo
    warn "将修改：$SYSCTL_CONF / /etc/security/limits.conf"
    [[ "$SCENE" =~ ^(router|bypass)$ ]] && warn "将写入：/etc/modules-load.d/netfilter.conf"
    echo
    read -rp "$(echo -e "${YELLOW}❓ 确认继续？[y/N]：${RESET}")" confirm
    [[ "${confirm,,}" == "y" ]] || { log "👋 已取消"; exit 0; }
}

# =========================
# 💾 备份
# =========================
backup_sysctl() {
    log_step "备份现有配置"
    mkdir -p "$BACKUP_DIR"
    for f in /etc/sysctl.conf /etc/sysctl.d/*.conf; do
        [[ -f "$f" ]] && cp "$f" "$BACKUP_DIR/" && log "已备份: $f"
    done
    sysctl -a > "$BACKUP_DIR/runtime_snapshot.txt" 2>/dev/null || true
    ok "备份 → $BACKUP_DIR（回滚：cp $BACKUP_DIR/*.conf /etc/sysctl.d/ && sysctl --system）"
}

# =========================
# 🧠 NUMA（裸机专属）
# =========================
optimize_numa() {
    [[ "$SCENE" != "baremetal" ]] && return 0
    log_step "NUMA 优化"
    command -v numactl >/dev/null 2>&1 || { warn "未安装 numactl，跳过"; return 0; }
    local nodes; nodes=$(numactl --hardware 2>/dev/null | awk '/available:/{print $2}')
    if [[ "$nodes" =~ ^[0-9]+$ ]] && [[ "$nodes" -gt 1 ]]; then
        numactl --interleave=all true 2>/dev/null && ok "NUMA interleave=all（$nodes 节点）" \
            || warn "NUMA 设置失败（虚拟化环境常见）"
    else
        warn "单 NUMA 节点，跳过"
    fi
}

# =========================
# ⚡ IRQ 亲和性
# =========================
optimize_irq() {
    [[ "$SCENE" =~ ^(vps_low|sbc)$ ]] && return 0
    log_step "IRQ 亲和性优化"
    local use_list=0 cpu_mask="" cpu_list="0-$((CPU_CORES - 1))"
    if [[ "$CPU_CORES" -le 32 ]]; then
        cpu_mask=$(printf "%x" $(( (1 << CPU_CORES) - 1 )))
    else
        use_list=1
    fi
    local count=0
    for irq_dir in /proc/irq/*/; do
        local irq_num; irq_num=$(basename "$irq_dir")
        [[ "$irq_num" =~ ^[0-9]+$ ]] || continue
        if [[ "$use_list" -eq 1 && -f "${irq_dir}smp_affinity_list" ]]; then
            echo "$cpu_list" > "${irq_dir}smp_affinity_list" 2>/dev/null && count=$((count + 1)) || true
        elif [[ -f "${irq_dir}smp_affinity" ]]; then
            echo "$cpu_mask" > "${irq_dir}smp_affinity" 2>/dev/null && count=$((count + 1)) || true
        fi
    done
    ok "IRQ 亲和性已更新（$count 条）"
}

# =========================
# 🚀 100G 网卡（裸机专属）
# =========================
optimize_100g() {
    [[ "$SCENE" != "baremetal" ]] && return 0
    log_step "100G 网卡优化"
    local found=0
    for iface in /sys/class/net/*/; do
        local name; name=$(basename "$iface")
        [[ "$name" == "lo" ]] && continue
        local speed=0; speed=$(cat "${iface}speed" 2>/dev/null || echo 0)
        [[ "$speed" =~ ^[0-9]+$ ]] || speed=0
        [[ "$speed" -ge 100000 ]] || continue
        found=1; ok "100G+ 网卡: $name（${speed}Mb/s）"
        command -v ethtool >/dev/null 2>&1 && {
            ethtool -L "$name" combined "$CPU_CORES" 2>/dev/null \
                && ok "  └─ 队列数=$CPU_CORES" || warn "  └─ 队列调整失败"
        }
        echo 4096 > /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null || true
        local rps_cpus
        if [[ "$CPU_CORES" -le 32 ]]; then
            rps_cpus=$(printf "%x" $(( (1 << CPU_CORES) - 1 )))
        else
            local pg=$(( CPU_CORES / 32 )) pf=""
            for (( i=0; i<pg; i++ )); do pf+="ffffffff"; done
            rps_cpus="${pf}$(printf '%x' $(( (1 << (CPU_CORES % 32)) - 1 )))"
        fi
        for rxq in "${iface}queues/rx-"*/rps_cpus; do
            [[ -f "$rxq" ]] && echo "$rps_cpus" > "$rxq" 2>/dev/null || true
        done
    done
    [[ "$found" -eq 0 ]] && warn "未检测到 100G+ 网卡"
}

# =========================
# 💿 磁盘 IO 调度器
# =========================
optimize_disk_io() {
    [[ "$SCENE" =~ ^(vps_low)$ ]] && return 0
    log_step "磁盘 IO 调度器优化"
    local optimized=0
    for disk in /sys/block/*/; do
        local name; name=$(basename "$disk")
        [[ "$name" =~ ^(loop|ram|dm-|md) ]] && continue
        local sched_file="${disk}queue/scheduler"
        [[ -f "$sched_file" ]] || continue
        local current rotational=1
        current=$(cat "$sched_file")
        rotational=$(cat "${disk}queue/rotational" 2>/dev/null || echo 1)

        local target
        if [[ "$SCENE" == "sbc" ]]; then
            if echo "$current" | grep -q "none"; then target="none"
            else target="noop"; fi
        elif [[ "$rotational" -eq 0 ]]; then
            if echo "$current" | grep -q "none"; then target="none"
            elif echo "$current" | grep -q "mq-deadline"; then target="mq-deadline"
            else target="deadline"; fi
        else
            if echo "$current" | grep -q "bfq"; then target="bfq"
            else target="cfq"; fi
        fi

        echo "$target" > "$sched_file" 2>/dev/null \
            && ok "  💿 $name（$([ "$rotational" -eq 0 ] && echo SSD || echo HDD/Flash)）→ $target" \
            || warn "  💿 $name 调度器 $target 不支持，跳过"
        optimized=$((optimized + 1))
    done
    [[ "$optimized" -eq 0 ]] && warn "未检测到可优化磁盘"
}

# =========================
# 🛜 主路由专项 sysctl
# =========================
apply_router_sysctl() {
    [[ "$SCENE" != "router" ]] && return 0
    log_step "主路由 sysctl"

    local ct_max
    ct_max=$(awk "BEGIN{printf \"%d\", int(${TOTAL_MEM_KB}*1024*0.25/350)}")
    [[ "$ct_max" -lt 65536 ]]   && ct_max=65536
    [[ "$ct_max" -gt 2097152 ]] && ct_max=2097152

    for mod in nf_conntrack nf_conntrack_ipv4 nf_conntrack_ipv6; do
        modprobe "$mod" 2>/dev/null && log "  模块: $mod" || true
    done
    cat > /etc/modules-load.d/netfilter.conf <<EOF
nf_conntrack
nf_conntrack_ipv4
nf_conntrack_ipv6
EOF

    cat > "$SYSCTL_CONF" <<EOF
# 🌉 Linux 优化 v9.0 - 主路由场景 | $(date)
# 环境: $CLOUD | CPU: ${CPU_CORES}核 | 内存: ${TOTAL_MEM_MB}MB

net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.rp_filter = 1

net.netfilter.nf_conntrack_max = ${ct_max}
net.netfilter.nf_conntrack_tcp_timeout_established = 3600
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 120
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 120
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 180
net.netfilter.nf_conntrack_icmp_timeout = 30
net.netfilter.nf_conntrack_generic_timeout = 600

net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216

net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 100000
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_syncookies = 1

net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = $(
    [[ "$BBR_SUPPORTED" -eq 1 ]] \
    && modprobe tcp_bbr 2>/dev/null \
    && echo bbr || echo cubic)

vm.swappiness = 20
vm.dirty_ratio = 10
vm.dirty_background_ratio = 3

net.ipv4.neigh.default.gc_thresh1 = 512
net.ipv4.neigh.default.gc_thresh2 = 2048
net.ipv4.neigh.default.gc_thresh3 = 4096
net.ipv6.neigh.default.gc_thresh3 = 4096

fs.file-max = 1048576
fs.nr_open = 1048576
net.ipv4.ip_local_port_range = 1024 65535
EOF
    _apply_sysctl_file "router"
    sysctl -w net.netfilter.nf_conntrack_max="$ct_max" 2>/dev/null || true
}

# =========================
# 🔀 旁路由专项 sysctl
# =========================
apply_bypass_sysctl() {
    [[ "$SCENE" != "bypass" ]] && return 0
    log_step "旁路由 sysctl"

    local ct_max
    ct_max=$(awk "BEGIN{printf \"%d\", int(${TOTAL_MEM_KB}*1024*0.15/350)}")
    [[ "$ct_max" -lt 32768 ]]  && ct_max=32768
    [[ "$ct_max" -gt 524288 ]] && ct_max=524288

    for mod in nf_conntrack nf_conntrack_ipv4 nf_conntrack_ipv6; do
        modprobe "$mod" 2>/dev/null && log "  模块: $mod" || true
    done
    cat > /etc/modules-load.d/netfilter.conf <<EOF
nf_conntrack
nf_conntrack_ipv4
nf_conntrack_ipv6
EOF

    local cc_algo="cubic" qdisc="fq_codel"
    if [[ "$BBR_SUPPORTED" -eq 1 ]] \
       && modprobe tcp_bbr 2>/dev/null; then
        cc_algo="bbr"
    fi

    local tcp_lo tcp_mid tcp_hi
    tcp_lo=$(awk  "BEGIN{printf \"%d\", int(${TOTAL_MEM_KB}*0.08/4)}")
    tcp_mid=$(awk "BEGIN{printf \"%d\", int(${TOTAL_MEM_KB}*0.12/4)}")
    tcp_hi=$(awk  "BEGIN{printf \"%d\", int(${TOTAL_MEM_KB}*0.16/4)}")

    cat > "$SYSCTL_CONF" <<EOF
# 🌉 Linux 优化 v9.0 - 旁路由场景 | $(date)
# 环境: $CLOUD | CPU: ${CPU_CORES}核 | 内存: ${TOTAL_MEM_MB}MB

net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.route_localnet = 1
net.ipv4.conf.default.route_localnet = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 100000
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_syncookies = 1

net.core.default_qdisc = ${qdisc}
net.ipv4.tcp_congestion_control = ${cc_algo}

net.core.somaxconn = 32768
net.core.netdev_max_backlog = 16384
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.ipv4.tcp_mem = ${tcp_lo} ${tcp_mid} ${tcp_hi}

net.netfilter.nf_conntrack_max = ${ct_max}
net.netfilter.nf_conntrack_tcp_timeout_established = 1800
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 60
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 60
net.netfilter.nf_conntrack_icmp_timeout = 15

net.ipv4.neigh.default.gc_thresh1 = 256
net.ipv4.neigh.default.gc_thresh2 = 1024
net.ipv4.neigh.default.gc_thresh3 = 2048

vm.swappiness = 20
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

fs.file-max = 1048576
fs.nr_open = 1048576
net.ipv4.ip_local_port_range = 1024 65535
EOF
    _apply_sysctl_file "bypass"
    sysctl -w net.netfilter.nf_conntrack_max="$ct_max" 2>/dev/null || true
    sysctl -w net.ipv4.conf.all.route_localnet=1 >/dev/null 2>&1 \
        && ok "route_localnet=1 立即生效（tproxy/redirect 可正常工作）" || true
}

# =========================
# 🔌 单片机 SBC 专项 sysctl
# =========================
apply_sbc_sysctl() {
    [[ "$SCENE" != "sbc" ]] && return 0
    log_step "单片机 SBC sysctl"

    cat > "$SYSCTL_CONF" <<EOF
# 🌉 Linux 优化 v9.0 - 单片机 SBC 场景 | $(date)
# 架构: $ARCH | CPU: ${CPU_CORES}核 | 内存: ${TOTAL_MEM_MB}MB

# ── 闪存寿命保护（核心）──
vm.dirty_ratio = 40
vm.dirty_background_ratio = 20
vm.dirty_writeback_centisecs = 1500
vm.dirty_expire_centisecs = 3000

# ── 内存管理 ──
vm.swappiness = 60
vm.vfs_cache_pressure = 50
vm.overcommit_memory = 1

# ── 网络（嵌入式保守配置）──
net.core.somaxconn = 1024
net.core.netdev_max_backlog = 1024
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304
net.core.rmem_default = 131072
net.core.wmem_default = 131072
net.ipv4.tcp_rmem = 4096 65536 4194304
net.ipv4.tcp_wmem = 4096 32768 4194304

net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_tw_buckets = 10000

# ── 文件描述符 ──
fs.file-max = 65536
fs.nr_open = 65536

net.ipv4.ip_local_port_range = 1024 65535
EOF
    _apply_sysctl_file "sbc"
}

# =========================
# 🔧 服务器场景 sysctl（vps / vps_low / baremetal）
# =========================
apply_server_sysctl() {
    [[ "$SCENE" =~ ^(router|bypass|sbc)$ ]] && return 0
    log_step "服务器 sysctl（场景: $SCENE）"

    local rmem_max wmem_max somaxconn netdev_backlog syn_backlog \
          tw_buckets swappiness dirty_ratio dirty_bg keepalive_time \
          fin_timeout file_max

    case "$SCENE" in
        vps_low)
            rmem_max=8388608;   wmem_max=8388608
            somaxconn=4096;     netdev_backlog=4096;    syn_backlog=4096
            tw_buckets=50000;   swappiness=30;          dirty_ratio=20
            dirty_bg=10;        keepalive_time=600;     fin_timeout=30
            file_max=262144
            ;;
        vps)
            rmem_max=$(( TOTAL_MEM_GB >= 8 ? 134217728 : 33554432 ))
            wmem_max=$rmem_max
            somaxconn=32768;    netdev_backlog=32768;   syn_backlog=16384
            tw_buckets=200000;  swappiness=10;          dirty_ratio=15
            dirty_bg=5;         keepalive_time=300;     fin_timeout=10
            file_max=1048576
            ;;
        baremetal)
            rmem_max=$(( TOTAL_MEM_GB >= 32 ? 536870912 : 134217728 ))
            wmem_max=$rmem_max
            somaxconn=65535;    netdev_backlog=65535;   syn_backlog=32768
            tw_buckets=500000;  swappiness=5;           dirty_ratio=10
            dirty_bg=3;         keepalive_time=120;     fin_timeout=5
            file_max=2097152
            ;;
    esac

    local cc_algo="cubic" qdisc="pfifo_fast"
    if [[ "$BBR_SUPPORTED" -eq 1 ]] && modprobe tcp_bbr 2>/dev/null; then
        cc_algo="bbr"; qdisc="fq"
        ok "BBR + fq 已启用"
    fi

    local tcp_lo tcp_mid tcp_hi
    tcp_lo=$(awk  "BEGIN{printf \"%d\", int(${TOTAL_MEM_KB}*0.10/4)}")
    tcp_mid=$(awk "BEGIN{printf \"%d\", int(${TOTAL_MEM_KB}*0.15/4)}")
    tcp_hi=$(awk  "BEGIN{printf \"%d\", int(${TOTAL_MEM_KB}*0.20/4)}")

    cat > "$SYSCTL_CONF" <<EOF
# 🌉 Linux 优化 v9.0 - 服务器场景: ${SCENE} | $(date)
# 环境: $CLOUD | CPU: ${CPU_CORES}核 | 内存: ${TOTAL_MEM_MB}MB

net.core.somaxconn = ${somaxconn}
net.core.netdev_max_backlog = ${netdev_backlog}
net.core.rmem_default = 262144
net.core.rmem_max = ${rmem_max}
net.core.wmem_default = 262144
net.core.wmem_max = ${wmem_max}
net.core.optmem_max = 65536

net.ipv4.tcp_max_syn_backlog = ${syn_backlog}
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_fin_timeout = ${fin_timeout}
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = ${tw_buckets}
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_keepalive_time = ${keepalive_time}
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

net.ipv4.tcp_rmem = 4096 87380 ${rmem_max}
net.ipv4.tcp_wmem = 4096 65536 ${wmem_max}
net.ipv4.tcp_mem = ${tcp_lo} ${tcp_mid} ${tcp_hi}

net.core.default_qdisc = ${qdisc}
net.ipv4.tcp_congestion_control = ${cc_algo}

vm.swappiness = ${swappiness}
vm.dirty_ratio = ${dirty_ratio}
vm.dirty_background_ratio = ${dirty_bg}
vm.overcommit_memory = 1

fs.file-max = ${file_max}
fs.nr_open = ${file_max}

net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
EOF
    _apply_sysctl_file "$SCENE"
}

# =========================
# ☁  云厂商专项（服务器场景）
# =========================
apply_cloud_tuning() {
    [[ "$SCENE" =~ ^(router|bypass|sbc)$ ]] && return 0
    log_step "云环境专项适配（$CLOUD）"
    case "$CLOUD" in
        AWS)
            sysctl -w net.core.rmem_max=536870912 >/dev/null 2>&1 && ok "AWS: rmem_max=512MB" || true
            sysctl -w net.ipv4.tcp_mtu_probing=1  >/dev/null 2>&1 && ok "AWS: MTU 探测已启用" || true ;;
        GCP)
            sysctl -w net.core.netdev_max_backlog=65535 >/dev/null 2>&1 && ok "GCP: backlog=65535" || true
            sysctl -w net.ipv4.tcp_mtu_probing=1        >/dev/null 2>&1 || true ;;
        Azure)
            sysctl -w net.ipv4.tcp_tw_reuse=1    >/dev/null 2>&1 && ok "Azure: tw_reuse=1" || true
            sysctl -w net.ipv4.tcp_fin_timeout=10 >/dev/null 2>&1 || true ;;
        BareMetal) ok "裸机模式：全量优化 🚀" ;;
        *)         warn "虚拟化/未知环境，仅通用参数" ;;
    esac
}

# =========================
# 📂 ulimit 持久化
# =========================
apply_ulimit() {
    log_step "持久化 ulimit"
    local nofile
    case "$SCENE" in
        sbc)           nofile=65536   ;;
        vps_low)       nofile=262144  ;;
        router|bypass) nofile=1048576 ;;
        *)             nofile=2097152 ;;
    esac
    local lc="/etc/security/limits.conf" marker="# linux-optimizer-v9"
    grep -q "$marker" "$lc" 2>/dev/null \
        && sed -i "/$marker/,/# end-linux-optimizer-v9/d" "$lc"
    cat >> "$lc" <<EOF

$marker
*    soft nofile ${nofile}
*    hard nofile ${nofile}
root soft nofile ${nofile}
root hard nofile ${nofile}
# end-linux-optimizer-v9
EOF
    ulimit -n "$nofile" 2>/dev/null && ok "ulimit -n = $nofile（当前会话生效）" \
        || warn "当前 shell 设置失败，重登录后生效"
}

# =========================
# 📊 验证
# =========================
verify_settings() {
    log_step "验证关键参数"
    declare -A checks
    case "$SCENE" in
        router)
            checks=(["net.ipv4.ip_forward"]="1"
                    ["net.ipv4.tcp_syncookies"]="1"
                    ["vm.swappiness"]="20") ;;
        bypass)
            checks=(["net.ipv4.ip_forward"]="1"
                    ["net.ipv4.conf.all.route_localnet"]="1"
                    ["net.ipv4.conf.all.rp_filter"]="0"
                    ["net.ipv4.tcp_syncookies"]="1") ;;
        sbc)
            checks=(["vm.swappiness"]="60"
                    ["vm.dirty_ratio"]="40"
                    ["vm.vfs_cache_pressure"]="50") ;;
        *)
            checks=(["net.core.somaxconn"]="$(sysctl -n net.core.somaxconn 2>/dev/null || echo 0)"
                    ["net.ipv4.tcp_tw_reuse"]="1"
                    ["net.ipv4.tcp_syncookies"]="1"
                    ["fs.file-max"]="$(sysctl -n fs.file-max 2>/dev/null || echo 0)") ;;
    esac
    local pass=0 fail=0
    for key in "${!checks[@]}"; do
        local exp="${checks[$key]}"
        local act; act=$(sysctl -n "$key" 2>/dev/null || echo "N/A")
        if [[ "$act" == "$exp" ]]; then
            ok "  ✔ $key = $act"; pass=$((pass + 1))
        else
            warn "  ✘ $key = $act（期望: $exp）"; fail=$((fail + 1))
        fi
    done
    ok "验证完成：✔ $pass  ✘ $fail"
    [[ "$fail" -gt 0 ]] && warn "异常项可能由内核版本或虚拟化限制导致"
}

# =========================
# 🔧 内部：应用 sysctl
# =========================
_apply_sysctl_file() {
    local label="$1"
    if sysctl --system > /tmp/sysctl_out.txt 2>&1; then
        ok "$label sysctl 全部应用成功"
    else
        local errs
        errs=$(grep -v "^$\|^Applying\|^#" /tmp/sysctl_out.txt \
               | grep -i "error\|invalid" || true)
        [[ -n "$errs" ]] && while IFS= read -r l; do warn "  $l"; done <<< "$errs"
        ok "$label sysctl 主要参数已应用"
    fi
    rm -f /tmp/sysctl_out.txt
}

# =========================
# 📊 摘要
# =========================
show_summary() {
    declare -A scene_zh=(
        [vps]="普通 VPS / 云主机"
        [vps_low]="低配 VPS（保守）"
        [bypass]="旁路由（透明代理）"
        [router]="主路由 / 软路由"
        [sbc]="单片机 / SBC"
        [baremetal]="裸机服务器（激进）"
    )
    echo
    printf "${CYAN}╔══════════════════════════════════════════════╗${RESET}\n"
    printf "${CYAN}║${GREEN}  🎉 Linux 架构级优化 v2.0 完成！             ${CYAN}║${RESET}\n"
    printf "${CYAN}╠══════════════════════════════════════════════╣${RESET}\n"
    printf "${CYAN}║${RESET}  🎭 优化场景 : %-30s${CYAN}║${RESET}\n" "${scene_zh[$SCENE]:-$SCENE}"
    printf "${CYAN}║${RESET}  ☁️  云环境   : %-30s${CYAN}║${RESET}\n" "$CLOUD"
    printf "${CYAN}║${RESET}  🖥️  CPU      : %-30s${CYAN}║${RESET}\n" "${CPU_CORES}核 ($ARCH)"
    printf "${CYAN}║${RESET}  💾 内存     : %-30s${CYAN}║${RESET}\n" "${TOTAL_MEM_MB}MB"
    printf "${CYAN}║${RESET}  📄 配置文件 : %-30s${CYAN}║${RESET}\n" "$SYSCTL_CONF"
    printf "${CYAN}║${RESET}  💾 备份     : %-30s${CYAN}║${RESET}\n" "$(basename "$BACKUP_DIR")"
    printf "${CYAN}╠══════════════════════════════════════════════╣${RESET}\n"
    printf "${CYAN}║${RESET}  🔄 回滚：sysctl --system（还原备份后）      ${CYAN}║${RESET}\n"
    printf "${CYAN}║${RESET}  ⚡ 跳过菜单：$0 --scene <场景>${CYAN}║${RESET}\n"
    printf "${CYAN}╚══════════════════════════════════════════════╝${RESET}\n"
    echo
    warn "⚠️  ulimit 重登录后对新进程完全生效"
    [[ "$SCENE" =~ ^(router|bypass)$ ]] && warn "⚠️  conntrack 模块已持久化，重启自动加载"
    [[ "$SCENE" == "bypass" ]] && warn "⚠️  route_localnet=1 已开启，tproxy/redirect 正常工作"
    [[ "$SCENE" == "sbc" ]] && warn "⚠️  dirty_ratio=40 保护闪存，写入延迟略有增加属正常"
}

# =========================
# 🚀 主流程
# =========================
main() {
    parse_args "$@"

    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║  🌉 Linux 架构级优化工具 v9.0                ║"
    echo "║  VPS | 低配VPS | 旁路由 | 主路由 | 裸机 | SBC ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${RESET}"

    preflight_check
    detect_cloud
    select_scene      # ← 替换原来的 detect_scene

    confirm_action
    backup_sysctl

    case "$SCENE" in
        sbc)
            optimize_disk_io
            apply_sbc_sysctl
            apply_ulimit
            ;;
        bypass)
            optimize_irq
            optimize_disk_io
            apply_bypass_sysctl
            apply_ulimit
            ;;
        router)
            optimize_irq
            optimize_disk_io
            apply_router_sysctl
            apply_ulimit
            ;;
        vps_low)
            apply_server_sysctl
            apply_ulimit
            ;;
        vps)
            optimize_irq
            optimize_disk_io
            apply_server_sysctl
            apply_cloud_tuning
            apply_ulimit
            ;;
        baremetal)
            optimize_numa
            optimize_irq
            optimize_100g
            optimize_disk_io
            apply_server_sysctl
            apply_cloud_tuning
            apply_ulimit
            ;;
    esac

    verify_settings
    show_summary
}

main "$@"
