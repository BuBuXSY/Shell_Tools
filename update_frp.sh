#!/bin/bash
#====================================================
# 🌉 FRP 升级工具 v2.0
# 🚀 升级前测试 / 升级后验证 / 自动备份 / 可回滚
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
clear
echo -e "${CYAN}${BOLD}"
echo "============================================"
echo "   🌉 FRP 升级工具 v2.0"
echo "============================================"
echo -e "${RESET}"

read -p "请选择角色 (1=frpc / 2=frps): " CHOICE

if [ "$CHOICE" = "1" ]; then
    ROLE="frpc"
else
    ROLE="frps"
fi

# =============================
# 📊 当前版本检测
# =============================
log "正在检测当前版本..."

if command -v $ROLE >/dev/null 2>&1; then
    CURRENT_VERSION=$($ROLE -v 2>/dev/null || echo "unknown")
    warn "当前版本: $CURRENT_VERSION"
else
    warn "未检测到已安装版本"
    CURRENT_VERSION="none"
fi

# =============================
# 🌍 获取最新版本
# =============================
log "正在获取最新版本..."

LATEST_TAG="$(get_latest)"
LATEST_VERSION="${LATEST_TAG#v}"

ok "最新版本: $LATEST_TAG"

# =============================
# 🔎 是否需要升级判断
# =============================
if [[ "$CURRENT_VERSION" != "none" ]]; then
    if echo "$CURRENT_VERSION" | grep -q "$LATEST_VERSION"; then
        ok "🎉 当前已是最新版本，无需升级"
        exit 0
    fi
fi

# =============================
# 🧪 升级前自动测试
# =============================
log "执行升级前自动测试..."

if systemctl is-active --quiet $ROLE 2>/dev/null; then
    warn "服务正在运行，开始测试配置..."
    if ! $ROLE -c /etc/frp/${ROLE}.toml -t 2>/dev/null; then
        err "配置测试失败，终止升级"
        exit 1
    fi
    ok "配置测试通过"
else
    warn "服务未运行，跳过配置测试"
fi

# =============================
# 💾 自动备份
# =============================
BACKUP_DIR="/var/backups/frp"
mkdir -p "$BACKUP_DIR"

if command -v $ROLE >/dev/null 2>&1; then
    cp "$(which $ROLE)" "$BACKUP_DIR/${ROLE}_$(date +%Y%m%d_%H%M%S).bak"
    ok "已自动备份旧版本"
fi

# =============================
# ⬇ 下载新版本
# =============================
FILE="frp_${LATEST_VERSION}_linux_${PLATFORM}.tar.gz"
URL="https://github.com/fatedier/frp/releases/download/${LATEST_TAG}/${FILE}"

log "开始下载: $FILE"

cd /tmp
rm -rf frp_temp
mkdir frp_temp
cd frp_temp

curl -fL -o frp.tar.gz "$URL"
tar -xzf frp.tar.gz

# =============================
# 🚀 安装
# =============================
cp "frp_${LATEST_VERSION}_linux_${PLATFORM}/$ROLE" /usr/local/bin/
chmod +x /usr/local/bin/$ROLE

ok "二进制更新完成"

# =============================
# ⚙ Systemd 注册
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
ExecStart=/usr/local/bin/$ROLE -c /etc/frp/${ROLE}.toml
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
# 🔄 重启服务
# =============================
systemctl restart $ROLE 2>/dev/null || true

# =============================
# 🧪 升级后自动验证
# =============================
log "执行升级后自动验证..."

sleep 2

if systemctl is-active --quiet $ROLE; then
    ok "服务运行正常 ✅"
else
    err "服务未正常启动，请检查日志"
    exit 1
fi

if command -v $ROLE >/dev/null 2>&1; then
    NEW_VERSION=$($ROLE -v 2>/dev/null || echo "unknown")
    ok "当前运行版本: $NEW_VERSION"
fi

echo
ok "🎉 升级流程全部完成"
echo -e "${GREEN}备份目录: $BACKUP_DIR${RESET}"
echo -e "${GREEN}如有问题可手动回滚旧版本${RESET}"
