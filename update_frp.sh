#!/bin/sh
# shellcheck shell=dash
# ====================================================
# MIT License
#
# Copyright (c) 2025 BuBuXSY
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ====================================================
# 🌉 FRP 自动安装 & 更新 & 卸载脚本 v2.1
# 支持 OpenWrt / Linux | frps / frpc
# By: BuBuXSY
# Version: 2026-07-11
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
CYAN="\033[36m"
RESET="\033[0m"

log() {
    case "$1" in
        INFO) printf "${BLUE}[ℹ️  INFO]${RESET} %s\n" "$2" ;;
        OK)   printf "${GREEN}[✅ OK]${RESET} %s\n"   "$2" ;;
        WARN) printf "${YELLOW}[⚠️  WARN]${RESET} %s\n" "$2" ;;
        ERR)  printf "${RED}[❌ ERR]${RESET} %s\n"   "$2" ;;
        STEP) printf "${CYAN}[🔧 STEP]${RESET} %s\n" "$2" ;;
    esac
}

# 带分隔线的步骤标题
log_step() {
    printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
    log STEP "$1"
    printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# =========================
# 📋 全局变量初始化
# =========================
TMP_DIR=""
FRP_ROOT="${FRP_ROOT:-}"
SERVICE_MANAGER_OVERRIDE="${FRP_SERVICE_MANAGER:-auto}"
SYSTEMCTL_CMD="${FRP_SYSTEMCTL:-systemctl}"
GITHUB_API="${FRP_GITHUB_API:-https://api.github.com/repos/fatedier/frp/releases/latest}"
GITHUB_RELEASE="${FRP_GITHUB_RELEASE:-https://github.com/fatedier/frp/releases}"
IS_OPENWRT=0
PLATFORM=""
FETCHER=""
LATEST_VERSION=""
ROLE=""
ACTION=""                              # install / update / uninstall
CLI_ROLE=""
CLI_ACTION=""
ASSUME_YES=0
BINARY_PATH=""
CONFIG_PATH=""
SERVICE_PATH=""
BINARY_BACKUP=""
BINARY_WAS_PRESENT=0
STAGED_BIN=""
STAGED_CONFIG=""
STAGED_SERVICE=""
TRANSACTION_ACTIVE=0
ROLLBACK_IN_PROGRESS=0
PRESERVE_BACKUP=0
CONFIG_CREATED=0
CONFIG_DIR_CREATED=0
SERVICE_KIND="none"
SERVICE_CREATED=0
SERVICE_WAS_ACTIVE=0
SERVICE_RESTART_ATTEMPTED=0
SERVICE_RESTARTED=0
FIRST_INSTALL=0

case "$FRP_ROOT" in
    ""|/*) ;;
    *)
        log ERR "FRP_ROOT 必须为绝对路径"
        exit 2
        ;;
esac

case "$SERVICE_MANAGER_OVERRIDE" in
    auto|none|systemd|openwrt) ;;
    *)
        log ERR "FRP_SERVICE_MANAGER 仅支持 auto/none/systemd/openwrt"
        exit 2
        ;;
esac

BIN_DIR="${FRP_ROOT}/usr/bin"
CONFIG_DIR="${FRP_ROOT}/etc/frp"
SYSTEMD_DIR="${FRP_ROOT}/etc/systemd/system"
INIT_DIR="${FRP_ROOT}/etc/init.d"
OPENWRT_RELEASE="${FRP_ROOT}/etc/openwrt_release"

# =========================
# 🧹 统一退出、回滚与清理
# =========================
cleanup() {
    [ -n "$STAGED_BIN" ] && rm -f "$STAGED_BIN"
    [ -n "$STAGED_CONFIG" ] && rm -f "$STAGED_CONFIG"
    [ -n "$STAGED_SERVICE" ] && rm -f "$STAGED_SERVICE"
    if [ -n "$BINARY_BACKUP" ] && [ "$PRESERVE_BACKUP" -eq 0 ]; then
        rm -f "$BINARY_BACKUP"
    fi
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
        log INFO "🧹 临时文件已清理"
    fi
}

handle_signal() {
    local signal_name="$1"
    local signal_status="$2"
    log ERR "收到 $signal_name 信号，正在中止并回滚"
    exit "$signal_status"
}

on_exit() {
    local status=$?
    trap - EXIT HUP INT TERM
    set +e

    if [ "$TRANSACTION_ACTIVE" -eq 1 ]; then
        if ! rollback_transaction; then
            status=1
        fi
    fi
    cleanup
    exit "$status"
}

trap on_exit EXIT
trap 'handle_signal HUP 129' HUP
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM

usage() {
    cat <<EOF
用法: $0 [--action install|update|uninstall] [--role frpc|frps] [--yes] [--help]

  --action  指定安装/更新或卸载
  --role    指定客户端 frpc 或服务端 frps
  --yes     跳过安装/卸载确认
  --help    显示帮助并退出

测试时可设置 FRP_ROOT 将系统文件写入临时根目录；
此时默认不操作服务，如需测试 systemd，必须同时显式设置
FRP_SERVICE_MANAGER=systemd 和 FRP_SYSTEMCTL=/path/to/stub。
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --action)
                [ "$#" -ge 2 ] || { log ERR "--action 缺少参数"; exit 2; }
                case "$2" in
                    install|update) CLI_ACTION="install" ;;
                    uninstall) CLI_ACTION="uninstall" ;;
                    *) log ERR "无效操作: $2"; exit 2 ;;
                esac
                shift 2
                ;;
            --role)
                [ "$#" -ge 2 ] || { log ERR "--role 缺少参数"; exit 2; }
                case "$2" in
                    frpc|frps) CLI_ROLE="$2" ;;
                    *) log ERR "无效角色: $2（仅支持 frpc/frps）"; exit 2 ;;
                esac
                shift 2
                ;;
            --yes|-y) ASSUME_YES=1; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log ERR "未知参数: $1"; usage >&2; exit 2 ;;
        esac
    done
}

prepare_tmp_dir() {
    [ -n "$TMP_DIR" ] && return 0
    TMP_DIR=$(mktemp -d /tmp/frp-installer.XXXXXX) \
        || { log ERR "❌ 无法创建临时目录"; exit 1; }
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log ERR "请使用 root 权限运行此脚本（sudo 或 su）"
        exit 1
    fi
}

set_role_paths() {
    BINARY_PATH="$BIN_DIR/$ROLE"
    CONFIG_PATH="$CONFIG_DIR/${ROLE}.toml"
}

resolve_service_kind() {
    case "$SERVICE_MANAGER_OVERRIDE" in
        none)
            SERVICE_KIND="none"
            ;;
        openwrt)
            SERVICE_KIND="openwrt"
            ;;
        systemd)
            if [ -n "$FRP_ROOT" ] && [ -z "${FRP_SYSTEMCTL:-}" ]; then
                log ERR "FRP_ROOT 模式下测试 systemd 必须显式指定 FRP_SYSTEMCTL stub"
                return 1
            fi
            if ! command_exists "$SYSTEMCTL_CMD"; then
                log ERR "❌ 未找到 systemctl 命令: $SYSTEMCTL_CMD"
                return 1
            fi
            SERVICE_KIND="systemd"
            ;;
        auto)
            if [ -n "$FRP_ROOT" ]; then
                SERVICE_KIND="none"
                log WARN "⚠️  FRP_ROOT 测试模式默认跳过所有真实服务操作"
            elif [ "$IS_OPENWRT" -eq 1 ]; then
                SERVICE_KIND="openwrt"
            elif command_exists "$SYSTEMCTL_CMD"; then
                SERVICE_KIND="systemd"
            else
                SERVICE_KIND="none"
            fi
            ;;
    esac
}

find_systemd_service_path() {
    local fragment=""
    local candidate

    if [ -z "$FRP_ROOT" ]; then
        fragment=$("$SYSTEMCTL_CMD" show -p FragmentPath --value "${ROLE}.service" 2>/dev/null) || true
        if [ -n "$fragment" ] && { [ -e "$fragment" ] || [ -L "$fragment" ]; }; then
            SERVICE_PATH="$fragment"
            return 0
        fi
    fi

    for candidate in \
        "$SYSTEMD_DIR/${ROLE}.service" \
        "${FRP_ROOT}/usr/lib/systemd/system/${ROLE}.service" \
        "${FRP_ROOT}/lib/systemd/system/${ROLE}.service"; do
        if [ -e "$candidate" ] || [ -L "$candidate" ]; then
            SERVICE_PATH="$candidate"
            return 0
        fi
    done
    SERVICE_PATH="$SYSTEMD_DIR/${ROLE}.service"
}

validate_service_file_paths() {
    local service_file="$1"

    if ! grep -Fq "$BINARY_PATH" "$service_file" \
        || ! grep -Fq "$CONFIG_PATH" "$service_file"; then
        log ERR "❌ 现有服务定义未同时引用 $BINARY_PATH 和 $CONFIG_PATH"
        log ERR "为避免重启未受管的 FRP 实例，已拒绝升级: $service_file"
        return 1
    fi
}

validate_systemd_service_paths() {
    local effective_exec=""

    if [ -n "$FRP_ROOT" ]; then
        validate_service_file_paths "$SERVICE_PATH"
        return
    fi

    effective_exec=$("$SYSTEMCTL_CMD" show -p ExecStart --value "${ROLE}.service" 2>/dev/null) || true
    case "$effective_exec" in
        *"$BINARY_PATH"*) ;;
        *)
            log ERR "❌ 现有 ${ROLE}.service 的有效 ExecStart 未引用 $BINARY_PATH"
            log ERR "为避免重启未受管的 FRP 实例，已拒绝升级: $SERVICE_PATH"
            return 1
            ;;
    esac
    case "$effective_exec" in
        *"$CONFIG_PATH"*) ;;
        *)
            log ERR "❌ 现有 ${ROLE}.service 的有效 ExecStart 未引用 $CONFIG_PATH"
            log ERR "为避免重启未受管的 FRP 实例，已拒绝升级: $SERVICE_PATH"
            return 1
            ;;
    esac
}

# =========================
# 🖥 系统检测（OpenWrt / Linux）
# =========================
detect_system() {
    log_step "系统环境检测"
    if [ -f "$OPENWRT_RELEASE" ]; then
        IS_OPENWRT=1
        DISTRIB_RELEASE=""
        # shellcheck source=/dev/null
        . "$OPENWRT_RELEASE"
        OS_NAME="OpenWrt ${DISTRIB_RELEASE:-unknown}"
    else
        IS_OPENWRT=0
        OS_NAME="$(uname -s) $(uname -r)"
    fi
    log INFO "🐧 系统: $OS_NAME"
}

# =========================
# 🏗 架构检测
# =========================
detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)  PLATFORM="amd64" ;;
        aarch64|arm64) PLATFORM="arm64" ;;
        armv5*|armv6*|armv7*) PLATFORM="arm" ;;
        loongarch64|loong64) PLATFORM="loong64" ;;
        mips64el|mips64le) PLATFORM="mips64le" ;;
        mips64*)       PLATFORM="mips64" ;;
        mipsel|mipsle) PLATFORM="mipsle" ;;
        mips*)         PLATFORM="mips" ;;
        riscv64)       PLATFORM="riscv64" ;;
        *)
            log ERR "❌ 不支持的 CPU 架构: $arch"
            exit 1
            ;;
    esac
    log INFO "🖥  架构: $arch → $PLATFORM"
}

# =========================
# 📥 下载工具选择
# =========================
detect_fetcher() {
    if command_exists curl; then
        FETCHER="curl"
    elif command_exists wget; then
        FETCHER="wget"
    elif [ "$IS_OPENWRT" -eq 1 ] && command_exists uclient-fetch; then
        FETCHER="uclient-fetch"
    else
        log ERR "❌ 未找到可用下载工具（curl / wget / uclient-fetch）"
        exit 1
    fi
    log INFO "📥 下载工具: $FETCHER"
}

fetch_to_file() {
    local url="$1" output="$2"
    rm -f "$output"
    case "$FETCHER" in
        curl)
            curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 \
                --max-time 120 -o "$output" "$url"
            ;;
        wget)
            wget -q -O "$output" "$url"
            ;;
        uclient-fetch)
            uclient-fetch -q -O "$output" "$url"
            ;;
        *) return 1 ;;
    esac
}

# =========================
# 🔍 获取最新 FRP 版本
# 修复：原版强依赖 curl（与 detect_fetcher 逻辑不一致），
#       且 GitHub API 在国内常被墙，现增加 HTML 页面解析作为备用通道。
# =========================
get_latest_version() {
    log_step "查询最新 FRP 版本"
    prepare_tmp_dir
    local release_file="$TMP_DIR/latest-release"

    # 通道 1：GitHub API（优先，返回 JSON，解析最稳定）
    if fetch_to_file "$GITHUB_API" "$release_file"; then
        LATEST_VERSION=$(grep '"tag_name":' "$release_file" \
            | head -n1 | cut -d'"' -f4) || true
    fi

    # 通道 2：解析 GitHub releases 页面（API 不可达时的备用方案）
    # 修复：国内访问 GitHub API 经常超时，增加 HTML 解析兜底
    if [ -z "$LATEST_VERSION" ]; then
        log WARN "⚠️  GitHub API 不可达，尝试备用通道解析 releases 页面..."
        if fetch_to_file "$GITHUB_RELEASE/latest" "$release_file"; then
            LATEST_VERSION=$(grep -oE 'fatedier/frp/releases/tag/v[0-9]+\.[0-9]+\.[0-9]+' "$release_file" \
                | head -n1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+') || true
        fi
    fi

    case "$LATEST_VERSION" in
        v[0-9]*.[0-9]*.[0-9]*) ;;
        *) LATEST_VERSION="" ;;
    esac
    if [ -z "$LATEST_VERSION" ]; then
        log ERR "❌ 无法获取 FRP 最新版本号，请检查网络连接"
        exit 1
    fi

    log OK "📌 最新版本: $LATEST_VERSION"
}

# =========================
# 📊 对比当前已安装版本
# 修复：原版每次都全量重装，没有版本对比提示
# =========================
check_installed_version() {
    local installed="未安装"
    local installed_raw=""
    if [ -f "$BINARY_PATH" ]; then
        installed_raw=$("$BINARY_PATH" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || true
    elif command_exists "$ROLE"; then
        installed_raw=$("$ROLE" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || true
    fi
    [ -n "$installed_raw" ] && installed="v$installed_raw"

    printf "\n${BLUE}📌 当前版本：${YELLOW}%s${RESET}\n" "$installed"
    printf "${BLUE}📌 最新版本：${GREEN}%s${RESET}\n\n" "$LATEST_VERSION"

    if [ "$installed" = "$LATEST_VERSION" ]; then
        log WARN "⚠️  当前已是最新版本 $LATEST_VERSION"
        [ "$ASSUME_YES" -eq 1 ] && return 0
        printf "❓ 是否仍要重新安装？[y/N]: "
        read -r confirm || confirm=""
        case "$confirm" in
            y|Y) log INFO "继续重新安装..." ;;
            *)   log INFO "👋 已取消"; exit 0 ;;
        esac
    fi
}

# =========================
# 📦 下载 FRP 压缩包（带重试）
# 修复：原版一次失败即退出，改为最多重试 3 次
# =========================
download_frp() {
    log_step "下载 FRP $LATEST_VERSION"
    prepare_tmp_dir

    local ver_plain
    ver_plain="${LATEST_VERSION#v}"     # 去掉 v 前缀，如 v0.61.0 → 0.61.0
    TAR_NAME="frp_${ver_plain}_linux_${PLATFORM}.tar.gz"
    TAR_FILE="$TMP_DIR/$TAR_NAME"
    EXTRACT_DIR="$TMP_DIR/frp_${ver_plain}_linux_${PLATFORM}"
    URL="${GITHUB_RELEASE}/download/${LATEST_VERSION}/${TAR_NAME}"
    CHECKSUM_FILE="$TMP_DIR/frp_sha256_checksums.txt"
    CHECKSUM_URL="${GITHUB_RELEASE}/download/${LATEST_VERSION}/frp_sha256_checksums.txt"

    log INFO "🔗 下载地址: $URL"

    # 重试最多 3 次
    local attempt=0
    local ok=0
    while [ "$attempt" -lt 3 ]; do
        attempt=$((attempt + 1))
        log INFO "⬇️  第 $attempt 次下载..."
        if fetch_to_file "$URL" "$TAR_FILE"; then
            ok=1; break
        fi
        log WARN "第 $attempt 次下载失败，${attempt}0 秒后重试..."
        sleep $((attempt * 10))
    done

    if [ "$ok" -eq 0 ]; then
        log ERR "❌ 下载失败（已重试 3 次），请检查网络或架构是否支持（$PLATFORM）"
        exit 1
    fi

    # 文件完整性校验（busybox wc 输出可能含空格，用 tr 去除）
    # 修复：busybox 的 wc -c 输出格式含前导空格，直接比较会失败
    local size
    size=$(wc -c < "$TAR_FILE" | tr -d ' ')
    if [ "$size" -lt 1024 ]; then
        log ERR "❌ 下载文件异常，体积过小（${size} bytes），可能为错误页面"
        exit 1
    fi

    log INFO "🔐 下载官方 SHA-256 校验清单..."
    if ! fetch_to_file "$CHECKSUM_URL" "$CHECKSUM_FILE"; then
        log ERR "❌ 无法下载 frp_sha256_checksums.txt，拒绝安装未验证资产"
        exit 1
    fi

    local expected_hash=""
    local checksum_hash checksum_name checksum_extra
    while read -r checksum_hash checksum_name checksum_extra; do
        case "$checksum_name" in
            \*) checksum_name=${checksum_name#\*} ;;
        esac
        if [ "$checksum_name" = "$TAR_NAME" ] && [ -z "${checksum_extra:-}" ]; then
            if [ -n "$expected_hash" ]; then
                log ERR "❌ 校验清单中 $TAR_NAME 出现多次，拒绝继续"
                exit 1
            fi
            expected_hash=$(printf '%s' "$checksum_hash" | tr 'A-F' 'a-f')
        fi
    done < "$CHECKSUM_FILE"

    if [ -z "$expected_hash" ]; then
        log ERR "❌ 官方校验清单中缺少 $TAR_NAME"
        exit 1
    fi

    local actual_hash
    actual_hash=$(sha256sum "$TAR_FILE" | cut -d ' ' -f1)
    if [ "$actual_hash" != "$expected_hash" ]; then
        log ERR "❌ SHA-256 校验失败（期望 $expected_hash，实际 $actual_hash）"
        exit 1
    fi
    log OK "🔐 SHA-256 校验通过"

    if ! tar -tzf "$TAR_FILE" >/dev/null 2>&1; then
        log ERR "❌ 压缩包校验失败"
        exit 1
    fi
    if tar -tzf "$TAR_FILE" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
        log ERR "❌ 压缩包包含不安全路径，已拒绝解压"
        exit 1
    fi

    log OK "✅ 下载完成: $TAR_NAME（${size} bytes）"
}

# =========================
# ⚙️  安装 FRP 二进制及配置
# =========================
install_frp() {
    log_step "安装 $ROLE 二进制"

    log INFO "📂 解压压缩包..."
    tar -xzf "$TAR_FILE" -C "$TMP_DIR" \
        || { log ERR "❌ 解压失败，tar 文件可能不完整"; exit 1; }

    local bin_src="$EXTRACT_DIR/$ROLE"
    if [ ! -f "$bin_src" ]; then
        log ERR "❌ 解压后未找到 $ROLE 二进制: $bin_src"
        log ERR "  当前 PLATFORM=$PLATFORM，请确认架构是否正确"
        exit 1
    fi

    chmod +x "$bin_src"
    local binary_version
    binary_version=$("$bin_src" --version 2>/dev/null \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || true
    if [ "v$binary_version" != "$LATEST_VERSION" ]; then
        log ERR "❌ 二进制版本校验失败（期望 $LATEST_VERSION，实际 ${binary_version:-未知}）"
        exit 1
    fi

    if [ ! -d "$BIN_DIR" ]; then
        log ERR "❌ 二进制目录不存在: $BIN_DIR"
        exit 1
    fi

    if [ -f "$BINARY_PATH" ]; then
        BINARY_WAS_PRESENT=1
        BINARY_BACKUP=$(mktemp "${TMPDIR:-/tmp}/frp-${ROLE}.backup.XXXXXX") \
            || { log ERR "❌ 无法创建旧二进制备份"; exit 1; }
        cp -p "$BINARY_PATH" "$BINARY_BACKUP" \
            || { log ERR "❌ 旧二进制备份失败"; exit 1; }
    elif [ -e "$BINARY_PATH" ] || [ -L "$BINARY_PATH" ]; then
        log ERR "❌ $BINARY_PATH 存在但不是可备份的常规文件"
        exit 1
    fi

    STAGED_BIN=$(mktemp "$BIN_DIR/.${ROLE}.new.XXXXXX") \
        || { log ERR "❌ 无法创建二进制 staged 文件"; exit 1; }
    cp "$bin_src" "$STAGED_BIN" \
        || { log ERR "❌ 复制新二进制失败"; exit 1; }
    chmod 0755 "$STAGED_BIN"

    TRANSACTION_ACTIVE=1
    mv -f "$STAGED_BIN" "$BINARY_PATH"
    STAGED_BIN=""
    log OK "✅ $ROLE 已安装至 $BINARY_PATH"

    install_config
}

install_config() {
    if [ -e "$CONFIG_PATH" ] || [ -L "$CONFIG_PATH" ]; then
        FIRST_INSTALL=0
        log WARN "⚠️  $CONFIG_PATH 已存在，保留现有配置"
        log INFO "🧪 使用新二进制验证现有配置..."
        if ! "$BINARY_PATH" verify -c "$CONFIG_PATH"; then
            log ERR "❌ 现有配置未通过 $ROLE verify，将回滚升级"
            return 1
        fi
        return 0
    fi

    FIRST_INSTALL=1
    if [ ! -d "$CONFIG_DIR" ]; then
        CONFIG_DIR_CREATED=1
        mkdir -p "$CONFIG_DIR"
    fi

    STAGED_CONFIG=$(mktemp "$CONFIG_DIR/.${ROLE}.toml.new.XXXXXX") \
        || { log ERR "❌ 无法创建配置 staged 文件"; return 1; }
    chmod 0600 "$STAGED_CONFIG"

    case "$ROLE" in
        frps)
            cat > "$STAGED_CONFIG" <<'EOF'
# 首次启动前必须修改监听地址、端口和认证信息。
# 如需 OIDC，请按 FRP 官方文档替换下方 token 认证配置。
bindAddr = "127.0.0.1"
bindPort = 7000

auth.method = "token"
auth.token = "CHANGE_ME_BEFORE_START"
EOF
            ;;
        frpc)
            cat > "$STAGED_CONFIG" <<'EOF'
# 首次启动前必须修改服务端地址、端口和认证信息。
# 本文件不预置 SSH 或其他代理；请在完成认证后自行添加。
serverAddr = "127.0.0.1"
serverPort = 7000

auth.method = "token"
auth.token = "CHANGE_ME_BEFORE_START"
EOF
            ;;
    esac

    if ! "$BINARY_PATH" verify -c "$STAGED_CONFIG"; then
        log ERR "❌ 内置安全配置未通过 $ROLE verify"
        return 1
    fi

    CONFIG_CREATED=1
    mv -f "$STAGED_CONFIG" "$CONFIG_PATH"
    STAGED_CONFIG=""
    chmod 0600 "$CONFIG_PATH"
    log OK "📄 已生成 0600 安全配置: $CONFIG_PATH"
    log WARN "⚠️  首装不会启用或启动服务，请先更换 token/OIDC 并核对地址、端口"
}

restore_binary() {
    local restore_tmp=""

    if [ "$BINARY_WAS_PRESENT" -eq 1 ]; then
        if [ ! -f "$BINARY_BACKUP" ]; then
            log ERR "❌ 旧二进制备份丢失: $BINARY_BACKUP"
            return 1
        fi
        restore_tmp=$(mktemp "$BIN_DIR/.${ROLE}.rollback.XXXXXX") || return 1
        if ! cp -p "$BINARY_BACKUP" "$restore_tmp" \
            || ! mv -f "$restore_tmp" "$BINARY_PATH"; then
            rm -f "$restore_tmp"
            return 1
        fi
        log OK "✅ 已恢复升级前的 $ROLE 二进制"
    else
        if ! rm -f "$BINARY_PATH"; then
            return 1
        fi
        log INFO "已移除本次新安装的二进制"
    fi
}

rollback_transaction() {
    local failed=0

    [ "$TRANSACTION_ACTIVE" -eq 1 ] || return 0
    [ "$ROLLBACK_IN_PROGRESS" -eq 0 ] || return 1
    ROLLBACK_IN_PROGRESS=1
    log WARN "⚠️  安装事务未提交，正在统一回滚"

    if [ "$SERVICE_RESTART_ATTEMPTED" -eq 1 ]; then
        case "$SERVICE_KIND" in
            systemd)
                "$SYSTEMCTL_CMD" stop "${ROLE}.service" >/dev/null 2>&1 || failed=1
                ;;
            openwrt)
                if [ -x "$SERVICE_PATH" ]; then
                    "$SERVICE_PATH" stop >/dev/null 2>&1 || failed=1
                fi
                ;;
        esac
    fi

    if [ "$SERVICE_CREATED" -eq 1 ]; then
        case "$SERVICE_KIND" in
            systemd)
                "$SYSTEMCTL_CMD" disable "${ROLE}.service" >/dev/null 2>&1 || true
                ;;
            openwrt)
                if [ -x "$SERVICE_PATH" ]; then
                    "$SERVICE_PATH" disable >/dev/null 2>&1 || true
                fi
                ;;
        esac
        if ! rm -f "$SERVICE_PATH"; then
            log ERR "❌ 无法清理本次创建的服务文件: $SERVICE_PATH"
            failed=1
        fi
    fi

    if [ "$SERVICE_KIND" = "systemd" ] && [ "$SERVICE_CREATED" -eq 1 ]; then
        "$SYSTEMCTL_CMD" daemon-reload >/dev/null 2>&1 || failed=1
    fi

    if ! restore_binary; then
        log ERR "❌ 旧二进制恢复失败"
        failed=1
    fi

    if [ "$CONFIG_CREATED" -eq 1 ] && ! rm -f "$CONFIG_PATH"; then
        log ERR "❌ 无法清理本次创建的配置: $CONFIG_PATH"
        failed=1
    fi
    if [ "$CONFIG_DIR_CREATED" -eq 1 ] && ! rmdir "$CONFIG_DIR" 2>/dev/null; then
        log ERR "❌ 无法清理本次创建的配置目录: $CONFIG_DIR"
        failed=1
    fi

    if [ "$SERVICE_RESTART_ATTEMPTED" -eq 1 ] && [ "$SERVICE_WAS_ACTIVE" -eq 1 ] \
        && [ "$SERVICE_CREATED" -eq 0 ]; then
        case "$SERVICE_KIND" in
            systemd)
                if ! "$SYSTEMCTL_CMD" restart "${ROLE}.service" >/dev/null 2>&1 \
                    || ! "$SYSTEMCTL_CMD" is-active --quiet "${ROLE}.service" >/dev/null 2>&1; then
                    failed=1
                fi
                ;;
            openwrt)
                if ! "$SERVICE_PATH" restart >/dev/null 2>&1 \
                    || ! "$SERVICE_PATH" status >/dev/null 2>&1; then
                    failed=1
                fi
                ;;
        esac
    fi

    TRANSACTION_ACTIVE=0
    ROLLBACK_IN_PROGRESS=0
    if [ "$failed" -ne 0 ]; then
        PRESERVE_BACKUP=1
        if [ -n "$BINARY_BACKUP" ] && [ -f "$BINARY_BACKUP" ]; then
            log ERR "❌ 回滚不完整，已保留旧二进制备份: $BINARY_BACKUP"
        else
            log ERR "❌ 回滚不完整，本次为首装，没有可保留的旧二进制备份"
        fi
        return 1
    fi

    if [ -n "$BINARY_BACKUP" ]; then
        rm -f "$BINARY_BACKUP" || {
            PRESERVE_BACKUP=1
            log ERR "❌ 回滚已完成，但备份清理失败，已保留: $BINARY_BACKUP"
            return 1
        }
        BINARY_BACKUP=""
    fi
    log OK "✅ 安装事务已回滚"
}

commit_transaction() {
    [ "$TRANSACTION_ACTIVE" -eq 1 ] || return 0
    # 安装后置步骤已成功，此处是事务提交点。
    TRANSACTION_ACTIVE=0
    if [ -n "$BINARY_BACKUP" ]; then
        if ! rm -f "$BINARY_BACKUP"; then
            PRESERVE_BACKUP=1
            log ERR "❌ 事务已提交，但无法清理二进制备份: $BINARY_BACKUP"
            return 1
        fi
        BINARY_BACKUP=""
    fi
    log OK "✅ 安装事务已提交"
}

# =========================
# 🔧 服务注册（OpenWrt init.d / systemd）
# =========================
install_service() {
    log_step "注册系统服务"
    resolve_service_kind
    case "$SERVICE_KIND" in
        openwrt)
            SERVICE_PATH="$INIT_DIR/$ROLE"
            _install_service_openwrt
            ;;
        systemd)
            find_systemd_service_path
            _install_service_systemd
            ;;
        none)
            log WARN "⚠️  未使用 systemd 或 OpenWrt init，请手动管理服务"
            ;;
    esac
}

_install_service_openwrt() {
    if [ ! -d "$INIT_DIR" ]; then
        log ERR "❌ OpenWrt init.d 目录不存在: $INIT_DIR"
        return 1
    fi

    if [ -e "$SERVICE_PATH" ] || [ -L "$SERVICE_PATH" ]; then
        log WARN "⚠️  已存在 $SERVICE_PATH，保留现有服务定义"
        validate_service_file_paths "$SERVICE_PATH"
    else
        STAGED_SERVICE=$(mktemp "$INIT_DIR/.${ROLE}.new.XXXXXX") || return 1
        cat > "$STAGED_SERVICE" <<EOF
#!/bin/sh /etc/rc.common
# FRP ${ROLE} OpenWrt init.d 服务
START=99
STOP=10
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command "$BINARY_PATH" -c "$CONFIG_PATH"
    procd_set_param respawn 3600 5 0
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
        chmod 0755 "$STAGED_SERVICE"
        SERVICE_CREATED=1
        mv -f "$STAGED_SERVICE" "$SERVICE_PATH"
        STAGED_SERVICE=""
    fi

    if [ "$FIRST_INSTALL" -eq 1 ]; then
        log WARN "⚠️  首装已注册服务，但未 enable/start"
        return 0
    fi

    "$SERVICE_PATH" status >/dev/null 2>&1 && SERVICE_WAS_ACTIVE=1 || true
    if [ "$SERVICE_WAS_ACTIVE" -eq 0 ]; then
        log INFO "⏸️  OpenWrt 服务升级前未运行，已保留停止状态"
        return 0
    fi

    SERVICE_RESTART_ATTEMPTED=1
    if ! "$SERVICE_PATH" restart; then
        log ERR "❌ OpenWrt 服务重启失败"
        return 1
    fi

    local waited=0
    while [ "$waited" -lt 10 ]; do
        if "$SERVICE_PATH" status >/dev/null 2>&1; then
            SERVICE_RESTARTED=1
            log OK "✅ OpenWrt 服务已重启: $ROLE（${waited}s）"
            log INFO "  查看日志: logread | grep $ROLE"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
        log INFO "⏳ 等待 OpenWrt 服务启动... (${waited}s)"
    done

    log ERR "❌ OpenWrt 服务重启后未进入运行状态"
    return 1
}

_install_service_systemd() {
    if [ -e "$SERVICE_PATH" ] || [ -L "$SERVICE_PATH" ]; then
        log WARN "⚠️  已存在 $SERVICE_PATH，保留现有服务定义"
        validate_systemd_service_paths
    else
        if [ ! -d "$SYSTEMD_DIR" ]; then
            log ERR "❌ systemd 服务目录不存在: $SYSTEMD_DIR"
            return 1
        fi
        STAGED_SERVICE=$(mktemp "$SYSTEMD_DIR/.${ROLE}.service.new.XXXXXX") || return 1
        cat > "$STAGED_SERVICE" <<EOF
[Unit]
Description=FRP ${ROLE} - Fast Reverse Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BINARY_PATH -c $CONFIG_PATH
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        chmod 0644 "$STAGED_SERVICE"
        SERVICE_CREATED=1
        mv -f "$STAGED_SERVICE" "$SERVICE_PATH"
        STAGED_SERVICE=""
    fi

    "$SYSTEMCTL_CMD" is-active --quiet "${ROLE}.service" 2>/dev/null \
        && SERVICE_WAS_ACTIVE=1 || true

    if [ "$SERVICE_CREATED" -eq 1 ]; then
        if ! "$SYSTEMCTL_CMD" daemon-reload; then
            log ERR "❌ systemd daemon-reload 失败"
            return 1
        fi
    fi

    if [ "$FIRST_INSTALL" -eq 1 ]; then
        log WARN "⚠️  首装已注册服务，但未 enable/start"
        return 0
    fi

    if [ "$SERVICE_WAS_ACTIVE" -eq 0 ]; then
        log INFO "⏸️  systemd 服务升级前未运行，已保留停止状态"
        return 0
    fi

    SERVICE_RESTART_ATTEMPTED=1
    if ! "$SYSTEMCTL_CMD" restart "${ROLE}.service"; then
        log ERR "❌ systemd 服务重启失败"
        return 1
    fi

    local waited=0
    while [ "$waited" -lt 10 ]; do
        if "$SYSTEMCTL_CMD" is-active --quiet "${ROLE}.service" 2>/dev/null; then
            SERVICE_RESTARTED=1
            log OK "✅ systemd 服务已启动: $ROLE（${waited}s）"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
        log INFO "⏳ 等待服务启动... (${waited}s)"
    done

    log ERR "❌ 服务启动失败，最近日志："
    if [ -z "$FRP_ROOT" ] && command_exists journalctl; then
        journalctl -u "$ROLE" -n 20 --no-pager || true
    else
        log WARN "⚠️  测试根目录模式下不读取宿主 journalctl"
    fi
    return 1
}

# =========================
# 🗑 卸载 FRP
# 修复：原版无卸载功能
# =========================
uninstall_frp() {
    log_step "卸载 $ROLE"
    resolve_service_kind

    # 停止并禁用服务
    case "$SERVICE_KIND" in
        openwrt)
            SERVICE_PATH="$INIT_DIR/$ROLE"
            if [ -f "$SERVICE_PATH" ]; then
                "$SERVICE_PATH" stop 2>/dev/null || true
                "$SERVICE_PATH" disable 2>/dev/null || true
                rm -f "$SERVICE_PATH"
                log OK "✅ OpenWrt 服务已移除"
            fi
            ;;
        systemd)
            # 只删除本脚本可能创建的 /etc unit，不破坏软件包管理的 vendor unit。
            SERVICE_PATH="$SYSTEMD_DIR/${ROLE}.service"
            if "$SYSTEMCTL_CMD" is-active --quiet "${ROLE}.service" 2>/dev/null; then
                "$SYSTEMCTL_CMD" stop "${ROLE}.service"
            fi
            "$SYSTEMCTL_CMD" disable "${ROLE}.service" 2>/dev/null || true
            rm -f "$SERVICE_PATH"
            "$SYSTEMCTL_CMD" daemon-reload
            log OK "✅ systemd 服务已移除"
            ;;
    esac

    # 删除二进制
    if [ -f "$BINARY_PATH" ]; then
        rm -f "$BINARY_PATH"
        log OK "✅ 二进制 $BINARY_PATH 已删除"
    fi

    # 询问是否保留配置
    del_cfg=""
    if [ "$ASSUME_YES" -ne 1 ]; then
        printf "\n❓ 是否同时删除配置文件 %s？[y/N]: " "$CONFIG_PATH"
        read -r del_cfg || del_cfg=""
    fi
    case "$del_cfg" in
        y|Y)
            rm -f "$CONFIG_PATH"
            rmdir "$CONFIG_DIR" 2>/dev/null || true
            log OK "✅ 配置文件已删除"
            ;;
        *)
            log INFO "📄 配置文件已保留: $CONFIG_PATH"
            ;;
    esac

    log OK "🎉 $ROLE 卸载完成"
}

# =========================
# 📊 安装摘要
# =========================
show_summary() {
    log_step "安装摘要"
    log OK "🎉 FRP $ROLE 已安装，版本: $LATEST_VERSION"
    log INFO "🔧 二进制: $BINARY_PATH"
    log INFO "📄 配置文件: $CONFIG_PATH"

    if [ "$FIRST_INSTALL" -eq 1 ]; then
        log WARN "🛑 首次安装已完成，服务未启用、未启动"
        log WARN "请先设置 token/OIDC，并核对服务端/监听地址与端口"
        printf "\n${YELLOW}🧪 配置验证:${RESET}\n  %s verify -c %s\n" "$BINARY_PATH" "$CONFIG_PATH"
        case "$SERVICE_KIND" in
            systemd)
                printf "${YELLOW}🚀 验证通过后手动启动:${RESET}\n  %s enable --now %s.service\n\n" "$SYSTEMCTL_CMD" "$ROLE"
                ;;
            openwrt)
                printf "${YELLOW}🚀 验证通过后手动启动:${RESET}\n  %s enable && %s start\n\n" "$SERVICE_PATH" "$SERVICE_PATH"
                ;;
            *)
                printf "${YELLOW}🚀 验证通过后手动启动:${RESET}\n  %s -c %s\n\n" "$BINARY_PATH" "$CONFIG_PATH"
                ;;
        esac
    elif [ "$SERVICE_KIND" = "none" ]; then
        log WARN "⚠️  现有配置已验证，但未检测到服务管理器，未自动重启"
    elif [ "$SERVICE_RESTARTED" -eq 1 ]; then
        log OK "♻️  现有配置已验证，原运行服务已重启"
    else
        log INFO "⏸️  现有配置已验证，服务原先未运行，已保留 active/enabled 状态"
    fi
}

# =========================
# 🚀 主流程
# =========================
main() {
    parse_args "$@"
    require_root

    printf "\n${CYAN}╔══════════════════════════════════════════════╗${RESET}\n"
    printf "${CYAN}║${GREEN}   🌉 FRP 自动安装脚本 v2.1                   ${CYAN}║${RESET}\n"
    printf "${CYAN}║${RESET}   支持 OpenWrt / Linux | frps / frpc          ${CYAN}║${RESET}\n"
    printf "${CYAN}╚══════════════════════════════════════════════╝${RESET}\n\n"

    detect_system

    # --- 操作选择（提前到主流程，修复原版角色选择埋在 install_frp 里）---
    if [ -n "$CLI_ACTION" ]; then
        ACTION="$CLI_ACTION"
    else
        printf "${YELLOW}📦 请选择操作：${RESET}\n"
        printf "   1️⃣   安装 / 更新 FRP\n"
        printf "   2️⃣   卸载 FRP\n"
        printf "❓ 请输入 [1/2]（默认 1）: "
        read -r action_choice || action_choice=""
        case "${action_choice:-1}" in
            1) ACTION="install" ;;
            2) ACTION="uninstall" ;;
            *) log ERR "❌ 无效输入，请输入 1 或 2"; exit 2 ;;
        esac
    fi

    if [ -n "$CLI_ROLE" ]; then
        ROLE="$CLI_ROLE"
    else
        printf "\n${YELLOW}🎭 请选择角色：${RESET}\n"
        printf "   1️⃣   frps（服务端）\n"
        printf "   2️⃣   frpc（客户端）\n"
        printf "❓ 请输入 [1/2]（默认 2）: "
        read -r role_choice || role_choice=""
        case "${role_choice:-2}" in
            1) ROLE="frps" ;;
            2) ROLE="frpc" ;;
            *) log ERR "❌ 无效输入，请输入 1 或 2"; exit 2 ;;
        esac
    fi
    log INFO "🎭 角色: $ROLE"
    set_role_paths

    case "$ACTION" in
        uninstall)
            # 卸载流程
            if [ "$ASSUME_YES" -ne 1 ]; then
                printf "\n${RED}⚠️  即将卸载 $ROLE，是否确认？[y/N]: ${RESET}"
                read -r confirm || confirm=""
                case "$confirm" in
                    y|Y) ;;
                    *) log INFO "👋 已取消"; exit 0 ;;
                esac
            fi
            uninstall_frp
            ;;
        install)
            # 安装 / 更新流程
            for required in tar grep head cut wc tr mktemp sha256sum cat cp mv chmod mkdir rmdir; do
                command_exists "$required" || { log ERR "❌ 缺少必要命令: $required"; exit 1; }
            done
            detect_arch
            detect_fetcher
            get_latest_version
            check_installed_version
            download_frp
            install_frp
            install_service
            commit_transaction
            show_summary
            ;;
    esac
}

main "$@"
