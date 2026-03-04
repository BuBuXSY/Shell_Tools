#!/bin/bash
#====================================================
# 🌉 FRP 全平台自动安装/更新 & 智能路径修正工具
# 🚀 支持: OpenWrt, Ubuntu, RedHat, Arch, macOS
#====================================================

set -e

TMP_DIR="/tmp/frp_installer"
GITHUB_API="https://api.github.com/repos/fatedier/frp/releases/latest"

# 颜色定义
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[34m"; 
CYAN="\033[36m"; BOLD="\033[1m"; RESET="\033[0m";

log() {
    case "$1" in
        INFO) echo -e "${CYAN}[ℹ️ 信息]${RESET} $2" ;;
        OK)   echo -e "${GREEN}[✅ 成功]${RESET} $2" ;;
        WARN) echo -e "${YELLOW}[⚠️ 警告]${RESET} $2" ;;
        ERR)  echo -e "${RED}[❌ 错误]${RESET} $2" ;;
        STEP) echo -e "${BLUE}==>${RESET} ${BOLD}$2${RESET}" ;;
    esac
}

#====================
# 1. 环境与架构检测
#====================
detect_env() {
    log STEP "正在扫描系统环境..."
    
    # 检测是否为 Windows (MSYS/Cygwin/WSL)
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        log WARN "检测到 Windows 环境，建议使用 PowerShell 脚本或手动放置 EXE 文件。"
        log INFO "本脚本将尝试继续，但服务注册可能会失败。"
    fi

    # 系统类型
    if [ -f /etc/openwrt_release ]; then
        SYS_TYPE="openwrt"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        SYS_TYPE="macos"
    else
        SYS_TYPE="linux"
    fi

    # 架构映射
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) PLATFORM="amd64" ;;
        aarch64|arm64) PLATFORM="arm64" ;;
        armv7*) PLATFORM="armv7" ;;
        mips*) PLATFORM="mips" ;;
        *) PLATFORM="$ARCH" ;;
    esac
    
    # macOS 适配
    OS_TYPE_URL="linux"
    [[ "$SYS_TYPE" == "macos" ]] && OS_TYPE_URL="darwin"

    log INFO "系统: $SYS_TYPE | 架构: $ARCH -> $PLATFORM"
}

#====================
# 2. 智能搜索旧地址
#====================
find_existing_frp() {
    log STEP "正在检索现有安装..."
    SEARCH_NAME=$1
    EXISTING_PATH=$(command -v "$SEARCH_NAME" || which "$SEARCH_NAME" 2>/dev/null || true)
    
    if [ -n "$EXISTING_PATH" ]; then
        INSTALL_DIR=$(dirname "$EXISTING_PATH")
        log WARN "发现已有安装地址: $EXISTING_PATH"
        log INFO "脚本将自动覆盖旧版本，保持目录结构一致。"
    else
        # 默认安装路径
        if [[ "$SYS_TYPE" == "macos" ]]; then
            INSTALL_DIR="/usr/local/bin"
        elif [[ "$SYS_TYPE" == "openwrt" ]]; then
            INSTALL_DIR="/usr/bin"
        else
            INSTALL_DIR="/usr/local/bin"
        fi
        log INFO "未检测到已有安装，将使用默认路径: $INSTALL_DIR"
    fi
}

#====================
# 3. 安装/更新逻辑
#====================
install_frp() {
    # 角色选择
    echo -e "\n${BOLD}请选择角色：${RESET}"
    echo -e "  ${GREEN}1)${RESET} frpc (客户端)"
    echo -e "  ${BLUE}2)${RESET} frps (服务端)"
    read -p "请输入序号 [1-2]: " CHOICE
    [[ "$CHOICE" == "1" ]] && ROLE="frpc" || ROLE="frps"

    find_existing_frp "$ROLE"

    # 版本获取
    log STEP "获取 GitHub 最新版本..."
    LATEST_TAG=$(curl -s "$GITHUB_API" | grep '"tag_name":' | head -n1 | cut -d'"' -f4)
    LATEST_VER_NUM=$(echo "$LATEST_TAG" | sed 's/^v//')
    
    # 下载与解压
    rm -rf "$TMP_DIR" && mkdir -p "$TMP_DIR"
    FILE_NAME="frp_${LATEST_VER_NUM}_${OS_TYPE_URL}_${PLATFORM}.tar.gz"
    URL="https://github.com/fatedier/frp/releases/download/${LATEST_TAG}/${FILE_NAME}"
    
    log INFO "正在下载: $FILE_NAME"
    curl -fsSL -o "$TMP_DIR/frp.tar.gz" "$URL"
    
    tar -xzf "$TMP_DIR/frp.tar.gz" -C "$TMP_DIR" --strip-components=1
    
    # 部署文件
    log STEP "部署二进制文件到 $INSTALL_DIR ..."
    chmod +x "$TMP_DIR/$ROLE"
    mv "$TMP_DIR/$ROLE" "$INSTALL_DIR/$ROLE"

    # 配置文件处理
    CONF_DIR="/etc/frp"
    [[ "$SYS_TYPE" == "macos" ]] && CONF_DIR="/usr/local/etc/frp"
    mkdir -p "$CONF_DIR"
    
    CONF_NAME="${ROLE}.toml"
    # 兼容旧版本 ini
    [[ ! -f "$TMP_DIR/frpc.toml" ]] && [[ -f "$TMP_DIR/frpc.ini" ]] && CONF_NAME="${ROLE}.ini"
    
    if [ ! -f "$CONF_DIR/$CONF_NAME" ]; then
        cp "$TMP_DIR/$CONF_NAME" "$CONF_DIR/$CONF_NAME"
        log OK "初始配置已生成: $CONF_DIR/$CONF_NAME"
    else
        log WARN "现有配置 $CONF_DIR/$CONF_NAME 已保留，未覆盖。"
    fi

    # 服务注册
    register_service "$ROLE" "$INSTALL_DIR/$ROLE" "$CONF_DIR/$CONF_NAME"
}

#====================
# 4. 服务注册逻辑
#====================
register_service() {
    ROLE=$1; BIN_PATH=$2; CONF_PATH=$3;

    if [[ "$SYS_TYPE" == "openwrt" ]]; then
        log STEP "配置 OpenWrt Procd 服务..."
        INIT_FILE="/etc/init.d/$ROLE"
        cat > "$INIT_FILE" <<EOF
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
start_service() {
    procd_open_instance
    procd_set_param command $BIN_PATH -c $CONF_PATH
    procd_set_param respawn
    procd_close_instance
}
EOF
        chmod +x "$INIT_FILE"
        service "$ROLE" enable && service "$ROLE" restart
    
    elif [[ "$SYS_TYPE" == "macos" ]]; then
        log INFO "macOS 建议通过 Launchctl 或手动运行。配置文件位于 $CONF_PATH"
        
    elif [[ "$SYS_TYPE" == "linux" ]]; then
        if command -v systemctl >/dev/null 2>&1; then
            log STEP "配置 Systemd 服务..."
            SERVICE_FILE="/etc/systemd/system/$ROLE.service"
            cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=FRP $ROLE Service
After=network.target
[Service]
Type=simple
ExecStart=$BIN_PATH -c $CONF_PATH
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            systemctl enable "$ROLE"
            systemctl restart "$ROLE"
        fi
    fi
    log OK "$ROLE 安装并启动成功！"
}

# 执行
clear
echo -e "${CYAN}================================================${RESET}"
echo -e "${CYAN}     🌉 FRP 全系统自适应安装工具 2026 版      ${RESET}"
echo -e "${CYAN}================================================${RESET}"
detect_env
install_frp
