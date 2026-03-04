#!/bin/sh
#====================================================
# 🌉 FRP 自动安装 & 更新脚本（OpenWrt / Linux 兼容）
# 🚀 支持 frps / frpc | 修复了 404 及路径匹配问题
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
        i386|i686) PLATFORM="386" ;;
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
        log ERR "No downloader found (curl/wget/uclient-fetch)"
        exit 1
    fi
}

#====================
# 获取最新 FRP 版本
#====================
get_latest_version() {
    log INFO "Fetching latest FRP version..."
    # 提取 Tag 名
    LATEST_TAG=$(curl -s "$GITHUB_API" | grep '"tag_name":' | head -n1 | cut -d'"' -f4)
    if [ -z "$LATEST_TAG" ]; then
        log ERR "Failed to fetch version from GitHub API"
        exit 1
    fi
    # 提取纯数字版本号 用于文件名拼接
    LATEST_VER_NUM=$(echo "$LATEST_TAG" | sed 's/^v//')
    log OK "Latest version found: $LATEST_TAG"
}

#====================
# 下载 FRP
#====================
download_frp() {
    rm -rf "$TMP_DIR" && mkdir -p "$TMP_DIR"
    # 文件名不带 v，但下载路径的 Tag 带 v
    FILE_NAME="frp_${LATEST_VER_NUM}_linux_${PLATFORM}.tar.gz"
    TAR_FILE="$TMP_DIR/$FILE_NAME"
    URL="https://github.com/fatedier/frp/releases/download/${LATEST_TAG}/${FILE_NAME}"
    
    log INFO "Downloading from: $URL"
    if ! $FETCH_CMD "$TAR_FILE" "$URL"; then
        log ERR "Download failed! Please check your network or architecture."
        exit 1
    fi
    log OK "Download completed."
}

#====================
# 安装 FRP
#====================
install_frp() {
    printf "${YELLOW}[?] Install frps (Server) or frpc (Client)? [frps/frpc]: ${RESET}"
    read -r ROLE
    ROLE=$(echo "$ROLE" | tr '[:upper:]' '[:lower:]')
    
    if [ "$ROLE" != "frps" ] && [ "$ROLE" != "frpc" ]; then
        log ERR "Invalid role: $ROLE. Use 'frps' or 'frpc'."
        exit 1
    fi

    log INFO "Extracting package..."
    # --strip-components=1 直接把文件夹里的内容解压出来，不保留那层带版本号的目录
    tar -xzf "$TAR_FILE" -C "$TMP_DIR" --strip-components=1

    BIN_SRC="$TMP_DIR/$ROLE"
    if [ ! -f "$BIN_SRC" ]; then
        log ERR "Binary $ROLE not found in extracted files."
        exit 1
    fi

    chmod +x "$BIN_SRC"
    mv "$BIN_SRC" /usr/bin/"$ROLE"
    log OK "Binary moved to /usr/bin/$ROLE"

    # 配置文件处理
    mkdir -p /etc/frp
    # 优先找 .toml (新版)，找不到再找旧版的 .ini (兼容旧版本包)
    CONF_EXAMPLE=""
    [ -f "$TMP_DIR/${ROLE}.toml" ] && CONF_EXAMPLE="$TMP_DIR/${ROLE}.toml"
    [ -f "$TMP_DIR/${ROLE}.ini" ] && [ -z "$CONF_EXAMPLE" ] && CONF_EXAMPLE="$TMP_DIR/${ROLE}.ini"

    CONF_DEST="/etc/frp/${ROLE}.toml"
    # 如果是旧版 .ini 后缀
    if echo "$CONF_EXAMPLE" | grep -q "\.ini$"; then CONF_DEST="/etc/frp/${ROLE}.ini"; fi

    if [ ! -f "$CONF_DEST" ]; then
        cp "$CONF_EXAMPLE" "$CONF_DEST"
        log OK "Created default config at $CONF_DEST"
    else
        log WARN "Config $CONF_DEST already exists, skipping overwrite."
    fi

    #====================
    # 服务启动逻辑
    #====================
    if [ "$IS_OPENWRT" -eq 1 ]; then
        SERVICE_PATH="/etc/init.d/$ROLE"
        log INFO "Configuring OpenWrt procd service..."
        cat > "$SERVICE_PATH" <<EOF
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/$ROLE -c $CONF_DEST
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
        chmod +x "$SERVICE_PATH"
        /etc/init.d/$ROLE enable
        /etc/init.d/$ROLE restart
    else
        SERVICE_PATH="/etc/systemd/system/$ROLE.service"
        log INFO "Configuring Systemd service..."
        cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=FRP $ROLE Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/$ROLE -c $CONF_DEST
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable "$ROLE"
        systemctl restart "$ROLE"
    fi

    log OK "$ROLE Service is now running!"
}

#====================
# Main Execution
#====================
clear
echo -e "${BOLD}${BLUE}🌉 FRP Auto Installer / Updater${RESET}"
echo "------------------------------------------------"

detect_system
detect_fetcher
get_latest_version
download_frp
install_frp

echo "------------------------------------------------"
log OK "FRP setup completed! Enjoy your tunnel."
