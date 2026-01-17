#!/bin/bash
# FRP Installer / Upgrader (Linux & OpenWrt)
# - procd fixed
# - SHA256 verified
# - ShellCheck clean
# By: BuBuXSY
# License: MIT

set -Eeuo pipefail

# ================== 常量 ==================
INSTALL_DIR="/usr/bin"
TMP_DIR="/tmp/frp_installer"
GITHUB_API="https://api.github.com/repos/fatedier/frp/releases/latest"
GITHUB_RELEASES="https://github.com/fatedier/frp/releases"

# ================== 颜色 ==================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

INFO="${CYAN}[INFO]${RESET}"
OK="${GREEN}[OK]${RESET}"
WARN="${YELLOW}[WARN]${RESET}"
ERR="${RED}[ERR]${RESET}"

log() { printf "%b %s\n" "$1" "$2" >&2; }

trap 'rm -rf "$TMP_DIR"' EXIT

# ================== 全局 ==================
IS_OPENWRT=false
OPENWRT_RELEASE=""
ARCH=""
PLATFORM=""
LATEST_VERSION=""
FETCH_CMD=""
SUDO=""

# ================== 工具 ==================
command_exists() { command -v "$1" >/dev/null 2>&1; }

# ================== OpenWrt ==================
detect_openwrt() {
    if [[ -f /etc/openwrt_release ]]; then
        IS_OPENWRT=true
        OPENWRT_RELEASE="$(grep DISTRIB_RELEASE /etc/openwrt_release | cut -d"'" -f2)"
        log "$INFO" "OpenWrt detected: $OPENWRT_RELEASE"
    fi
}

# ================== 权限 ==================
check_privilege() {
    if "$IS_OPENWRT"; then
        [[ $EUID -eq 0 ]] || { log "$ERR" "Need root on OpenWrt"; exit 1; }
        SUDO=""
    else
        SUDO="sudo"
        sudo -v
    fi
}

# ================== 架构 ==================
detect_arch() {
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64) PLATFORM="amd64" ;;
        aarch64|arm64) PLATFORM="arm64" ;;
        armv7l|armv6l) PLATFORM="arm" ;;
        mipsel|mips) PLATFORM="mipsle" ;;
        mips64el|mips64) PLATFORM="mips64le" ;;
        *) log "$ERR" "Unsupported arch: $ARCH"; exit 1 ;;
    esac
    log "$INFO" "Arch: $ARCH -> $PLATFORM"
}

# ================== 下载器 ==================
detect_fetcher() {
    if "$IS_OPENWRT"; then
        if command_exists uclient-fetch; then
            FETCH_CMD="uclient-fetch -O"
        elif command_exists wget; then
            FETCH_CMD="wget -O"
        else
            log "$ERR" "No downloader available"
            exit 1
        fi
    else
        if command_exists curl; then
            FETCH_CMD="curl -L --fail -o"
        elif command_exists wget; then
            FETCH_CMD="wget -O"
        else
            log "$ERR" "No downloader available"
            exit 1
        fi
    fi
}

# ================== 版本 ==================
get_latest_version() {
    log "$INFO" "Fetching latest FRP version..."
    LATEST_VERSION="$(curl -fsSL "$GITHUB_API" | grep tag_name | cut -d\" -f4 | sed 's/^v//')"
    [[ -n "$LATEST_VERSION" ]] || { log "$ERR" "Failed to get version"; exit 1; }
    log "$OK" "Latest: $LATEST_VERSION"
}

