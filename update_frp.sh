#!/bin/sh
# ====================================================
# 🌉 FRP 自动安装 & 更新 & 卸载脚本 v2.1
# 支持 OpenWrt / Linux | frps / frpc
# ====================================================
# 使用 /bin/sh 保证 OpenWrt 兼容性（busybox ash）

set -eu

# =========================
# 🎨 彩色日志
# =========================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
RESET="\033[0m"

log() {
    case "$1" in
        INFO) printf "${BLUE}[ℹ️  INFO]${RESET} %s\n" "$2" ;;
        OK)   printf "${GREEN}[✅ OK]${RESET} %s\n"   "$2" ;;
        WARN) printf "${YELLOW}[⚠️  WARN]${RESET} %s\n" "$2" ;;
        ERR)  printf "${RED}[❌ ERR]${RESET} %s\n"   "$2" ;;
        STEP) printf "${CYAN}[🔧 STEP]${RESET} %s\n" "$2" ;;
    esac
}

# 带分隔线的步骤标题
log_step() {
    printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
    log STEP "$1"
    printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# =========================
# 🛡 Root 检查
# =========================
if [ "$(id -u)" -ne 0 ]; then
    log ERR "请使用 root 权限运行此脚本（sudo 或 su）"
    exit 1
fi

# =========================
# 📋 全局变量初始化
# =========================
TMP_DIR="/tmp/frp_installer_$$"        # 用 PID 隔离，防多实例冲突
GITHUB_API="https://api.github.com/repos/fatedier/frp/releases/latest"
GITHUB_RELEASE="https://github.com/fatedier/frp/releases"
IS_OPENWRT=0
PLATFORM=""
FETCH_CMD=""
LATEST_VERSION=""
ROLE=""
ACTION=""                              # install / update / uninstall

# =========================
# 🧹 清理（注册 trap，中途退出也能清理）
# 修复：原版清理函数未注册 trap，Ctrl+C 或中途报错时临时文件残留
# =========================
cleanup() {
    if [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
        log INFO "🧹 临时文件已清理"
    fi
}
trap cleanup EXIT

# =========================
# 🖥 系统检测（OpenWrt / Linux）
# =========================
detect_system() {
    log_step "系统环境检测"
    if [ -f /etc/openwrt_release ]; then
        IS_OPENWRT=1
        DISTRIB_RELEASE=""
        # shellcheck source=/dev/null
        . /etc/openwrt_release
        OS_NAME="OpenWrt ${DISTRIB_RELEASE:-unknown}"
    else
        IS_OPENWRT=0
        OS_NAME="$(uname -s) $(uname -r)"
    fi
    log INFO "🐧 系统: $OS_NAME"
}

# =========================
# 🏗 架构检测
# =========================
detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)        PLATFORM="amd64" ;;
        aarch64)       PLATFORM="arm64" ;;
        armv7*|armv6*) PLATFORM="arm" ;;
        mips64*)       PLATFORM="mips64" ;;
        mips*)         PLATFORM="mips" ;;
        riscv64)       PLATFORM="riscv64" ;;
        *)
            log WARN "⚠️  未知架构 $arch，尝试直接使用原始值"
            PLATFORM="$arch"
            ;;
    esac
    log INFO "🖥  架构: $arch → $PLATFORM"
}

# =========================
# 📥 下载工具选择
# =========================
detect_fetcher() {
    if command_exists curl; then
        FETCH_CMD="curl -fsSL --retry 3 --retry-delay 5 -o"
    elif command_exists wget; then
        FETCH_CMD="wget -q -O"
    elif [ "$IS_OPENWRT" -eq 1 ] && command_exists uclient-fetch; then
        FETCH_CMD="uclient-fetch -O"
    else
        log ERR "❌ 未找到可用下载工具（curl / wget / uclient-fetch）"
        exit 1
    fi
    log INFO "📥 下载工具: $(echo "$FETCH_CMD" | awk '{print $1}')"
}

