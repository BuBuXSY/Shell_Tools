#!/bin/bash
# ====================================================
# 🌉 Linux 内核架构级优化工具 v7.0
# 🚀 全场景自动识别与差异化优化
# 📦 场景：普通VPS | 低配VPS | 软路由/网关 | 裸机服务器
# ☁  云厂商自适应 | NUMA | IRQ | 100G | BBR
# 🛡 备份回滚 | 幂等执行 | ulimit 持久化
# By: BuBuXSY | Version: 7.0
# 最低要求：bash 4.0+
# ====================================================

set -uo pipefail

# bash 版本检查（关联数组 declare -A 需要 bash 4.0+）
if (( BASH_VERSINFO[0] < 4 )); then
    echo "❌ 此脚本需要 bash 4.0+（当前: $BASH_VERSION）"
    echo "   macOS 用户请执行：brew install bash"
    exit 1
fi

# =========================
# 🎨 样式
# =========================
readonly RED=$'\033[1;31m'
readonly GREEN=$'\033[1;32m'
readonly YELLOW=$'\033[1;33m'
readonly CYAN=$'\033[1;36m'
readonly BLUE=$'\033[1;34m'
readonly RESET=$'\033[0m'

# =========================
# 📋 日志系统
# =========================
readonly LOG_FILE="/var/log/linux-optimizer-v7.log"
readonly SYSCTL_CONF="/etc/sysctl.d/99-v7-performance.conf"
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
# 📋 全局状态变量
# =========================
CPU_CORES=$(nproc)
TOTAL_MEM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
TOTAL_MEM_MB=$(( TOTAL_MEM_KB / 1024 ))
TOTAL_MEM_GB=$(( TOTAL_MEM_KB / 1024 / 1024 ))
CLOUD="Unknown"
BBR_SUPPORTED=1
SCENE="unknown"         # 自动检测后填入：vps_low / vps / router / bypass / baremetal

