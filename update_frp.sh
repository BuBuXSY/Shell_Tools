#!/bin/bash
#====================================================
# 🌉 FRP 自动升级 + Systemd 注册 v6.0
# 🚀 自动备份 / 自动检测 / 自动服务注册
# 👤 By: BuBuXSY
#====================================================

set -euo pipefail

# =============================
# 🎨 颜色
# =============================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

log(){ echo -e "${CYAN}[信息]${RESET} $1"; }
ok(){ echo -e "${GREEN}[成功]${RESET} $1"; }
warn(){ echo -e "${YELLOW}[警告]${RESET} $1"; }
err(){ echo -e "${RED}[错误]${RESET} $1"; }

# =============================
# 🔐 权限检查
# =============================
if [ "$(id -u)" != "0" ]; then
    err "请使用 root 运行"
    exit 1
fi

# =============================
# 🖥 架构检测
# =============================
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) PLATFORM="amd64" ;;
    aarch64|arm64) PLATFORM="arm64" ;;
    armv7*) PLATFORM="arm" ;;
    *) err "不支持架构: $ARCH"; exit 1 ;;
esac

# =============================
# 🔥 获取最新版本
# =============================
get_latest() {
    local response
    response=$(curl -fsSL -w "\n%{http_code}" \
        https://api.github.com/repos/fatedier/frp/releases/latest)

    local code
    code=$(echo "$response" | tail -n1)

    if [ "$code" != "200" ]; then
        err "GitHub API 请求失败"
        exit 1
    fi

    echo "$response" | sed '$d' | grep -m1 '"tag_name"' | cut -d'"' -f4
}

# =============================
# 🌉 主流程
# =============================
echo
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${CYAN}${BOLD}   🌉 FRP 自动管理工具 v6.0${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"

read -p "请选择角色 (1=frpc / 2=frps): " CHOICE

if [ "$CHOICE" = "1" ]; then
    ROLE="frpc"
else
    ROLE="frps"
fi

log "检测已安装版本..."

if command -v $ROLE >/dev/null 2>&1; then
    CURRENT_VERSION=$($ROLE -v 2>/dev/null || echo "未知")
    warn "当前版本: $CURRENT_VERSION"
else
    warn "未检测到已安装版本"
fi

LATEST_TAG="$(get_latest)"
VERSION="${LATEST_TAG#v}"

ok "最新版本: $LATEST_TAG"

# =============================
# 📦 自动备份
# =============================
BACKUP_DIR="/var/backups/frp"
mkdir -p "$BACKUP_DIR"

if command -v $ROLE >/dev/null 2>&1; then
    cp "$(which $ROLE)" "$BACKUP_DIR/${ROLE}_$(date +%Y%m%d_%H%M%S).bak"
    ok "已备份旧版本"
fi

# =============================
# ⬇ 下载新版本
# =============================
FILE="frp_${VERSION}_linux_${PLATFORM}.tar.gz"
URL="https://github.com/fatedier/frp/releases/download/${LATEST_TAG}/${FILE}"

log "下载: $FILE"

cd /tmp
rm -rf frp_temp
mkdir frp_temp
cd frp_temp

curl -fL -o frp.tar.gz "$URL"
tar -xzf frp.tar.gz

# =============================
# 🚀 安装二进制
# =============================
INSTALL_DIR="/usr/local/bin"
cp "frp_${VERSION}_linux_${PLATFORM}/$ROLE" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/$ROLE"

ok "二进制文件更新完成"

# =============================
# ⚙ 自动 systemd 注册
# =============================
SERVICE_FILE="/etc/systemd/system/${ROLE}.service"

if [ ! -f "$SERVICE_FILE" ]; then
    log "创建 systemd 服务..."

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=FRP $ROLE Service
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/$ROLE -c /etc/frp/${ROLE}.toml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $ROLE
    ok "systemd 服务已创建"
else
    warn "检测到已有 systemd 服务，已保留"
fi

# =============================
# 📁 配置文件保护
# =============================
CONF_DIR="/etc/frp"
mkdir -p "$CONF_DIR"

if [ ! -f "$CONF_DIR/${ROLE}.toml" ] && [ ! -f "$CONF_DIR/${ROLE}.ini" ]; then
    warn "未检测到配置文件，请手动配置"
else
    ok "配置文件已保留未覆盖"
fi

# =============================
# 🔄 重启服务
# =============================
systemctl restart $ROLE 2>/dev/null || true

ok "FRP 安装/升级完成 🎉"

echo
echo -e "${GREEN}备份目录: $BACKUP_DIR${RESET}"
echo -e "${GREEN}服务管理: systemctl {start|stop|restart} $ROLE${RESET}"
