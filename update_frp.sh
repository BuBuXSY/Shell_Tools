#!/bin/bash
#!/bin/sh
#====================================================
# FRP 自动安装 & 更新脚本（去 SHA256 校验版）
# 支持 OpenWrt / Linux
# 自动下载最新版本，支持 frps / frpc
# 🌉 FRP 自动安装 & 更新脚本（OpenWrt / Linux 兼容）
# 🚀 支持 frps / frpc
# 🟢 彩色日志 + emoji 提示
#====================================================

set -euo pipefail
set -e

TMP_DIR="/tmp/frp_installer"
GITHUB_RELEASES="https://github.com/fatedier/frp/releases"
GITHUB_API="https://api.github.com/repos/fatedier/frp/releases/latest"

log() { echo -e "[$1] $2"; }
command_exists() { command -v "$1" >/dev/null 2>&1; }
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

detect_openwrt() {
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
    log "INFO" "System detected: $OS_NAME"
}
    log INFO "System detected: $OS_NAME"

detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) PLATFORM="amd64" ;;
        aarch64) PLATFORM="arm64" ;;
        armv7*|armv6*) PLATFORM="armv7" ;;
        mips*) PLATFORM="mips" ;;
        *) PLATFORM="$arch" ;;
        *) PLATFORM="$ARCH" ;;
    esac
    log "INFO" "Arch detected: $arch -> $PLATFORM"
    log INFO "Arch detected: $ARCH -> $PLATFORM"
}

#====================
# 下载工具选择
#====================
detect_fetcher() {
    if command_exists curl; then
        FETCH_CMD="curl -fsSL -o"
@@ -45,37 +68,45 @@ detect_fetcher() {
    elif [ "$IS_OPENWRT" -eq 1 ] && command_exists uclient-fetch; then
        FETCH_CMD="uclient-fetch -O"
    else
        log "ERR" "No suitable downloader found (curl/wget/uclient-fetch)"
        log ERR "No suitable downloader found (curl/wget/uclient-fetch)"
        exit 1
    fi
}

#====================
# 获取最新 FRP 版本
#====================
get_latest_version() {
    log "INFO" "Fetching latest FRP version..."
    # 使用 GitHub API 获取最新 release tag
    log INFO "Fetching latest FRP version..."
    if command_exists curl; then
        LATEST_VERSION="$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')"
        LATEST_VERSION=$(curl -s "$GITHUB_API" | grep '"tag_name":' | head -n1 | cut -d'"' -f4)
        log OK "Latest version: $LATEST_VERSION"
    else
        log "ERR" "curl required to fetch latest version"
        log ERR "curl required to fetch latest version"
        exit 1
    fi
    log "OK" "Latest version: $LATEST_VERSION"
}

#====================
# 下载 FRP
#====================
download_frp() {
    mkdir -p "$TMP_DIR"
    TAR_FILE="$TMP_DIR/frp_${LATEST_VERSION}_linux_${PLATFORM}.tar.gz"
    URL="$GITHUB_RELEASES/download/$LATEST_VERSION/$(basename "$TAR_FILE")"
    log "INFO" "Downloading FRP package..."
    URL="https://github.com/fatedier/frp/releases/download/${LATEST_VERSION}/$(basename "$TAR_FILE")"
    log INFO "Downloading FRP package..."
    $FETCH_CMD "$TAR_FILE" "$URL"
    log "OK" "Download completed: $(basename "$TAR_FILE")"
    log OK "Download completed: $(basename "$TAR_FILE")"
}

#====================
# 安装 FRP
#====================
install_frp() {
    read -rp "Install frps or frpc? [frps/frpc]: " ROLE
    ROLE="${ROLE,,}"
    if [[ "$ROLE" != "frps" && "$ROLE" != "frpc" ]]; then
        log "ERR" "Invalid role"
    ROLE=$(echo "$ROLE" | tr '[:upper:]' '[:lower:]')
    if [ "$ROLE" != "frps" ] && [ "$ROLE" != "frpc" ]; then
        log ERR "Invalid role"
        exit 1
    fi

@@ -84,13 +115,11 @@ install_frp() {
    chmod +x "$BIN"
    mv "$BIN" /usr/bin/"$ROLE"

    # 默认配置目录
    mkdir -p /etc/frp
    if [ ! -f /etc/frp/${ROLE}.toml ]; then
        cp "$TMP_DIR/${ROLE}.example.toml" /etc/frp/${ROLE}.toml
    fi

    # 创建服务
    if [ "$IS_OPENWRT" -eq 1 ]; then
        SERVICE_PATH="/etc/init.d/$ROLE"
        cat > "$SERVICE_PATH" <<EOF
@@ -122,17 +151,16 @@ EOF
        systemctl restart "$ROLE"
    fi

    log "OK" "$ROLE installed and service started!"
    log OK "$ROLE installed and service started!"
}

#====================
# Main
#====================
detect_openwrt
detect_arch
detect_system
detect_fetcher
get_latest_version
download_frp
install_frp

log "OK" "FRP setup completed!"
log OK "🌉 FRP setup completed!"