# =========================
# 🔍 获取最新 FRP 版本
# 修复：原版强依赖 curl（与 detect_fetcher 逻辑不一致），
#       且 GitHub API 在国内常被墙，现增加 HTML 页面解析作为备用通道。
# =========================
get_latest_version() {
    log_step "查询最新 FRP 版本"

    # 通道 1：GitHub API（优先，返回 JSON，解析最稳定）
    if command_exists curl; then
        LATEST_VERSION=$(curl -sf --max-time 10 "$GITHUB_API" \
            | grep '"tag_name":' \
            | head -n1 \
            | cut -d'"' -f4) || true
    fi

    # 通道 2：解析 GitHub releases 页面（API 不可达时的备用方案）
    # 修复：国内访问 GitHub API 经常超时，增加 HTML 解析兜底
    if [ -z "$LATEST_VERSION" ]; then
        log WARN "⚠️  GitHub API 不可达，尝试备用通道解析 releases 页面..."
        if command_exists curl; then
            LATEST_VERSION=$(curl -sf --max-time 15 \
                "$GITHUB_RELEASE/latest" \
                | grep -oE 'fatedier/frp/releases/tag/v[0-9]+\.[0-9]+\.[0-9]+' \
                | head -n1 \
                | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+') || true
        elif command_exists wget; then
            LATEST_VERSION=$(wget -qO- --timeout=15 \
                "$GITHUB_RELEASE/latest" \
                | grep -oE 'fatedier/frp/releases/tag/v[0-9]+\.[0-9]+\.[0-9]+' \
                | head -n1 \
                | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+') || true
        fi
    fi

    if [ -z "$LATEST_VERSION" ]; then
        log ERR "❌ 无法获取 FRP 最新版本号，请检查网络连接"
        exit 1
    fi

    log OK "📌 最新版本: $LATEST_VERSION"
}

# =========================
# 📊 对比当前已安装版本
# 修复：原版每次都全量重装，没有版本对比提示
# =========================
check_installed_version() {
    local installed="未安装"
    if command_exists "$ROLE"; then
        installed=$("$ROLE" --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1) || installed="未知"
    elif [ -f "/usr/bin/$ROLE" ]; then
        installed=$("/usr/bin/$ROLE" --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1) || installed="未知"
    fi

    printf "\n${BLUE}📌 当前版本：${YELLOW}%s${RESET}\n" "$installed"
    printf "${BLUE}📌 最新版本：${GREEN}%s${RESET}\n\n" "$LATEST_VERSION"

    if [ "$installed" = "$LATEST_VERSION" ]; then
        log WARN "⚠️  当前已是最新版本 $LATEST_VERSION"
        printf "❓ 是否仍要重新安装？[y/N]: "
        read -r confirm
        case "$confirm" in
            y|Y) log INFO "继续重新安装..." ;;
            *)   log INFO "👋 已取消"; exit 0 ;;
        esac
    fi
}

# =========================
# 📦 下载 FRP 压缩包（带重试）
# 修复：原版一次失败即退出，改为最多重试 3 次
# =========================
download_frp() {
    log_step "下载 FRP $LATEST_VERSION"
    mkdir -p "$TMP_DIR"

    local ver_plain
    ver_plain="${LATEST_VERSION#v}"     # 去掉 v 前缀，如 v0.61.0 → 0.61.0
    TAR_NAME="frp_${ver_plain}_linux_${PLATFORM}.tar.gz"
    TAR_FILE="$TMP_DIR/$TAR_NAME"
    EXTRACT_DIR="$TMP_DIR/frp_${ver_plain}_linux_${PLATFORM}"
    URL="${GITHUB_RELEASE}/download/${LATEST_VERSION}/${TAR_NAME}"

    log INFO "🔗 下载地址: $URL"

    # 重试最多 3 次
    local attempt=0
    local ok=0
    while [ "$attempt" -lt 3 ]; do
        attempt=$((attempt + 1))
        log INFO "⬇️  第 $attempt 次下载..."
        if $FETCH_CMD "$TAR_FILE" "$URL"; then
            ok=1; break
        fi
        log WARN "第 $attempt 次下载失败，${attempt}0 秒后重试..."
        sleep $((attempt * 10))
    done

    if [ "$ok" -eq 0 ]; then
        log ERR "❌ 下载失败（已重试 3 次），请检查网络或架构是否支持（$PLATFORM）"
        exit 1
    fi

    # 文件完整性校验（busybox wc 输出可能含空格，用 tr 去除）
    # 修复：busybox 的 wc -c 输出格式含前导空格，直接比较会失败
    local size
    size=$(wc -c < "$TAR_FILE" | tr -d ' ')
    if [ "$size" -lt 1024 ]; then
        log ERR "❌ 下载文件异常，体积过小（${size} bytes），可能为错误页面"
        exit 1
    fi

    log OK "✅ 下载完成: $TAR_NAME（${size} bytes）"
}