# =========================
# 🛡 前置检查
# =========================
preflight_check() {
    log_step "前置检查"

    if [[ $EUID -ne 0 ]]; then
        err "必须使用 root 权限运行（sudo 或 su -）"; exit 1
    fi

    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE" 2>/dev/null || { err "无法写入日志: $LOG_FILE"; exit 1; }

    # 内核版本（BBR 需要 4.9+）
    local kver
    kver=$(uname -r | awk -F. '{print $1*100+$2}')
    if [[ "$kver" -lt 409 ]]; then
        warn "内核 $(uname -r) 低于 4.9，BBR 不可用"
        BBR_SUPPORTED=0
    else
        BBR_SUPPORTED=1
    fi

    # 必要命令
    local missing=()
    for cmd in awk sysctl nproc; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    [[ ${#missing[@]} -gt 0 ]] && { err "缺少必要命令: ${missing[*]}"; exit 1; }

    ok "预检通过（内核: $(uname -r) | 架构: $(uname -m) | CPU: ${CPU_CORES}核 | 内存: ${TOTAL_MEM_MB}MB）"
}

# =========================
# ☁  云厂商检测
# =========================
detect_cloud() {
    local product=""
    product=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo "")

    if echo "$product" | grep -qi "amazon\|ec2"; then           CLOUD="AWS"
    elif echo "$product" | grep -qi "google"; then              CLOUD="GCP"
    elif echo "$product" | grep -qi "microsoft\|azure"; then    CLOUD="Azure"
    elif [[ -f /sys/hypervisor/type ]]; then                    CLOUD="Virtualized"
    elif command -v systemd-detect-virt >/dev/null 2>&1 \
         && systemd-detect-virt -q 2>/dev/null; then            CLOUD="Virtualized"
    else                                                        CLOUD="BareMetal"
    fi
}

# =========================
# 🔍 场景自动识别
# ──────────────────────────────────────────────────
# 识别优先级（从高到低）：
#
# 1. 旁路由（bypass router）—— 优先于主路由判断，防止误判
#    - ip_forward = 1（在做转发）
#    - 物理网卡只有 1 块（单臂接入，不是多口路由器）
#    - 默认路由下一跳不是自己（自己不是网关）
#    - 存在透明代理进程或 tproxy iptables 规则
#
# 2. 软路由 / 主路由 / 网关
#    - ip_forward = 1
#    - 物理网卡 ≥ 2 块，或 OpenWrt，或存在全量 NAT 规则
#
# 3. 低配 VPS（内存 ≤ 1GB）
#
# 4. 裸机服务器（非虚拟化 + 内存 ≥ 16GB + CPU ≥ 8 核）
#
# 5. 普通 VPS（兜底）
# =========================
detect_scene() {
    log_step "场景自动识别"

    # ── 基础信息收集 ──
    local ip_fwd
    ip_fwd=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 0)

    # 物理网卡数量（排除虚拟设备）
    local phys_nics=0
    for iface in /sys/class/net/*/; do
        local name; name=$(basename "$iface")
        [[ "$name" =~ ^(lo|docker|veth|virbr|tun|tap|br-|dummy|bond|team) ]] && continue
        [[ -d "${iface}device" ]] && phys_nics=$((phys_nics + 1))
    done

    # ============================================================
    # 🔍 维度1：旁路由检测（优先级最高，防止被误判为主路由）
    # ============================================================
    local bypass_score=0         # 累计旁路由特征得分，≥ 2 分判定为旁路由
    local bypass_reasons=()

    # 特征 A：ip_forward 已开启（必要条件，不满足直接跳过）
    if [[ "$ip_fwd" == "1" ]]; then

        # 特征 B：单物理网卡（旁路由单臂接入，得 2 分；主路由多网卡）
        if [[ "$phys_nics" -eq 1 ]]; then
            bypass_score=$((bypass_score + 2))
            bypass_reasons+=("单物理网卡（单臂旁路由特征，得 2 分）")
        fi

        # 特征 C：默认路由下一跳不是本机任何 IP（自己不是网关，得 2 分）
        local default_gw local_ips gw_is_self=0
        default_gw=$(ip route show default 2>/dev/null | awk '/default via/{print $3; exit}')
        if [[ -n "$default_gw" ]]; then
            local_ips=$(ip addr show 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
            while IFS= read -r lip; do
                [[ "$lip" == "$default_gw" ]] && gw_is_self=1 && break
            done <<< "$local_ips"
            if [[ "$gw_is_self" -eq 0 ]]; then
                bypass_score=$((bypass_score + 2))
                bypass_reasons+=("默认网关（$default_gw）不是本机 IP，自己不充当网关（得 2 分）")
            fi
        fi

        # 特征 D：存在透明代理进程（clash / sing-box / v2ray / xray / tun2socks）
        for proc in clash sing-box v2ray xray tun2socks mihomo; do
            if pgrep -x "$proc" >/dev/null 2>&1 \
               || systemctl is-active --quiet "$proc" 2>/dev/null; then
                bypass_score=$((bypass_score + 3))
                bypass_reasons+=("检测到透明代理进程: $proc（得 3 分）")
                break
            fi
        done

        # 特征 E：存在 tproxy iptables 规则（TPROXY 目标 = 旁路由透明代理标志）
        if command -v iptables >/dev/null 2>&1; then
            local tproxy_rules
            tproxy_rules=$(iptables -t mangle -L 2>/dev/null | grep -c TPROXY || echo 0)
            if [[ "$tproxy_rules" -gt 0 ]]; then
                bypass_score=$((bypass_score + 3))
                bypass_reasons+=("检测到 ${tproxy_rules} 条 TPROXY mangle 规则（得 3 分）")
            fi
        fi
        if command -v nft >/dev/null 2>&1; then
            local nft_tproxy
            nft_tproxy=$(nft list ruleset 2>/dev/null | grep -c tproxy || echo 0)
            if [[ "$nft_tproxy" -gt 0 ]]; then
                bypass_score=$((bypass_score + 3))
                bypass_reasons+=("nftables 检测到 ${nft_tproxy} 条 tproxy 规则（得 3 分）")
            fi
        fi

        # 特征 F：只有 1 条默认路由（旁路由不做复杂多路由策略）
        local default_route_count
        default_route_count=$(ip route show default 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$default_route_count" -eq 1 ]]; then
            bypass_score=$((bypass_score + 1))
            bypass_reasons+=("只有 1 条默认路由（得 1 分）")
        fi
    fi

    # ============================================================
    # 🔍 维度2：主路由 / 软路由特征
    # ============================================================
    local is_router=0
    local router_reasons=()

    if [[ "$ip_fwd" == "1" ]]; then
        # 多物理网卡（主路由核心特征）
        if [[ "$phys_nics" -ge 2 ]]; then
            is_router=1
            router_reasons+=("检测到 ${phys_nics} 块物理网卡（多接口路由）")
        fi
        # OpenWrt
        if [[ -f /etc/openwrt_release ]]; then
            is_router=1
            router_reasons+=("OpenWrt 系统")
        fi
        # 全量 NAT（MASQUERADE 覆盖所有出口流量）
        if command -v iptables >/dev/null 2>&1; then
            local nat_rules
            nat_rules=$(iptables -t nat -L POSTROUTING 2>/dev/null | grep -c MASQUERADE || echo 0)
            if [[ "$nat_rules" -gt 0 ]]; then
                is_router=1
                router_reasons+=("存在 ${nat_rules} 条 MASQUERADE NAT 规则")
            fi
        fi
        if command -v nft >/dev/null 2>&1; then
            local nft_nat
            nft_nat=$(nft list ruleset 2>/dev/null | grep -c masquerade || echo 0)
            if [[ "$nft_nat" -gt 0 ]]; then
                is_router=1
                router_reasons+=("nftables 存在 masquerade 规则")
            fi
        fi
    fi

    # ============================================================
    # ✅ 最终判断（旁路由优先于主路由）
    # ============================================================
    if [[ "$ip_fwd" == "1" && "$bypass_score" -ge 2 && "$bypass_score" -gt "$is_router" ]]; then
        SCENE="bypass"
        ok "🔀 识别为：旁路由（透明代理模式，得分: $bypass_score）"
        for r in "${bypass_reasons[@]}"; do log "  └─ $r"; done

    elif [[ "$is_router" -eq 1 ]]; then
        SCENE="router"
        ok "🛜 识别为：软路由 / 主路由 / 网关"
        for r in "${router_reasons[@]}"; do log "  └─ $r"; done

    elif [[ "$TOTAL_MEM_MB" -le 1024 ]]; then
        SCENE="vps_low"
        ok "🐣 识别为：低配 VPS（内存 ${TOTAL_MEM_MB}MB ≤ 1024MB）"

    elif [[ "$CLOUD" == "BareMetal" && "$TOTAL_MEM_GB" -ge 16 && "$CPU_CORES" -ge 8 ]]; then
        SCENE="baremetal"
        ok "🏢 识别为：裸机服务器（非虚拟化 | 内存 ${TOTAL_MEM_GB}GB | ${CPU_CORES}核）"

    else
        SCENE="vps"
        ok "☁  识别为：普通 VPS / 云主机（${CLOUD} | 内存 ${TOTAL_MEM_GB}GB）"
    fi
}

# =========================
# ❓ 确认提示
# =========================
confirm_action() {
    log_step "操作确认"

    local scene_desc
    case "$SCENE" in
        vps_low)   scene_desc="低配 VPS（保守参数，优先稳定性）" ;;
        vps)       scene_desc="普通 VPS / 云主机（均衡参数）" ;;
        router)    scene_desc="软路由 / 网关（转发优化 + conntrack + NAT）" ;;
        bypass)    scene_desc="旁路由（透明代理 + 低延迟 + tproxy）" ;;
        baremetal) scene_desc="裸机服务器（激进参数，全量优化）" ;;
        *)         scene_desc="未知（通用参数）" ;;
    esac

    echo
    echo -e "${BLUE}  📊 检测结果摘要${RESET}"
    echo    "  ┌─────────────────────────────────────────────"
    printf  "  │  🎭 识别场景  : %s\n" "$scene_desc"
    printf  "  │  ☁  云环境    : %s\n" "$CLOUD"
    printf  "  │  🖥️  CPU 核心  : %s 核\n" "$CPU_CORES"
    printf  "  │  💾 物理内存  : %s MB\n" "$TOTAL_MEM_MB"
    printf  "  │  🐧 内核版本  : %s\n" "$(uname -r)"
    echo    "  └─────────────────────────────────────────────"
    echo
    warn "以下文件将被修改："
    echo "    📄 $SYSCTL_CONF"
    echo "    📄 /etc/security/limits.conf"
    [[ "$SCENE" == "router" || "$SCENE" == "bypass" ]] && echo "    📄 /etc/modules-load.d/netfilter.conf（conntrack 模块）"
    echo
    read -rp "$(echo -e "${YELLOW}❓ 确认继续优化？[y/N]：${RESET}")" confirm
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
    ok "备份完成 → $BACKUP_DIR"
    ok "回滚命令：cp $BACKUP_DIR/*.conf /etc/sysctl.d/ && sysctl --system"
}

# =========================
# 🧠 NUMA 优化
# =========================
optimize_numa() {
    # 低配 VPS 和软路由跳过（资源紧张，NUMA 收益低）
    [[ "$SCENE" == "vps_low" || "$SCENE" == "router" ]] && return 0

    log_step "NUMA 优化"
    if ! command -v numactl >/dev/null 2>&1; then
        warn "未安装 numactl，跳过（apt/yum install numactl）"
        return 0
    fi

    local numa_nodes
    numa_nodes=$(numactl --hardware 2>/dev/null | awk '/available:/{print $2}')
    if [[ -z "$numa_nodes" || ! "$numa_nodes" =~ ^[0-9]+$ ]]; then
        warn "无法解析 NUMA 拓扑，跳过"; return 0
    fi

    if [[ "$numa_nodes" -gt 1 ]]; then
        numactl --interleave=all true 2>/dev/null \
            && ok "NUMA interleave=all 已启用（$numa_nodes 个节点）" \
            || warn "NUMA interleave 设置失败（虚拟化环境常见）"
    else
        warn "单 NUMA 节点，跳过"
    fi
}

# =========================
# ⚡ IRQ 亲和性优化
# =========================
optimize_irq() {
    # 低配 VPS 跳过（核心少，无需分配）
    [[ "$SCENE" == "vps_low" ]] && return 0

    log_step "IRQ 亲和性优化"

    local use_list=0 cpu_mask="" cpu_list="0-$((CPU_CORES - 1))"

    if [[ "$CPU_CORES" -le 32 ]]; then
        cpu_mask=$(printf "%x" $(( (1 << CPU_CORES) - 1 )))
    else
        use_list=1
        warn "CPU 核心数 > 32，使用 smp_affinity_list 模式"
    fi

    local count=0
    for irq_dir in /proc/irq/*/; do
        local irq_num; irq_num=$(basename "$irq_dir")
        [[ "$irq_num" =~ ^[0-9]+$ ]] || continue
        if [[ "$use_list" -eq 1 && -f "${irq_dir}smp_affinity_list" ]]; then
            echo "$cpu_list" > "${irq_dir}smp_affinity_list" 2>/dev/null \
                && count=$((count + 1)) || true
        elif [[ -f "${irq_dir}smp_affinity" ]]; then
            echo "$cpu_mask" > "${irq_dir}smp_affinity" 2>/dev/null \
                && count=$((count + 1)) || true
        fi
    done
    ok "IRQ 亲和性已更新（$count 条 | ${cpu_mask:+mask:0x$cpu_mask}${use_list:+list:$cpu_list}）"
}

# =========================
# 🚀 100G 网卡优化（裸机专属）
# =========================
optimize_100g() {
    [[ "$SCENE" != "baremetal" ]] && return 0

    log_step "100G 网卡优化（裸机模式）"
    local found=0

    for iface in /sys/class/net/*/; do
        local name; name=$(basename "$iface")
        [[ "$name" == "lo" ]] && continue
        local speed=0
        speed=$(cat "${iface}speed" 2>/dev/null || echo 0)
        [[ "$speed" =~ ^[0-9]+$ ]] || speed=0
        [[ "$speed" -ge 100000 ]] || continue

        ok "检测到 100G+ 网卡: $name（${speed}Mb/s）"
        found=1

        command -v ethtool >/dev/null 2>&1 && {
            ethtool -L "$name" combined "$CPU_CORES" 2>/dev/null \
                && ok "  └─ 队列数已设为 $CPU_CORES" \
                || warn "  └─ 队列调整失败（驱动不支持），跳过"
        }

        echo 4096 > /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null || true

        local rps_cpus
        if [[ "$CPU_CORES" -le 32 ]]; then
            rps_cpus=$(printf "%x" $(( (1 << CPU_CORES) - 1 )))
        else
            local hex_len=$(( (CPU_CORES + 3) / 4 ))
            local prefix_groups=$(( CPU_CORES / 32 ))
            local prefix=""
            for (( i=0; i<prefix_groups; i++ )); do prefix+="ffffffff"; done
            rps_cpus="${prefix}$(printf '%0*x' "$hex_len" $(( (1 << (CPU_CORES % 32 == 0 ? 32 : CPU_CORES % 32)) - 1 )))"
        fi

        for rxq in "${iface}queues/rx-"*/rps_cpus; do
            [[ -f "$rxq" ]] && echo "$rps_cpus" > "$rxq" 2>/dev/null || true
        done
        ok "  └─ RPS mask 已设置（$rps_cpus）"
    done

    [[ "$found" -eq 0 ]] && warn "未检测到 100G+ 网卡，跳过"
}

# =========================
# 🛜 软路由 / 网关专项优化
# ──────────────────────────────────────────────────
# 与服务器优化的核心差异：
#  - 开启 IP 转发（ip_forward / ip6_forward）
#  - 扩大 conntrack 表（NAT 追踪连接数）
#  - 关闭不必要的 TCP 优化（减少转发延迟）
#  - 启用 ECMP / 策略路由支持
#  - 调低内存消耗参数（软路由通常内存少）
# =========================
optimize_router() {
    [[ "$SCENE" != "router" ]] && return 0

    log_step "软路由 / 网关专项优化"

    # --- conntrack 最大连接数（按内存动态计算）---
    # 经验值：每条 conntrack 记录约占 350 字节
    # 用可用内存的 25% 分配给 conntrack
    local ct_max
    ct_max=$(awk "BEGIN{printf \"%d\", int(${TOTAL_MEM_KB} * 1024 * 0.25 / 350)}")
    # 最小 65536，最大 2097152
    [[ "$ct_max" -lt 65536 ]]   && ct_max=65536
    [[ "$ct_max" -gt 2097152 ]] && ct_max=2097152
    ok "conntrack 最大连接数计算: $ct_max（内存 ${TOTAL_MEM_MB}MB × 25% ÷ 350B/条）"

    # --- 加载 conntrack 模块 ---
    for mod in nf_conntrack nf_conntrack_ipv4 nf_conntrack_ipv6; do
        modprobe "$mod" 2>/dev/null && log "  模块已加载: $mod" || true
    done

    # 持久化模块加载（重启后生效）
    cat > /etc/modules-load.d/netfilter.conf <<EOF
nf_conntrack
nf_conntrack_ipv4
nf_conntrack_ipv6
EOF
    ok "conntrack 模块已配置持久化加载"

    # --- 路由器专用 sysctl ---
    cat > "$SYSCTL_CONF" <<EOF
# ==============================================
# 🌉 Linux 优化 v7.0 - 软路由 / 网关场景
# 生成时间: $(date)
# 环境: $CLOUD | CPU: ${CPU_CORES}核 | 内存: ${TOTAL_MEM_MB}MB
# ==============================================

# ── IP 转发（核心，网关必须开启）──
net.ipv4.ip_forward = 1                         # 开启 IPv4 内核转发
net.ipv6.conf.all.forwarding = 1                # 开启 IPv6 内核转发
net.ipv4.conf.all.send_redirects = 0            # 网关不发送 ICMP 重定向（可能暴露拓扑）
net.ipv4.conf.all.accept_redirects = 0          # 不接受 ICMP 重定向（防中间人）
net.ipv4.conf.default.rp_filter = 1             # 反向路径过滤，防 IP 欺骗

# ── Netfilter / conntrack（NAT 核心）──
net.netfilter.nf_conntrack_max = ${ct_max}                  # 最大连接追踪数（内存自适应）
net.netfilter.nf_conntrack_tcp_timeout_established = 3600   # 已建立 TCP 连接超时 1 小时
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 120      # TIME_WAIT 超时 2 分钟
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60      # CLOSE_WAIT 超时 1 分钟
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 120       # FIN_WAIT 超时 2 分钟
net.netfilter.nf_conntrack_udp_timeout = 30                 # UDP 连接超时 30 秒（DNS 等短连接）
net.netfilter.nf_conntrack_udp_timeout_stream = 180         # UDP 流超时 3 分钟
net.netfilter.nf_conntrack_icmp_timeout = 30                # ICMP 超时 30 秒
net.netfilter.nf_conntrack_generic_timeout = 600            # 其他协议超时 10 分钟

# ── 网络缓冲区（转发场景适度，不能太大避免内存压力）──
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.core.rmem_max = 16777216                    # 16MB（软路由内存有限）
net.core.wmem_max = 16777216

# ── TCP 转发优化 ──
net.ipv4.tcp_fastopen = 3                       # TFO 减少握手延迟
net.ipv4.tcp_fin_timeout = 15                   # 加速端口回收
net.ipv4.tcp_tw_reuse = 1                       # TIME_WAIT 复用
net.ipv4.tcp_max_tw_buckets = 100000            # TIME_WAIT 上限
net.ipv4.tcp_keepalive_time = 600               # 空闲连接探活（软路由连接生命周期更长）
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_syncookies = 1                     # SYN Cookie 防 SYN flood

# ── 内存管理（保守，优先稳定）──
vm.swappiness = 20                              # 软路由适当允许 swap（内存紧张时）
vm.dirty_ratio = 10
vm.dirty_background_ratio = 3

# ── 路由表 & ARP（多接口环境）──
net.ipv4.neigh.default.gc_thresh1 = 512
net.ipv4.neigh.default.gc_thresh2 = 2048
net.ipv4.neigh.default.gc_thresh3 = 4096        # ARP 缓存上限（多设备网络防 ARP 表溢出）
net.ipv4.route.gc_timeout = 100
net.ipv6.neigh.default.gc_thresh3 = 4096

# ── 文件描述符（软路由连接多）──
fs.file-max = 1048576
fs.nr_open = 1048576

# ── 端口范围 ──
net.ipv4.ip_local_port_range = 1024 65535
EOF

    # 立即应用 conntrack 运行时参数（部分参数需要模块加载后才能 sysctl 写入）
    sysctl -w net.netfilter.nf_conntrack_max="$ct_max" 2>/dev/null \
        && ok "conntrack_max 运行时已设为 $ct_max" || warn "conntrack_max 运行时设置失败（模块未加载？）"

    ok "软路由 sysctl 配置已写入 $SYSCTL_CONF"
}

# =========================
# 🔀 旁路由专项优化
# ──────────────────────────────────────────────────
# 与主路由的核心差异：
#  - 不做全量 NAT，只处理被引导过来的代理流量
#  - 必须开启 route_localnet（tproxy 将流量重定向到本机需要此项）
#  - 使用 fq_codel 替代 fq（更适合低延迟代理，尤其是小包密集场景）
#  - conntrack 表比主路由小（只处理部分流量）
#  - TCP 缓冲区中等（内存通常比主路由更紧张）
#  - tcp_no_metrics_save=1（避免代理场景下缓存失效的历史指标影响新连接）
# =========================
optimize_bypass() {
    [[ "$SCENE" != "bypass" ]] && return 0

    log_step "旁路由专项优化（透明代理模式）"

    # conntrack 表：旁路由只处理部分流量，用内存 15% 分配
    local ct_max
    ct_max=$(awk "BEGIN{printf \"%d\", int(${TOTAL_MEM_KB} * 1024 * 0.15 / 350)}")
    [[ "$ct_max" -lt 32768 ]]  && ct_max=32768
    [[ "$ct_max" -gt 524288 ]] && ct_max=524288
    ok "conntrack 表大小: $ct_max（内存 ${TOTAL_MEM_MB}MB × 15% ÷ 350B/条）"

    # 加载 conntrack 模块
    for mod in nf_conntrack nf_conntrack_ipv4 nf_conntrack_ipv6; do
        modprobe "$mod" 2>/dev/null && log "  模块已加载: $mod" || true
    done
    cat > /etc/modules-load.d/netfilter.conf <<EOF
nf_conntrack
nf_conntrack_ipv4
nf_conntrack_ipv6
EOF
    ok "conntrack 模块已持久化"

    # qdisc 选择：fq_codel（低延迟，AQM 抑制缓冲膨胀，比 fq 更适合代理小包场景）
    local qdisc="fq_codel"
    local cc_algo="bbr"
    if [[ "$BBR_SUPPORTED" -eq 0 ]] \
       || ! modprobe tcp_bbr 2>/dev/null \
       && ! grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        cc_algo="cubic"
        qdisc="fq_codel"    # fq_codel 不依赖 BBR，仍然有效
        warn "BBR 不可用，回退到 cubic，qdisc 保持 fq_codel"
    else
        ok "BBR + fq_codel 已启用（低延迟透明代理最优组合）"
    fi

    local tcp_mem_lo tcp_mem_mid tcp_mem_hi
    tcp_mem_lo=$(awk  "BEGIN{printf \"%d\", int(${TOTAL_MEM_KB}*0.08/4)}")
    tcp_mem_mid=$(awk "BEGIN{printf \"%d\", int(${TOTAL_MEM_KB}*0.12/4)}")
    tcp_mem_hi=$(awk  "BEGIN{printf \"%d\", int(${TOTAL_MEM_KB}*0.16/4)}")

    cat > "$SYSCTL_CONF" <<EOF
# ==============================================
# 🌉 Linux 优化 v7.0 - 旁路由 / 透明代理场景
# 生成时间: $(date)
# 环境: $CLOUD | CPU: ${CPU_CORES}核 | 内存: ${TOTAL_MEM_MB}MB
# ==============================================

# ── IP 转发（旁路由必须开启，处理被引导来的流量）──
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# ── tproxy 透明代理必要参数 ──
net.ipv4.conf.all.route_localnet = 1        # 允许本地回环地址参与路由，tproxy 重定向必须项
net.ipv4.conf.default.route_localnet = 1

# ── TCP 性能（代理低延迟优先）──
net.ipv4.tcp_no_metrics_save = 1            # 不缓存历史连接指标，代理场景每条连接独立计算 RTT
net.ipv4.tcp_fastopen = 3                   # TFO 减少握手 RTT（代理出口连接获益明显）
net.ipv4.tcp_fin_timeout = 15               # 加速端口回收
net.ipv4.tcp_tw_reuse = 1                   # TIME_WAIT 复用（代理出口连接较多）
net.ipv4.tcp_max_tw_buckets = 100000
net.ipv4.tcp_syn_retries = 2                # 代理场景连接失败应快速失败，减少重试等待
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3           # 旁路由代理连接生命周期短，减少探活次数
net.ipv4.tcp_syncookies = 1

# ── 拥塞控制（BBR + fq_codel：低延迟最优组合）──
net.core.default_qdisc = ${qdisc}           # fq_codel：主动队列管理，抑制缓冲膨胀（bufferbloat）
net.ipv4.tcp_congestion_control = ${cc_algo}

# ── 网络缓冲区（中等，旁路由内存有限）──
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 16384
net.core.rmem_max = 33554432                # 32MB（代理流量单连接带宽需求不高）
net.core.wmem_max = 33554432
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.ipv4.tcp_mem = ${tcp_mem_lo} ${tcp_mem_mid} ${tcp_mem_hi}

# ── Netfilter / conntrack（只处理代理流量，表比主路由小）──
net.netfilter.nf_conntrack_max = ${ct_max}
net.netfilter.nf_conntrack_tcp_timeout_established = 1800   # 代理连接生命周期短，30 分钟足够
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 60
net.netfilter.nf_conntrack_udp_timeout = 30                 # DNS / UDP 代理短超时
net.netfilter.nf_conntrack_udp_timeout_stream = 60
net.netfilter.nf_conntrack_icmp_timeout = 15

# ── 安全 ──
net.ipv4.conf.all.rp_filter = 0            # 旁路由流量来源多样，关闭反向路径过滤防丢包
net.ipv4.conf.default.rp_filter = 0        # （主路由保持 rp_filter=1，旁路由需关闭）
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# ── 内存（保守，旁路由通常内存较少）──
vm.swappiness = 20
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# ── ARP（单臂接入，防 ARP 表溢出）──
net.ipv4.neigh.default.gc_thresh1 = 256
net.ipv4.neigh.default.gc_thresh2 = 1024
net.ipv4.neigh.default.gc_thresh3 = 2048

# ── 文件描述符 ──
fs.file-max = 1048576
fs.nr_open = 1048576

# ── 端口范围 ──
net.ipv4.ip_local_port_range = 1024 65535
EOF

    # 立即应用 conntrack 运行时参数
    sysctl -w net.netfilter.nf_conntrack_max="$ct_max" 2>/dev/null \
        && ok "conntrack_max 运行时已设为 $ct_max" \
        || warn "conntrack_max 运行时设置失败（模块可能未加载）"

    sysctl -w net.ipv4.conf.all.route_localnet=1 >/dev/null 2>&1 \
        && ok "route_localnet 已立即启用（tproxy 生效）" || warn "route_localnet 设置失败"

    # 应用全部配置
    if sysctl --system > /tmp/sysctl_out.txt 2>&1; then
        ok "旁路由 sysctl 参数已全部应用（cc=$cc_algo | qdisc=$qdisc）"
    else
        local errs
        errs=$(grep -v "^$\|^Applying\|^#" /tmp/sysctl_out.txt \
               | grep -i "error\|invalid" || true)
        [[ -n "$errs" ]] && while IFS= read -r line; do warn "  $line"; done <<< "$errs"
        ok "旁路由 sysctl 主要参数已应用"
    fi
    rm -f /tmp/sysctl_out.txt
}

# =========================
# 🔧 服务器场景 sysctl（VPS / 低配VPS / 裸机）
# =========================
apply_server_sysctl() {
    [[ "$SCENE" == "router" ]] && return 0

    log_step "应用服务器 sysctl 参数（场景: $SCENE）"

    # ── 按场景计算缓冲区上限 ──
    local rmem_max wmem_max
    case "$SCENE" in
        vps_low)
            # 低配 VPS：保守，避免 OOM
            rmem_max=8388608        # 8MB
            wmem_max=8388608
            ;;
        vps)
            if [[ "$TOTAL_MEM_GB" -ge 8 ]]; then
                rmem_max=134217728  # 128MB
                wmem_max=134217728
            else
                rmem_max=33554432   # 32MB
                wmem_max=33554432
            fi
            ;;
        baremetal)
            if [[ "$TOTAL_MEM_GB" -ge 32 ]]; then
                rmem_max=536870912  # 512MB
                wmem_max=536870912
            else
                rmem_max=134217728  # 128MB
                wmem_max=134217728
            fi
            ;;
        *)
            rmem_max=33554432; wmem_max=33554432
            ;;
    esac

    # ── BBR 拥塞控制 ──
    local cc_algo="cubic" qdisc="pfifo_fast"
    if [[ "$BBR_SUPPORTED" -eq 1 ]]; then
        if modprobe tcp_bbr 2>/dev/null \
           || grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
            cc_algo="bbr"; qdisc="fq"
            ok "BBR 已启用（qdisc=fq）"
        else
            warn "BBR 模块不可用，回退到 cubic"
        fi
    fi

    # ── tcp_mem 取整（修复浮点写入问题）──
    local tcp_mem_lo tcp_mem_mid tcp_mem_hi
    tcp_mem_lo=$(awk  "BEGIN{printf \"%d\", int(${TOTAL_MEM_KB}*0.10/4)}")
    tcp_mem_mid=$(awk "BEGIN{printf \"%d\", int(${TOTAL_MEM_KB}*0.15/4)}")
    tcp_mem_hi=$(awk  "BEGIN{printf \"%d\", int(${TOTAL_MEM_KB}*0.20/4)}")

    # ── 场景差异化参数 ──
    local somaxconn netdev_backlog syn_backlog tw_buckets swappiness \
          dirty_ratio dirty_bg keepalive_time fin_timeout file_max

    case "$SCENE" in
        vps_low)
            # 低配：能跑就行，不追求极致，避免内存压力
            somaxconn=4096;     netdev_backlog=4096;    syn_backlog=4096
            tw_buckets=50000;   swappiness=30;          dirty_ratio=20
            dirty_bg=10;        keepalive_time=600;     fin_timeout=30
            file_max=262144
            ;;
        vps)
            # 普通 VPS：均衡
            somaxconn=32768;    netdev_backlog=32768;   syn_backlog=16384
            tw_buckets=200000;  swappiness=10;          dirty_ratio=15
            dirty_bg=5;         keepalive_time=300;     fin_timeout=10
            file_max=1048576
            ;;
        baremetal)
            # 裸机：激进，榨干性能
            somaxconn=65535;    netdev_backlog=65535;   syn_backlog=32768
            tw_buckets=500000;  swappiness=5;           dirty_ratio=10
            dirty_bg=3;         keepalive_time=120;     fin_timeout=5
            file_max=2097152
            ;;
        *)
            somaxconn=32768;    netdev_backlog=32768;   syn_backlog=16384
            tw_buckets=200000;  swappiness=10;          dirty_ratio=15
            dirty_bg=5;         keepalive_time=300;     fin_timeout=10
            file_max=1048576
            ;;
    esac

    cat > "$SYSCTL_CONF" <<EOF
