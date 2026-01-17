#!/bin/sh
#====================================================
# 🌉 FRP 自动安装 & 更新脚本（OpenWrt / Linux 兼容）
# 🚀 支持 frps / frpc
# 🟢 彩色日志 + emoji 提示
#====================================================

set -e

TMP_DIR="/tmp/frp_installer"
GITHUB_API="https://api.github.com/repos/fatedier/frp/releases/latest"

#====================
# 彩色输出
#====================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
BOLD="\033[1m"
RESET="\033[0m"

log() {
    case "$1" in
        INFO) echo -e "${BLUE}[ℹ️ INFO]${RESET} $2" ;;
        OK)   echo -e "${GREEN}[✅ OK]${RESET} $2" ;;
        WARN) echo -e "${YELLOW}[⚠️ WARN]${RESET} $2" ;;
        ERR)  echo -e "${RED}[❌ ERR]${RESET} $2" ;;
    esac
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

#====================
# 系统 & 架构检测
#====================
detect_system() {
    if [ -f /etc/openwrt_release ]; then
        IS_OPENWRT=1
        OS_NAME="OpenWrt $(. /etc/openwrt_release && echo ${DISTRIB_RELEASE})"
    else
        IS_OPENWRT=0
        OS_NAME="$(uname -s) $(uname -r)"
    fi
    log INFO "System detected: $OS_NAME"

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) PLATFORM="amd64" ;;
        aarch64) PLATFORM="arm64" ;;
        armv7*|armv6*) PLATFORM="armv7" ;;
        mips*) PLATFORM="mips" ;;
        *) PLATFORM="$ARCH" ;;
    esac
    log INFO "Arch detected: $ARCH -> $PLATFORM"
}

#====================
# 下载工具选择
#====================
detect_fetcher() {
    if command_exists curl; then
        FETCH_CMD="curl -fsSL -o"
    elif command_exists wget; then
        FETCH_CMD="wget -qO"
    elif [ "$IS_OPENWRT" -eq 1 ] && command_exists uclient-fetch; then
        FETCH_CMD="uclient-fetch -O"
    else
        log ERR "No suitable downloader found (curl/wget/uclient-fetch)"
        exit 1
    fi
}

#====================
# 获取最新 FRP 版本
#====================
get_latest_version() {
    log INFO "Fetching latest FRP version..."
    if command_exists curl; then
        LATEST_VERSION=$(curl -s "$GITHUB_API" | grep '"tag_name":' | head -n1 | cut -d'"' -f4)
        log OK "Latest version: $LATEST_VERSION"
    else
        log ERR "curl required to fetch latest version"
        exit 1
    fi
}

#====================
# 下载 FRP
#====================
download_frp() {
    mkdir -p "$TMP_DIR"
    TAR_FILE="$TMP_DIR/frp_${LATEST_VERSION}_linux_${PLATFORM}.tar.gz"
    URL="https://github.com/fatedier/frp/releases/download/${LATEST_VERSION}/$(basename "$TAR_FILE")"
    log INFO "Downloading FRP package..."
    $FETCH_CMD "$TAR_FILE" "$URL"
    log OK "Download completed: $(basename "$TAR_FILE")"
}

#====================
# 安装 FRP
#====================
install_frp() {
    read -rp "Install frps or frpc? [frps/frpc]: " ROLE
    ROLE=$(echo "$ROLE" | tr '[:upper:]' '[:lower:]')
    if [ "$ROLE" != "frps" ] && [ "$ROLE" != "frpc" ]; then
        log ERR "Invalid role"
        exit 1
    fi

    tar -xzf "$TAR_FILE" -C "$TMP_DIR"
    BIN="$TMP_DIR/$ROLE"
    chmod +x "$BIN"
    mv "$BIN" /usr/bin/"$ROLE"

    mkdir -p /etc/frp
    if [ ! -f /etc/frp/${ROLE}.toml ]; then
        cp "$TMP_DIR/${ROLE}.example.toml" /etc/frp/${ROLE}.toml
    fi

    if [ "$IS_OPENWRT" -eq 1 ]; then
        SERVICE_PATH="/etc/init.d/$ROLE"
        cat > "$SERVICE_PATH" <<EOF
#!/bin/sh /etc/rc.common
# FRP $ROLE service
START=99
USE_PROCD=1
start_service() { procd_open_instance; procd_set_param command /usr/bin/$ROLE -c /etc/frp/$ROLE.toml; procd_close_instance; }
EOF
        chmod +x "$SERVICE_PATH"
        /etc/init.d/$ROLE enable
        /etc/init.d/$ROLE restart
    else
        SERVICE_PATH="/etc/systemd/system/$ROLE.service"
        cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=FRP $ROLE Service
After=network.target

[Service]
ExecStart=/usr/bin/$ROLE -c /etc/frp/$ROLE.toml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable "$ROLE"
        systemctl restart "$ROLE"
    fi

    log OK "$ROLE installed and service started!"
}

#====================
# Main
#====================
detect_system
detect_fetcher
get_latest_version
download_frp
install_frp

log OK "🌉 FRP setup completed!"