# ================== 下载 + 校验 ==================
download_and_verify() {
    mkdir -p "$TMP_DIR"

    local tar="frp_${LATEST_VERSION}_linux_${PLATFORM}.tar.gz"
    local url="$GITHUB_RELEASES/download/v${LATEST_VERSION}/$tar"

    log "$INFO" "Downloading FRP package..."
    $FETCH_CMD "$TMP_DIR/$tar" "$url"

    # 自动抓 SHA256
    if command_exists sha256sum && command_exists curl && command_exists grep && command_exists awk; then
        log "$INFO" "Fetching SHA256 from GitHub Release page..."

        local sha_page
        sha_page="$(curl -fsSL "$GITHUB_RELEASES/releases/tag/v$LATEST_VERSION")"

        # HTML 解析: 找到对应 tar.gz 链接前面的 SHA256
        local sha
        sha="$(echo "$sha_page" | grep -A2 "$tar" | grep -oE '[a-f0-9]{64}' | head -n1)"

        if [[ -z "$sha" ]]; then
            log "$WARN" "Cannot parse SHA256 from release page, skipping verification"
        else
            log "$INFO" "SHA256 from release page: $sha"
            echo "$sha  $TMP_DIR/$tar" | sha256sum -c -
            if [[ $? -ne 0 ]]; then
                log "$ERR" "SHA256 verification failed!"
                exit 1
            else
                log "$OK" "SHA256 verified"
            fi
        fi
    else
        log "$WARN" "sha256sum/curl/grep/awk not available, skip verification"
    fi
}

# ================== 安装 ==================
install_bin() {
    local type="$1"

    tar -xzf "$TMP_DIR"/frp_*.tar.gz -C "$TMP_DIR"
    local src
    src="$(find "$TMP_DIR" -type f -name "$type" | head -n1)"

    [[ -f "$src" ]] || { log "$ERR" "Binary not found: $type"; exit 1; }

    $SUDO cp "$src" "$INSTALL_DIR/$type"
    $SUDO chmod +x "$INSTALL_DIR/$type"
    "$INSTALL_DIR/$type" --version >/dev/null

    log "$OK" "$type installed"
}

# ================== OpenWrt procd ==================
create_procd_service() {
    local type="$1"

    log "$INFO" "Creating procd service"
    mkdir -p /etc/frp

    cat > "/etc/init.d/$type" <<EOF
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=90
STOP=10

PROG="$INSTALL_DIR/$type"
CONF="/etc/frp/$type.toml"

start_service() {
    procd_open_instance
    procd_set_param command "\$PROG" -c "\$CONF"
    procd_set_param file "\$PROG"
    procd_set_param respawn 3600 5 5
    procd_close_instance
}
EOF

    chmod +x "/etc/init.d/$type"

    if [[ ! -f "/etc/frp/$type.toml" ]]; then
        cat > "/etc/frp/$type.toml" <<EOF
# $type.toml
$( [[ "$type" == "frps" ]] && echo "bindPort = 7000" || echo "serverAddr = \"YOUR_SERVER_IP\"\nserverPort = 7000" )
EOF
    fi

    /etc/init.d/"$type" enable
    /etc/init.d/"$type" restart
}

# ================== systemd ==================
create_systemd_service() {
    local type="$1"

    log "$INFO" "Creating systemd service"

    sudo mkdir -p /etc/frp
    sudo tee "/etc/systemd/system/$type.service" >/dev/null <<EOF
[Unit]
Description=FRP $type
After=network.target

[Service]
ExecStart=$INSTALL_DIR/$type -c /etc/frp/$type.toml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "$type"
    sudo systemctl restart "$type"
}

# ================== 主流程 ==================
main() {
    detect_openwrt
    check_privilege
    detect_arch
    detect_fetcher
    get_latest_version
    download_and_verify

    printf "Install which? (frps/frpc): "
    read -r TYPE
    [[ "$TYPE" == "frps" || "$TYPE" == "frpc" ]] || exit 1

    install_bin "$TYPE"

    if "$IS_OPENWRT"; then
        create_procd_service "$TYPE"
        /etc/init.d/"$TYPE" status || true
    else
        create_systemd_service "$TYPE"
        systemctl status "$TYPE" --no-pager || true
    fi

    log "$OK" "All done"
}

main "$@"