# ==============================================
# 🌉 Linux 优化 v7.0 - 服务器场景: ${SCENE}
# 生成时间: $(date)
# 环境: $CLOUD | CPU: ${CPU_CORES}核 | 内存: ${TOTAL_MEM_MB}MB
# ==============================================

# ── 网络核心 ──
net.core.somaxconn = ${somaxconn}
net.core.netdev_max_backlog = ${netdev_backlog}
net.core.rmem_default = 262144
net.core.rmem_max = ${rmem_max}
net.core.wmem_default = 262144
net.core.wmem_max = ${wmem_max}
net.core.optmem_max = 65536

# ── TCP 高并发 & 低延迟 ──
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

# ── TCP 缓冲区 ──
net.ipv4.tcp_rmem = 4096 87380 ${rmem_max}
net.ipv4.tcp_wmem = 4096 65536 ${wmem_max}
net.ipv4.tcp_mem = ${tcp_mem_lo} ${tcp_mem_mid} ${tcp_mem_hi}

# ── 拥塞控制 ──
net.core.default_qdisc = ${qdisc}
net.ipv4.tcp_congestion_control = ${cc_algo}

# ── 内存 & CPU ──
vm.swappiness = ${swappiness}
vm.dirty_ratio = ${dirty_ratio}
vm.dirty_background_ratio = ${dirty_bg}
vm.overcommit_memory = 1