# =========================
# ⚙️  安装 FRP 二进制及配置
# =========================
install_frp() {
    log_step "安装 $ROLE 二进制"

    log INFO "📂 解压压缩包..."
    tar -xzf "$TAR_FILE" -C "$TMP_DIR" \
        || { log ERR "❌ 解压失败，tar 文件可能不完整"; exit 1; }

    local bin_src="$EXTRACT_DIR/$ROLE"
    if [ ! -f "$bin_src" ]; then
        log ERR "❌ 解压后未找到 $ROLE 二进制: $bin_src"
        log ERR "  当前 PLATFORM=$PLATFORM，请确认架构是否正确"
        exit 1
    fi

    chmod +x "$bin_src"
    mv "$bin_src" "/usr/bin/$ROLE"
    log OK "✅ $ROLE 已安装至 /usr/bin/$ROLE"

    # 安装默认配置（已存在则不覆盖，保护用户配置）
    mkdir -p /etc/frp
    local example_cfg="$EXTRACT_DIR/${ROLE}.toml"
    if [ ! -f "/etc/frp/${ROLE}.toml" ]; then
        if [ -f "$example_cfg" ]; then
            cp "$example_cfg" "/etc/frp/${ROLE}.toml"
            log OK "📄 示例配置已复制至 /etc/frp/${ROLE}.toml"
        else
            log WARN "⚠️  未找到示例配置，请手动创建 /etc/frp/${ROLE}.toml"
        fi
    else
        log WARN "⚠️  /etc/frp/${ROLE}.toml 已存在，跳过覆盖（保留现有配置）"
    fi
}

# =========================
# 🔧 服务注册（OpenWrt init.d / systemd）
# =========================
install_service() {
    log_step "注册系统服务"
    if [ "$IS_OPENWRT" -eq 1 ]; then
        _install_service_openwrt
    elif command_exists systemctl; then
        _install_service_systemd
    else
        log WARN "⚠️  未检测到 systemd 或 OpenWrt init，请手动管理服务"
    fi
}

_install_service_openwrt() {
    local svc="/etc/init.d/$ROLE"
    cat > "$svc" <<EOF
#!/bin/sh /etc/rc.common
# FRP ${ROLE} OpenWrt init.d 服务
START=99
STOP=10
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/$ROLE -c /etc/frp/${ROLE}.toml
    procd_set_param respawn 3600 5 0    # 1小时内最多重启5次，失败计数不重置
    # 修复：补充日志重定向，方便通过 logread 查看 frp 输出
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    killall $ROLE 2>/dev/null || true
}
EOF
    chmod +x "$svc"
    "$svc" enable
    "$svc" start
    log OK "✅ OpenWrt 服务已启动: $ROLE"
    log INFO "  查看日志: logread | grep $ROLE"
}

_install_service_systemd() {
    local unit="/etc/systemd/system/${ROLE}.service"
    cat > "$unit" <<EOF
[Unit]
Description=FRP ${ROLE} - Fast Reverse Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/${ROLE} -c /etc/frp/${ROLE}.toml
Restart=on-failure
RestartSec=5s
# 日志通过 journalctl 收集，无需额外重定向

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$ROLE"
    systemctl restart "$ROLE"

    # 等待服务就绪（最多 10 秒）
    local waited=0
    while [ "$waited" -lt 10 ]; do
        if systemctl is-active --quiet "$ROLE" 2>/dev/null; then
            break
        fi
        sleep 1
        waited=$((waited + 1))
        log INFO "⏳ 等待服务启动... (${waited}s)"
    done

    if systemctl is-active --quiet "$ROLE" 2>/dev/null; then
        log OK "✅ systemd 服务已启动: $ROLE（${waited}s）"
    else
        log ERR "❌ 服务启动失败，最近日志："
        journalctl -u "$ROLE" -n 20 --no-pager || true
        exit 1
    fi
}

