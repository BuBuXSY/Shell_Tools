#!/bin/bash
#====================================================
# 🌉 FRP 全平台自动安装/更新 & 智能路径修正工具
# 🚀 支持: OpenWrt, Ubuntu, RedHat, Arch, macOS
# 🔐 Version 1.0
#====================================================

set -euo pipefail

TMP_DIR="/tmp/frp_installer"
GITHUB_API="https://api.github.com/repos/fatedier/frp/releases/latest"

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[34m";
CYAN="\033[36m"; BOLD="\033[1m"; RESET="\033[0m";

log() {
    case "$1" in
        INFO) echo -e "${CYAN}[ℹ]${RESET} $2" ;;
        OK)   echo -e "${GREEN}[✓]${RESET} $2" ;;
        WARN) echo -e "${YELLOW}[!]${RESET} $2" ;;
        ERR)  echo -e "${RED}[✗]${RESET} $2" ;;
        STEP) echo -e "${BLUE}==>${RESET} ${BOLD}$2${RESET}" ;;
    esac
}

#====================
# 环境检测
#====================
detect_env() {

    if [ -f /etc/openwrt_release ]; then
        SYS_TYPE="openwrt"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        SYS_TYPE="macos"
    else
        SYS_TYPE="linux"
    fi

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) PLATFORM="amd64" ;;
        aarch64|arm64) PLATFORM="arm64" ;;
        armv7*) PLATFORM="armv7" ;;
        *) PLATFORM="$ARCH" ;;
    esac

    OS_TYPE_URL="linux"
    [[ "$SYS_TYPE" == "macos" ]] && OS_TYPE_URL="darwin"

    log INFO "系统: $SYS_TYPE | 架构: $PLATFORM"
}

#====================
# 获取最新版本（安全版）
#====================
get_latest_release() {

    log STEP "获取最新版本..."

    RELEASE_JSON=$(curl -fsSL "$GITHUB_API" || true)

    if [ -z "$RELEASE_JSON" ]; then
        log ERR "无法获取 GitHub 版本信息"
        exit 1
    fi

    LATEST_TAG=$(echo "$RELEASE_JSON" | grep '"tag_name":' | head -n1 | cut -d'"' -f4)

    if [ -z "$LATEST_TAG" ]; then
        log ERR "解析版本失败"
        exit 1
    fi

    echo "$LATEST_TAG"
}

#====================
# 安装逻辑
#====================
install_frp() {

    echo -e "\n${BOLD}请选择角色：${RESET}"
    echo "1) frpc"
    echo "2) frps"
    read -p "选择: " CHOICE

    [[ "$CHOICE" == "1" ]] && ROLE="frpc" || ROLE="frps"

    INSTALL_DIR="/usr/local/bin"
    [[ "$SYS_TYPE" == "openwrt" ]] && INSTALL_DIR="/usr/bin"

    CONF_DIR="/etc/frp"
    [[ "$SYS_TYPE" == "macos" ]] && CONF_DIR="/usr/local/etc/frp"

    mkdir -p "$TMP_DIR" "$CONF_DIR"

    LATEST_TAG=$(get_latest_release)

    FILE_NAME="frp_${LATEST_TAG#v}_${OS_TYPE_URL}_${PLATFORM}.tar.gz"
    URL="https://github.com/fatedier/frp/releases/download/${LATEST_TAG}/${FILE_NAME}"

    log INFO "下载 $FILE_NAME"

    curl -fL -o "$TMP_DIR/frp.tar.gz" "$URL"

    # 解压
    tar -xzf "$TMP_DIR/frp.tar.gz" -C "$TMP_DIR" --strip-components=1

    # ===== 备份旧版本 =====
    if [ -f "$INSTALL_DIR/$ROLE" ]; then
        cp "$INSTALL_DIR/$ROLE" "$INSTALL_DIR/${ROLE}.bak"
        log OK "已备份旧版本"
    fi

    # 部署
    chmod +x "$TMP_DIR/$ROLE"
    mv "$TMP_DIR/$ROLE" "$INSTALL_DIR/$ROLE"

    # 配置文件
    CONF_FILE="$CONF_DIR/${ROLE}.toml"

    if [ ! -f "$CONF_FILE" ]; then
        cp "$TMP_DIR/${ROLE}.toml" "$CONF_FILE"
        log OK "已生成默认配置"
    else
        log WARN "配置已存在，未覆盖"
    fi

    register_service
}

#====================
# 服务注册
#====================
register_service() {

    if [[ "$SYS_TYPE" == "linux" ]]; then

        if command -v systemctl >/dev/null 2>&1; then

            SERVICE="/etc/systemd/system/$ROLE.service"

            cat > "$SERVICE" <<EOF
[Unit]
Description=FRP $ROLE
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/$ROLE -c $CONF_FILE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

            systemctl daemon-reload
            systemctl enable "$ROLE"
            systemctl restart "$ROLE"

            # 健康检查
            sleep 2
            if systemctl is-active --quiet "$ROLE"; then
                log OK "$ROLE 启动成功"
            else
                log ERR "启动失败，执行回滚"
                rollback
            fi
        fi
    fi
}

#====================
# 回滚机制
#====================
rollback() {

    if [ -f "$INSTALL_DIR/${ROLE}.bak" ]; then
        mv "$INSTALL_DIR/${ROLE}.bak" "$INSTALL_DIR/$ROLE"
        systemctl restart "$ROLE" || true
        log WARN "已回滚到旧版本"
    fi

    exit 1
}

#====================
# 主流程
#====================
clear
echo -e "${CYAN}================================================${RESET}"
echo -e "${CYAN}     🌉 FRP 全系统自适应安装工具 企业增强版     ${RESET}"
echo -e "${CYAN}================================================${RESET}"

detect_env
install_frp