# ── 文件描述符 ──
fs.file-max = ${file_max}
fs.nr_open = ${file_max}

# ── 端口范围 ──
net.ipv4.ip_local_port_range = 1024 65535

# ── 安全强化 ──
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
EOF

    if sysctl --system > /tmp/sysctl_out.txt 2>&1; then
        ok "sysctl 参数已全部应用"
    else
        local errs
        errs=$(grep -v "^$\|^Applying\|^#" /tmp/sysctl_out.txt \
               | grep -i "error\|invalid" || true)
        [[ -n "$errs" ]] && while IFS= read -r line; do warn "  $line"; done <<< "$errs"
        ok "sysctl 主要参数已应用（上述警告来自系统既有配置）"
    fi
    rm -f /tmp/sysctl_out.txt

    ok "sysctl 写入完成（场景: $SCENE | cc=$cc_algo | rmem_max=$rmem_max）"
}

# =========================
# ☁  云厂商专项适配（服务器场景）
# =========================
apply_cloud_tuning() {
    [[ "$SCENE" == "router" ]] && return 0
    log_step "云环境专项适配（$CLOUD）"

    case "$CLOUD" in
        AWS)
            sysctl -w net.core.rmem_max=536870912 >/dev/null 2>&1 \
                && ok "AWS: 接收缓冲区扩至 512MB（ENA 高吞吐）" || warn "AWS rmem_max 覆盖失败"
            sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1 \
                && ok "AWS: MTU 探测已启用（防 Jumbo Frame 黑洞）" || true
            ;;
        GCP)
            sysctl -w net.core.netdev_max_backlog=65535 >/dev/null 2>&1 \
                && ok "GCP: netdev_max_backlog=65535" || true
            sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1 || true
            ;;
        Azure)
            sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1 \
                && ok "Azure: TIME_WAIT 复用已确认" || true
            sysctl -w net.ipv4.tcp_fin_timeout=10 >/dev/null 2>&1 || true
            ;;
        Virtualized)
            warn "虚拟化环境：IRQ/队列等硬件级优化可能受限"
            ;;
        BareMetal)
            ok "物理裸机模式：所有优化项全量启用 🚀"
            ;;
        *) warn "未知环境，仅应用通用参数" ;;
    esac
}

