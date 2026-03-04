#!/bin/sh
# ====================================================
# 🌉 FRP 自动安装 & 更新脚本 v2.0
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
RESET="\033[0m"

log() {
    case "$1" in
        INFO) printf "${BLUE}[ℹ INFO]${RESET} %s\n" "$2" ;;
        OK)   printf "${GREEN}[✓ OK]${RESET} %s\n"   "$2" ;;
        WARN) printf "${YELLOW}[! WARN]${RESET} %s\n" "$2" ;;
        ERR)  printf "${RED}[✗ ERR]${RESET} %s\n"   "$2" ;;
    esac
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# =========================
# 🛡 Root 检查
# =========================
if [ "$(id -u)" -ne 0 ]; then
    log ERR "请使用 root 权限运行此脚本"
    exit 1
fi

# =========================
# 变量初始化
# =========================
TMP_DIR="/tmp/frp_installer"
GITHUB_API="https://api.github.com/repos/fatedier/frp/releases/latest"
IS_OPENWRT=0
PLATFORM=""
FETCH_CMD=""
LATEST_VERSION=""
ROLE=""

# =========================
# 🖥 系统检测（OpenWrt / Linux 合并）
# =========================
detect_system() {
    if [ -f /etc/openwrt_release ]; then
        IS_OPENWRT=1
        # 兼容 busybox：用点命令 source
        # shellcheck source=/dev/null
        DISTRIB_RELEASE=""
        . /etc/openwrt_release
        OS_NAME="OpenWrt ${DISTRIB_RELEASE:-unknown}"
    else
        IS_OPENWRT=0
        OS_NAME="$(uname -s) $(uname -r)"
    fi
    log INFO "系统检测: $OS_NAME"
}

# =========================
# 🏗 架构检测
# =========================
detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)          PLATFORM="amd64" ;;
        aarch64)         PLATFORM="arm64" ;;
        armv7*|armv6*)   PLATFORM="arm" ;;
        mips64*)         PLATFORM="mips64" ;;
        mips*)           PLATFORM="mips" ;;
        riscv64)         PLATFORM="riscv64" ;;
        *)
            log WARN "未知架构 $arch，尝试直接使用原始值"
            PLATFORM="$arch"
            ;;
    esac
    log INFO "架构检测: $arch → $PLATFORM"
}

# =========================
# 📥 下载工具选择
# =========================
detect_fetcher() {
    if command_exists curl; then
        FETCH_CMD="curl -fsSL -o"
    elif command_exists wget; then
        FETCH_CMD="wget -q -O"
    elif [ "$IS_OPENWRT" -eq 1 ] && command_exists uclient-fetch; then
        FETCH_CMD="uclient-fetch -O"
    else
        log ERR "未找到可用下载工具（curl / wget / uclient-fetch）"
        exit 1
    fi
    log INFO "下载工具: $(echo "$FETCH_CMD" | awk '{print $1}')"
}

# =========================
# 🔍 获取最新 FRP 版本
# =========================
get_latest_version() {
    log INFO "正在查询最新 FRP 版本..."

    if ! command_exists curl; then
        log ERR "获取版本号需要 curl"
        exit 1
    fi

    # 用 cut 解析 JSON，避免依赖 grep -P（OpenWrt 不支持）
    LATEST_VERSION=$(curl -sf "$GITHUB_API" \
        | grep '"tag_name":' \
        | head -n1 \
        | cut -d'"' -f4)

    if [ -z "$LATEST_VERSION" ]; then
        log ERR "无法获取版本号，请检查网络或 GitHub API 访问"
        exit 1
    fi

    log OK "最新版本: $LATEST_VERSION"
}

# =========================
# 📦 下载 FRP 压缩包
# =========================
download_frp() {
    mkdir -p "$TMP_DIR"

    # LATEST_VERSION 格式为 "v0.xx.x"，GitHub 资产文件名去掉 v 前缀
    local ver_plain
    ver_plain="${LATEST_VERSION#v}"

    TAR_NAME="frp_${ver_plain}_linux_${PLATFORM}.tar.gz"
    TAR_FILE="$TMP_DIR/$TAR_NAME"
    URL="https://github.com/fatedier/frp/releases/download/${LATEST_VERSION}/${TAR_NAME}"

    log INFO "下载地址: $URL"

    if ! $FETCH_CMD "$TAR_FILE" "$URL"; then
        log ERR "下载失败，请检查网络或架构是否正确（$PLATFORM）"
        exit 1
    fi

    # 验证文件完整性（基础大小检查）
    local size
    size=$(wc -c < "$TAR_FILE")
    if [ "$size" -lt 1024 ]; then
        log ERR "下载文件过小（${size} bytes），可能下载失败"
        exit 1
    fi

    log OK "下载完成: $TAR_NAME (${size} bytes)"
}

