#!/bin/sh
#====================================================
# 🌉 FRP 自动安装 & 更新脚本（OpenWrt / Linux 兼容）
# 🚀 支持 1/2 数字快捷选择 | 自动识别架构 | 中文彩色版
#====================================================

set -e

TMP_DIR="/tmp/frp_installer"
GITHUB_API="https://api.github.com/repos/fatedier/frp/releases/latest"

#====================
# 彩色输出颜色定义
#====================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
PURPLE="\033[35m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

log() {
    case "$1" in
        INFO) echo -e "${CYAN}[ℹ️ 信息]${RESET} $2" ;;
        OK)   echo -e "${GREEN}[✅ 成功]${RESET} $2" ;;
        WARN) echo -e "${YELLOW}[⚠️ 警告]${RESET} $2" ;;
        ERR)  echo -e "${RED}[❌ 错误]${RESET} $2" ;;
        STEP) echo -e "${PURPLE}==>${RESET} ${BOLD}$2${RESET}" ;;
    esac
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

#====================
# 系统 & 架构检测
#====================
detect_system() {
    log STEP "正在检测系统环境..."
    if [ -f /etc/openwrt_release ]; then
        IS_OPENWRT=1
        OS_NAME="OpenWrt $(. /etc/openwrt_release && echo ${DISTRIB_RELEASE})"
    else
        IS_OPENWRT=0
        OS_NAME="$(uname -s) $(uname -r)"
    fi
    log INFO "系统: $OS_NAME"

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) PLATFORM="amd64" ;;
        aarch64) PLATFORM="arm64" ;;
        armv7*|armv6*) PLATFORM="armv7" ;;
        mips*) PLATFORM="mips" ;;
        i386|i686) PLATFORM="386" ;;
        *) PLATFORM="$ARCH" ;;
    esac
    log INFO "架构: $ARCH -> $PLATFORM"
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
        log ERR "未找到下载工具 (curl/wget/uclient-fetch)"
        exit 1
    fi
}

#====================
# 获取最新版本
#====================
get_latest_version() {
    log STEP "获取 FRP 最新版本号..."
    LATEST_TAG=$(curl -s "$GITHUB_API" | grep '"tag_name":' | head -n1 | cut -d'"' -f4)
    if [ -z "$LATEST_TAG" ]; then
        log ERR "无法获取版本号，请检查网络是否能访问 GitHub"
        exit 1
    fi
    LATEST_VER_NUM=$(echo "$LATEST_TAG" | sed 's/^v//')
    log OK "最新版本: $LATEST_TAG"
}

#====================
# 执行安装逻辑
#====================
install_process() {
    # 1. 角色选择
    echo -e "\n${BOLD}请选择要安装的角色：${RESET}"
    echo -e "  ${GREEN}1)${RESET} ${BOLD}frpc${RESET} (客户端 - 用于内网穿透出往外走)"
    echo -e "  ${BLUE}2)${RESET} ${BOLD}frps${RESET} (服务端 - 拥有公网IP的服务器)"
    echo -n -e "${YELLOW}请输入数字 [1-2]: ${RESET}"
    read -r CHOICE

    case "$CHOICE" in
        1) ROLE="frpc" ;;
        2) ROLE="frps" ;;
        *) log ERR "输入无效，脚本退出"; exit 1 ;;
    esac

    log INFO "已选择角色: $ROLE"

    # 2. 下载
    rm -rf "$TMP_DIR" && mkdir -p "$TMP_DIR"
    FILE_NAME="frp_${LATEST_VER_NUM}_linux_${PLATFORM}.tar.gz"
    TAR_FILE="$TMP_DIR/$FILE_NAME"
    URL="https://github.com/fatedier/frp/releases/download/${LATEST_TAG}/${FILE_NAME}"
    
    log STEP "正在下载安装包..."
    if ! $FETCH_CMD "$TAR_FILE" "$URL"; then
        log ERR "下载失败，请检查架构 $PLATFORM 是否正确或网络是否波动"
        exit 1
    fi

    # 3. 解压与部署
    log STEP "解压并移动二进制文件..."
    tar -xzf "$TAR_FILE" -C "$TMP_DIR" --strip-components=1
    
    if [ ! -f "$TMP_DIR/$ROLE" ]; then
        log ERR "解压包中未找到 $ROLE 二进制文件"
        exit 1
    fi

    chmod +x "$TMP_DIR/$ROLE"
    mv "$TMP_DIR/$ROLE" /usr/bin/"$ROLE"

    # 4. 配置文件 (不覆盖已有配置)
    mkdir -p /etc/frp
    CONF_EXT="toml"
    # 自动识别包里是 toml 还是 ini
    [ ! -f "$TMP_DIR/${ROLE}.toml" ] && [ -f "$TMP_DIR/${ROLE}.ini" ] && CONF_EXT="ini"
    
    CONF_PATH="/etc/frp/${ROLE}.${CONF_EXT}"
    if [ ! -f "$CONF_PATH" ]; then
        cp "$TMP_DIR/${ROLE}.${CONF_EXT}" "$CONF_PATH"
        log OK "初始配置文件已创建: $CONF_PATH"
    else
        log WARN "配置文件 $CONF_PATH 已存在，已跳过，防止覆盖你的原有设置"
    fi

    # 5. 启动服务
    if [ "$IS_OPENWRT" -eq 1 ]; then
        log STEP "配置 OpenWrt 启动服务..."
        INIT_FILE="/etc/init.d/$ROLE"
        cat > "$INIT_FILE" <<EOF
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/$ROLE -c $CONF_PATH
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
        chmod +x "$INIT_FILE"
        $INIT_FILE enable
        $INIT_FILE restart
    else
        log STEP "配置 Systemd 启动服务..."
        SYSTEMD_FILE="/etc/systemd/system/$ROLE.service"
        cat > "$SYSTEMD_FILE" <<EOF
[Unit]
Description=FRP $ROLE Service
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/$ROLE -c $CONF_PATH
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable "$ROLE"
        systemctl restart "$ROLE"
    fi
}

#====================
# 主程序
#====================
clear
echo -e "${CYAN}${BOLD}================================================${RESET}"
echo -e "${CYAN}${BOLD}    🌉 FRP 自动安装/更新工具 (OpenWrt/Linux)    ${RESET}"
echo -e "${CYAN}${BOLD}================================================${RESET}"

detect_system
detect_fetcher
get_latest_version
install_process

echo -e "\n${GREEN}${BOLD}✨ 所有操作已完成！${RESET}"
echo -e "${YELLOW}提示：${RESET}如需修改配置，请输入: ${CYAN}vi /etc/frp/frp${ROLE: -1}.${CONF_EXT:-toml}${RESET}"
echo -e "------------------------------------------------"