# =========================
# 📂 持久化 ulimit
# =========================
apply_ulimit() {
    log_step "持久化进程级 ulimit"

    # 按场景设置 nofile 上限
    local nofile
    case "$SCENE" in
        vps_low) nofile=262144  ;;
        router)  nofile=1048576 ;;
        *)       nofile=2097152 ;;
    esac

    local limits_conf="/etc/security/limits.conf"
    local marker="# linux-optimizer-v7"

    # 幂等：删除旧块再写入
    grep -q "$marker" "$limits_conf" 2>/dev/null \
        && sed -i "/$marker/,/# end-linux-optimizer-v7/d" "$limits_conf" \
        && log "已移除旧版 ulimit 配置"

    cat >> "$limits_conf" <<EOF

$marker
*    soft nofile ${nofile}
*    hard nofile ${nofile}
root soft nofile ${nofile}
root hard nofile ${nofile}
# end-linux-optimizer-v7
EOF

    ulimit -n "$nofile" 2>/dev/null \
        && ok "ulimit -n 已设为 $nofile（当前会话立即生效）" \
        || warn "当前 shell ulimit 设置失败（已写入配置，重登录后生效）"
}

# =========================
# 💿 磁盘 IO 调度器优化
# ──────────────────────────────────────────────────
# 调度器选择策略：
#  - SSD / NVMe → none（或 mq-deadline），绕过不必要的请求重排
#  - HDD        → bfq（公平队列，减少寻道）
#  - 软路由     → none（大部分是 eMMC/SSD，转发不依赖本地 IO）
# =========================
optimize_disk_io() {
    log_step "磁盘 IO 调度器优化"

    local optimized=0
    for disk in /sys/block/*/; do
        local name; name=$(basename "$disk")
        # 跳过非物理磁盘（loop / ram / dm）
        [[ "$name" =~ ^(loop|ram|dm-|md) ]] && continue

        local scheduler_file="${disk}queue/scheduler"
        [[ -f "$scheduler_file" ]] || continue

        local current; current=$(cat "$scheduler_file")
        local rotational=1
        rotational=$(cat "${disk}queue/rotational" 2>/dev/null || echo 1)

        local target_sched
        if [[ "$rotational" -eq 0 ]]; then
            # SSD / NVMe / eMMC
            if echo "$current" | grep -q "none"; then
                target_sched="none"
            elif echo "$current" | grep -q "mq-deadline"; then
                target_sched="mq-deadline"
            else
                target_sched="deadline"
            fi
        else
            # HDD
            if echo "$current" | grep -q "bfq"; then
                target_sched="bfq"
            else
                target_sched="cfq"
            fi
        fi

        echo "$target_sched" > "$scheduler_file" 2>/dev/null \
            && ok "  💿 $name（$([ "$rotational" -eq 0 ] && echo SSD || echo HDD)）→ 调度器: $target_sched" \
            || warn "  💿 $name 调度器设置失败（内核不支持 $target_sched）"
        optimized=$((optimized + 1))
    done

    [[ "$optimized" -eq 0 ]] && warn "未检测到可优化的磁盘设备"
}

# =========================
# 📊 验证关键参数
# =========================
verify_settings() {
    log_step "验证关键参数"

    declare -A checks
    if [[ "$SCENE" == "router" ]]; then
        checks=(
            ["net.ipv4.ip_forward"]="1"
            ["net.ipv6.conf.all.forwarding"]="1"
            ["net.ipv4.tcp_syncookies"]="1"
            ["vm.swappiness"]="20"
        )
    else
        checks=(
            ["net.core.somaxconn"]="$(sysctl -n net.core.somaxconn 2>/dev/null || echo 0)"
            ["net.ipv4.tcp_tw_reuse"]="1"
            ["net.ipv4.tcp_syncookies"]="1"
            ["vm.swappiness"]="$(sysctl -n vm.swappiness 2>/dev/null || echo 0)"
            ["fs.file-max"]="$(sysctl -n fs.file-max 2>/dev/null || echo 0)"
            ["net.ipv4.tcp_fastopen"]="3"
        )
    fi

    local pass=0 fail=0
    for key in "${!checks[@]}"; do
        local expected="${checks[$key]}"
        local actual; actual=$(sysctl -n "$key" 2>/dev/null || echo "N/A")
        if [[ "$actual" == "$expected" ]]; then
            ok "  ✔ $key = $actual"
            pass=$((pass + 1))
        else
            warn "  ✘ $key = $actual（期望: $expected）"
            fail=$((fail + 1))
        fi
    done

    ok "验证完成：通过 ${pass} 项，异常 ${fail} 项"
    [[ "$fail" -gt 0 ]] && warn "异常项可能由内核版本或虚拟化限制导致，请查阅日志"
}

# =========================
# 📊 最终摘要
# =========================
show_summary() {
    local scene_zh
    case "$SCENE" in
        vps_low)   scene_zh="低配 VPS（保守参数）" ;;
        vps)       scene_zh="普通 VPS / 云主机（均衡参数）" ;;
        router)    scene_zh="软路由 / 网关（转发 + NAT 优化）" ;;
        bypass)    scene_zh="旁路由（透明代理 + fq_codel + tproxy）" ;;
        baremetal) scene_zh="裸机服务器（全量激进参数）" ;;
        *)         scene_zh="通用模式" ;;
    esac

    echo
    printf "${CYAN}╔══════════════════════════════════════════════╗${RESET}\n"
    printf "${CYAN}║${GREEN}  🎉 Linux 架构级优化 v7.0 完成！             ${CYAN}║${RESET}\n"
    printf "${CYAN}╠══════════════════════════════════════════════╣${RESET}\n"
    printf "${CYAN}║${RESET}  🎭 优化场景   : %-28s${CYAN}║${RESET}\n" "$scene_zh"
    printf "${CYAN}║${RESET}  ☁  云环境     : %-28s${CYAN}║${RESET}\n" "$CLOUD"
    printf "${CYAN}║${RESET}  🖥️  CPU 核心   : %-28s${CYAN}║${RESET}\n" "${CPU_CORES} 核"
    printf "${CYAN}║${RESET}  💾 物理内存   : %-28s${CYAN}║${RESET}\n" "${TOTAL_MEM_MB}MB"
    printf "${CYAN}║${RESET}  📄 sysctl 配置: %-28s${CYAN}║${RESET}\n" "$SYSCTL_CONF"
    printf "${CYAN}║${RESET}  💾 备份目录   : %-28s${CYAN}║${RESET}\n" "$(basename "$BACKUP_DIR")"
    printf "${CYAN}║${RESET}  📋 日志文件   : %-28s${CYAN}║${RESET}\n" "$LOG_FILE"
    printf "${CYAN}╠══════════════════════════════════════════════╣${RESET}\n"
    printf "${CYAN}║${RESET}  🔄 回滚：cp %s/*.conf /etc/sysctl.d/  ${CYAN}║${RESET}\n" "$(basename "$BACKUP_DIR")"
    printf "${CYAN}║${RESET}           sysctl --system                    ${CYAN}║${RESET}\n"
    printf "${CYAN}╚══════════════════════════════════════════════╝${RESET}\n"
    echo
    warn "⚠️  ulimit 变更需重新登录或重启后对新进程完全生效"
    [[ "$SCENE" == "router" || "$SCENE" == "bypass" ]] && warn "⚠️  conntrack 模块已持久化，重启后自动加载"
    [[ "$SCENE" == "bypass" ]] && warn "⚠️  route_localnet=1 已开启，tproxy 规则可正常工作"
    warn "⚠️  验证持久化：重启后执行 sysctl -a | grep ip_forward（软路由）或 somaxconn"
}

# =========================
# 🚀 主流程
# =========================
main() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║  🌉 Linux 架构级优化工具 v7.0                ║"
    echo "║  全场景自动识别：VPS | 软路由 | 裸机          ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${RESET}"

    preflight_check
    detect_cloud
    detect_scene        # 自动识别场景（router / vps_low / baremetal / vps）
    confirm_action      # 展示检测结果，等待确认

    backup_sysctl

    # ── 场景差异化执行路径 ──
    case "$SCENE" in
        router)
            optimize_irq
            optimize_disk_io
            optimize_router
            apply_ulimit
            ;;
        bypass)
            optimize_irq        # 旁路由也做 IRQ 优化（代理转发有收益）
            optimize_disk_io
            optimize_bypass     # 旁路由专项：tproxy + fq_codel + 小 conntrack 表
            apply_ulimit
            ;;
        vps_low)
            # 低配：只做最核心的，不跑耗时的 NUMA/IRQ/100G
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