# =========================
# ⚙ 安装 FRP 二进制
# =========================
install_frp() {
    # 选择角色
    printf "安装 frps 还是 frpc？[frps/frpc]: "
    read -r ROLE
    ROLE=$(echo "$ROLE" | tr '[:upper:]' '[:lower:]')
    if [ "$ROLE" != "frps" ] && [ "$ROLE" != "frpc" ]; then
        log ERR "无效输入，请输入 frps 或 frpc"
        exit 1
    fi

    log INFO "正在解压..."
    local ver_plain
    ver_plain="${LATEST_VERSION#v}"
    local extract_dir="$TMP_DIR/frp_${ver_plain}_linux_${PLATFORM}"

    tar -xzf "$TAR_FILE" -C "$TMP_DIR"

    local bin_src="$extract_dir/$ROLE"
    if [ ! -f "$bin_src" ]; then
        log ERR "解压后未找到 $ROLE 二进制文件：$bin_src"
        exit 1
    fi

    chmod +x "$bin_src"
    mv "$bin_src" "/usr/bin/$ROLE"
    log OK "$ROLE 已安装至 /usr/bin/$ROLE"

    # 默认配置
    mkdir -p /etc/frp
    local example_cfg="$extract_dir/${ROLE}.toml"
    if [ ! -f "/etc/frp/${ROLE}.toml" ]; then
        if [ -f "$example_cfg" ]; then
            cp "$example_cfg" "/etc/frp/${ROLE}.toml"
            log OK "示例配置已复制至 /etc/frp/${ROLE}.toml"
        else
            log WARN "未找到示例配置文件，请手动创建 /etc/frp/${ROLE}.toml"
        fi
    else
        log WARN "/etc/frp/${ROLE}.toml 已存在，跳过覆盖"
    fi

    # 注册服务
    _install_service
}

# =========================
# 🔧 服务注册（OpenWrt init.d / systemd）
# =========================
_install_service() {
    if [ "$IS_OPENWRT" -eq 1 ]; then
        _install_service_openwrt
    elif command_exists systemctl; then
        _install_service_systemd
    else
        log WARN "未检测到 systemd / OpenWrt init，请手动管理服务"
    fi
}

_install_service_openwrt() {
    local svc="/etc/init.d/$ROLE"
    cat > "$svc" <<EOF
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/$ROLE -c /etc/frp/${ROLE}.toml
    procd_set_param respawn
    procd_close_instance
}
EOF
    chmod +x "$svc"
    "$svc" enable
    "$svc" start
    log OK "OpenWrt 服务已启动: $ROLE"
}

_install_service_systemd() {
    local unit="/etc/systemd/system/${ROLE}.service"
    cat > "$unit" <<EOF
[Unit]
Description=FRP ${ROLE}
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/${ROLE} -c /etc/frp/${ROLE}.toml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$ROLE"
    systemctl restart "$ROLE"
    log OK "systemd 服务已启动: $ROLE"
}

# =========================
# 🧹 清理临时文件
# =========================
cleanup() {
    rm -rf "$TMP_DIR"
    log INFO "临时文件已清理"
}

# =========================
# 🚀 主流程
# =========================
main() {
    printf "\n"
    printf "================================================\n"
    printf "   🌉 FRP 自动安装脚本 v2.0\n"
    printf "================================================\n\n"

    detect_system
    detect_arch
    detect_fetcher
    get_latest_version
    download_frp
    install_frp
    cleanup

    log OK "🎉 FRP 安装完成！版本: $LATEST_VERSION | 角色: $ROLE"
    printf "\n配置文件: /etc/frp/%s.toml\n" "$ROLE"
    printf "查看状态: %s\n\n" "$([ "$IS_OPENWRT" -eq 1 ] && echo "/etc/init.d/$ROLE status" || echo "systemctl status $ROLE")"
}

main "$@"