# =========================
# 🗑 卸载 FRP
# 修复：原版无卸载功能
# =========================
uninstall_frp() {
    log_step "卸载 $ROLE"

    # 停止并禁用服务
    if [ "$IS_OPENWRT" -eq 1 ]; then
        if [ -f "/etc/init.d/$ROLE" ]; then
            "/etc/init.d/$ROLE" stop 2>/dev/null || true
            "/etc/init.d/$ROLE" disable 2>/dev/null || true
            rm -f "/etc/init.d/$ROLE"
            log OK "✅ OpenWrt 服务已移除"
        fi
    elif command_exists systemctl; then
        if systemctl is-active --quiet "$ROLE" 2>/dev/null; then
            systemctl stop "$ROLE"
        fi
        systemctl disable "$ROLE" 2>/dev/null || true
        rm -f "/etc/systemd/system/${ROLE}.service"
        systemctl daemon-reload
        log OK "✅ systemd 服务已移除"
    fi

    # 删除二进制
    if [ -f "/usr/bin/$ROLE" ]; then
        rm -f "/usr/bin/$ROLE"
        log OK "✅ 二进制 /usr/bin/$ROLE 已删除"
    fi

    # 询问是否保留配置
    printf "\n❓ 是否同时删除配置文件 /etc/frp/${ROLE}.toml？[y/N]: "
    read -r del_cfg
    case "$del_cfg" in
        y|Y)
            rm -f "/etc/frp/${ROLE}.toml"
            # 如果 /etc/frp 目录为空则一并删除
            rmdir /etc/frp 2>/dev/null || true
            log OK "✅ 配置文件已删除"
            ;;
        *)
            log INFO "📄 配置文件已保留: /etc/frp/${ROLE}.toml"
            ;;
    esac

    log OK "🎉 $ROLE 卸载完成"
}

# =========================
# 📊 安装摘要
# =========================
show_summary() {
    local status_cmd
    if [ "$IS_OPENWRT" -eq 1 ]; then
        status_cmd="/etc/init.d/$ROLE status"
    else
        status_cmd="systemctl status $ROLE"
    fi

    printf "\n${CYAN}╔══════════════════════════════════════════════╗${RESET}\n"
    printf "${CYAN}║${GREEN}  🎉 FRP %-6s 安装完成！版本: %-12s${CYAN}║${RESET}\n" "$ROLE" "$LATEST_VERSION"
    printf "${CYAN}╠══════════════════════════════════════════════╣${RESET}\n"
    printf "${CYAN}║${RESET}  📄 配置文件 : /etc/frp/%-20s${CYAN}║${RESET}\n" "${ROLE}.toml"
    printf "${CYAN}║${RESET}  🔧 二进制   : /usr/bin/%-21s${CYAN}║${RESET}\n" "$ROLE"
    printf "${CYAN}╠══════════════════════════════════════════════╣${RESET}\n"
    printf "${CYAN}║${RESET}  🛠  服务管理：                               ${CYAN}║${RESET}\n"
    printf "${CYAN}║${RESET}    状态: %-37s${CYAN}║${RESET}\n" "$status_cmd"
    printf "${CYAN}╚══════════════════════════════════════════════╝${RESET}\n\n"
}

# =========================
# 🚀 主流程
# =========================
main() {
    printf "\n${CYAN}╔══════════════════════════════════════════════╗${RESET}\n"
    printf "${CYAN}║${GREEN}   🌉 FRP 自动安装脚本 v2.1                   ${CYAN}║${RESET}\n"
    printf "${CYAN}║${RESET}   支持 OpenWrt / Linux | frps / frpc          ${CYAN}║${RESET}\n"
    printf "${CYAN}╚══════════════════════════════════════════════╝${RESET}\n\n"

    detect_system
    detect_arch
    detect_fetcher

    # --- 操作选择（提前到主流程，修复原版角色选择埋在 install_frp 里）---
    printf "${YELLOW}📦 请选择操作：${RESET}\n"
    printf "   1️⃣   安装 / 更新 FRP\n"
    printf "   2️⃣   卸载 FRP\n"
    printf "❓ 请输入 [1/2]（默认 1）: "
    read -r action_choice
    action_choice="${action_choice:-1}"

    printf "\n${YELLOW}🎭 请选择角色：${RESET}\n"
    printf "   1️⃣   frps（服务端）\n"
    printf "   2️⃣   frpc（客户端）\n"
    printf "❓ 请输入 [1/2]（默认 2）: "
    read -r role_choice
    role_choice="${role_choice:-2}"

    case "$role_choice" in
        1) ROLE="frps" ;;
        2) ROLE="frpc" ;;
        *)
            log ERR "❌ 无效输入，请输入 1 或 2"
            exit 1
            ;;
    esac
    log INFO "🎭 角色: $ROLE"

    case "$action_choice" in
        2)
            # 卸载流程
            ACTION="uninstall"
            printf "\n${RED}⚠️  即将卸载 $ROLE，是否确认？[y/N]: ${RESET}"
            read -r confirm
            case "$confirm" in
                y|Y) uninstall_frp ;;
                *)   log INFO "👋 已取消"; exit 0 ;;
            esac
            ;;
        *)
            # 安装 / 更新流程
            ACTION="install"
            get_latest_version
            check_installed_version
            download_frp
            install_frp
            install_service
            show_summary
            ;;
    esac
}

main "$@"
