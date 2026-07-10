#!/bin/bash
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
# 🌉 Nginx 编译安装脚本 v2.1
# 支持最新主线版本 / 稳定版本
# By: BuBuXSY
# Version: 2026-07-11
# ====================================================

set -uo pipefail
# 注意：去掉 -e，改为每步手动处理，避免单步失败终止整个流程

[[ "${DEBUG:-0}" == "1" ]] && set -x

# =========================
# 🎨 颜色定义（兼容 bash 3.x，不用关联数组）
# =========================
C_GREEN="\e[1;32m"; C_RED="\e[1;31m"; C_YELLOW="\e[1;33m"
C_BLUE="\e[1;34m"; C_CYAN="\e[1;36m"; C_RESET="\e[0m"

# =========================
# 📋 全局变量
# =========================
LOG_FILE="/var/log/nginx_install_$(date +%Y%m%d_%H%M%S).log"
BUILD_DIR=""
BACKUP_DIR="/var/backups/nginx"
NGINX_USER="nginx"
NGINX_GROUP="nginx"
CPU_CORES=$(nproc 2>/dev/null || echo 1)
KTLS_SUPPORTED=0                       # 默认关闭，preflight 中按内核版本覆盖
VERSION_CHANNEL=""
ASSUME_YES=0
LAST_BINARY_BACKUP=""
LAST_NGINX_CONF_BACKUP=""
LAST_SYSTEMD_UNIT_BACKUP=""
SYSTEMD_UNIT_PATH=""
NGINX_ENABLE_STATE=""
BINARY_WAS_PRESENT=0
NGINX_CONF_WAS_PRESENT=0
SYSTEMD_UNIT_WAS_PRESENT=0
NGINX_WAS_ACTIVE=0
INSTALL_PENDING=0
LOG_READY=0
RUN_STARTED=0

# 固定第三方依赖，避免构建时静默跟随上游 HEAD。
NGX_BROTLI_COMMIT="a71f9312c2deb28875acc7bacfdd5695a111aa53"
NGX_GEOIP2_COMMIT="445df24ef3781e488cee3dfe8a1e111997fc1dfe"
OPENSSL_VERSION="3.5.7"
OPENSSL_COMMIT="8cf17aaeb4599f8af87fefd810b5b5fee90fe69e"
PCRE2_VERSION="10.47"
PCRE2_SHA256="c08ae2388ef333e8403e670ad70c0a11f1eed021fd88308d7e02f596fcd9dc16"
ZLIB_VERSION="1.3.1"
ZLIB_SHA256="9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"

# =========================
# 📖 参数说明
# =========================
usage() {
    cat <<EOF
用法: $0 [--channel mainline|stable] [--yes] [--help]

  --channel  直接选择主线版或稳定版，省略时交互选择
  --yes      跳过安装确认（适合自动化执行）
  --help     显示帮助
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --channel)
                [[ $# -ge 2 ]] || { echo "❌ --channel 缺少参数" >&2; exit 2; }
                case "$2" in
                    mainline|stable) VERSION_CHANNEL="$2" ;;
                    *) echo "❌ 无效版本通道: $2（仅支持 mainline/stable）" >&2; exit 2 ;;
                esac
                shift 2
                ;;
            --yes|-y) ASSUME_YES=1; shift ;;
            --help|-h) usage; exit 0 ;;
            *) echo "❌ 未知参数: $1" >&2; usage >&2; exit 2 ;;
        esac
    done
}

# =========================
# 📋 日志系统
# =========================
print_msg() {
    local level=$1 msg=$2 color emoji
    case $level in
        INFO)    color=$C_BLUE;   emoji="ℹ️ " ;;
        SUCCESS) color=$C_GREEN;  emoji="✅" ;;
        ERROR)   color=$C_RED;    emoji="❌" ;;
        WARN)    color=$C_YELLOW; emoji="⚠️ " ;;
        STEP)    color=$C_CYAN;   emoji="🔧" ;;  # 新增：标记主要步骤
        *)       color=$C_RESET;  emoji="  " ;;
    esac
    local line
    line="$(date '+%H:%M:%S') ${emoji} ${msg}"
    if [[ "$LOG_READY" -eq 1 ]]; then
        echo -e "${color}${line}${C_RESET}" | tee -a "$LOG_FILE"
    else
        echo -e "${color}${line}${C_RESET}"
    fi
}

# 带分隔线的步骤标题，视觉更清晰
print_step() {
    echo -e "\n${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    print_msg STEP "$1"
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
}

# =========================
# 🛡 前置检查
# =========================
preflight() {
    # root 权限检查
    if [[ $EUID -ne 0 ]]; then
        echo -e "${C_RED}❌ 此脚本必须以 root 权限运行（请使用 sudo 或切换到 root）${C_RESET}" >&2
        exit 1
    fi

    # 日志目录必须先建，后续所有 print_msg 才能写入
    mkdir -p "$(dirname "$LOG_FILE")" || { echo "❌ 无法创建日志目录"; exit 1; }
    touch "$LOG_FILE" || { echo "❌ 无法创建日志文件: $LOG_FILE"; exit 1; }
    LOG_READY=1
    RUN_STARTED=1
    print_step "前置检查"

    if ! command -v mktemp >/dev/null 2>&1; then
        print_msg ERROR "缺少必要命令: mktemp"
        exit 1
    fi
    BUILD_DIR=$(umask 077; mktemp -d /tmp/nginx-build.XXXXXX) \
        || { print_msg ERROR "无法创建安全的临时编译目录"; exit 1; }
    chmod 0700 "$BUILD_DIR" \
        || { print_msg ERROR "无法设置临时编译目录权限"; exit 1; }

    if ! command -v systemctl >/dev/null 2>&1; then
        print_msg ERROR "未检测到 systemd，本脚本当前仅支持 systemd 服务管理"
        exit 1
    fi

    # 磁盘空间检查（编译 OpenSSL + nginx 至少需要 2GB 临时空间）
    # 修复：原脚本缺少磁盘检查，低磁盘时编译到中途才报错，浪费时间
    local free_mb
    free_mb=$(df -m /tmp | awk 'NR==2{print $4}')
    if [[ "$free_mb" -lt 2048 ]]; then
        print_msg ERROR "/tmp 剩余空间不足（当前 ${free_mb}MB，需要至少 2048MB）"
        print_msg INFO  "建议：df -h /tmp 查看后清理或更换 BUILD_DIR 路径"
        exit 1
    fi
    print_msg INFO "磁盘空间检查通过（/tmp 可用 ${free_mb}MB）"

    # 内核版本检查（kTLS 需要 4.17+）
    local kver
    kver=$(uname -r | awk -F'[.-]' '{print $1*10000+$2*100+$3}')
    if [[ "$kver" -ge 41700 ]]; then
        KTLS_SUPPORTED=1
        print_msg INFO "内核 $(uname -r) 支持 kTLS ✓"
    else
        KTLS_SUPPORTED=0
        print_msg WARN "内核 $(uname -r) 低于 4.17，将禁用 kTLS"
    fi

    # 查询版本与确认安装前不应修改系统，因此基础查询命令必须预先可用。
    local missing=()
    for cmd in curl timeout awk grep sort tail id getent find; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_msg ERROR "缺少查询版本所需基础命令: ${missing[*]}"
        print_msg INFO "请先安装以上命令，再重新运行脚本"
        exit 1
    fi

    missing=()
    for cmd in wget tar make gcc git sed install sha256sum gpg gpgv; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_msg WARN "以下命令未找到（将在安装依赖后重新检查）: ${missing[*]}"
    fi

    print_msg SUCCESS "前置检查完成（🖥️  CPU: ${CPU_CORES} 核 | 🐧 内核: $(uname -r)）"
}

detect_nginx_identity() {
    [[ -f /etc/nginx/nginx.conf ]] || return 0

    local identity configured_user configured_group
    identity=$(awk '
        {
            sub(/#.*/, "")
            if ($1 == "user") {
                gsub(/;/, "", $2)
                gsub(/;/, "", $3)
                print $2, $3
                exit
            }
        }
    ' /etc/nginx/nginx.conf)
    configured_user=${identity%% *}
    configured_group=${identity#* }
    [[ "$configured_group" != "$identity" ]] || configured_group=""

    if [[ -z "$configured_user" ]]; then
        print_msg WARN "现有 nginx.conf 未声明 worker 用户，将沿用脚本默认值 $NGINX_USER"
        return 0
    fi
    if ! id -u "$configured_user" >/dev/null 2>&1; then
        print_msg ERROR "现有 nginx.conf 指定了不存在的用户: $configured_user"
        exit 1
    fi

    NGINX_USER="$configured_user"
    if [[ -n "$configured_group" ]]; then
        NGINX_GROUP="$configured_group"
    else
        NGINX_GROUP=$(id -gn "$configured_user") \
            || { print_msg ERROR "无法确定 $configured_user 的主组"; exit 1; }
    fi
    print_msg INFO "保留现有 Nginx worker 身份: $NGINX_USER:$NGINX_GROUP"
}

# =========================
# 🌐 网络检查（TCP 替代 ICMP，兼容禁 ping 的云服务器）
# =========================
check_network() {
    print_step "网络连通性检查"
    local ok=0
    for host_port in "nginx.org:80" "github.com:443" "8.8.8.8:53"; do
        local h="${host_port%%:*}" p="${host_port##*:}"
        if timeout 3 bash -c ">/dev/tcp/$h/$p" 2>/dev/null; then
            ok=1
            print_msg INFO "连通测试通过 ➜ $host_port"
            break
        fi
    done
    if [[ "$ok" -eq 0 ]]; then
        print_msg ERROR "所有测试节点均无法连通，请检查网络或防火墙设置"
        exit 1
    fi
    print_msg SUCCESS "网络连接正常 🌐"
}

# =========================
# 🖥 系统检测
# =========================
detect_os() {
    print_step "系统环境检测"
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS="${ID:-unknown}"
        VER="${VERSION_ID:-unknown}"
    else
        print_msg ERROR "无法检测操作系统（/etc/os-release 不存在）"
        exit 1
    fi
    print_msg SUCCESS "检测到系统: 🐧 $OS $VER"
}

# =========================
# 📦 安装依赖
# =========================
install_dependencies() {
    print_step "安装编译依赖"
    case $OS in
        ubuntu|debian)
            print_msg INFO "使用 apt 安装依赖..."
            apt-get update -qq
            apt-get install -y \
                build-essential ca-certificates zlib1g-dev \
                libpcre2-dev libssl-dev libgd-dev libgeoip-dev \
                libxslt1-dev libxml2-dev libmaxminddb-dev \
                autoconf libtool pkg-config wget curl git cmake gnupg gpgv findutils \
                || { print_msg ERROR "依赖安装失败，请检查 apt 源"; exit 1; }
            ;;
        centos|rhel|almalinux|rocky)
            print_msg INFO "使用 yum 安装依赖..."
            yum install -y epel-release
            yum install -y \
                gcc gcc-c++ make ca-certificates zlib-devel \
                pcre2-devel openssl-devel gd-devel GeoIP-devel \
                libxslt-devel libxml2-devel libmaxminddb-devel \
                wget curl git cmake autoconf libtool pkgconfig gnupg2 findutils \
                || { print_msg ERROR "依赖安装失败，请检查 yum 源"; exit 1; }
            ;;
        fedora)
            print_msg INFO "使用 dnf 安装依赖..."
            dnf install -y \
                gcc gcc-c++ make ca-certificates zlib-devel \
                pcre2-devel openssl-devel gd-devel GeoIP-devel \
                libxslt-devel libxml2-devel libmaxminddb-devel \
                wget curl git cmake autoconf libtool pkgconfig gnupg2 findutils \
                || { print_msg ERROR "依赖安装失败，请检查 dnf 源"; exit 1; }
            ;;
        *)
            print_msg ERROR "不支持的发行版: $OS（仅支持 ubuntu/debian/centos/rhel/almalinux/rocky/fedora）"
            exit 1
            ;;
    esac
    print_msg SUCCESS "编译依赖安装完成 📦"
}

# =========================
# 👤 创建 nginx 用户
# 修复：改为先建目录、再建用户，避免 useradd 时 home 目录不存在的警告
# =========================
create_nginx_user() {
    print_step "创建 nginx 系统用户"
    # 先确保 home 目录存在（useradd 不会自动创建 -r 用户的 home）
    mkdir -p /var/cache/nginx \
        || { print_msg ERROR "无法创建 /var/cache/nginx"; exit 1; }

    if ! getent group "$NGINX_GROUP" >/dev/null 2>&1; then
        groupadd --system "$NGINX_GROUP" \
            || { print_msg ERROR "无法创建系统组: $NGINX_GROUP"; exit 1; }
        print_msg SUCCESS "已创建系统组: $NGINX_GROUP"
    fi

    if ! id -u "$NGINX_USER" &>/dev/null; then
        local nologin_shell
        nologin_shell=$(command -v nologin 2>/dev/null || printf '/sbin/nologin')
        useradd -r -g "$NGINX_GROUP" -s "$nologin_shell" -d /var/cache/nginx \
                -c "Nginx web server" "$NGINX_USER" \
            || { print_msg ERROR "无法创建系统用户: $NGINX_USER"; exit 1; }
        print_msg SUCCESS "已创建系统用户: $NGINX_USER 👤"
    else
        print_msg INFO "nginx 用户已存在，跳过创建"
        if ! id -nG "$NGINX_USER" | tr ' ' '\n' | grep -Fxq "$NGINX_GROUP"; then
            usermod -a -G "$NGINX_GROUP" "$NGINX_USER" \
                || { print_msg ERROR "无法将 $NGINX_USER 加入 $NGINX_GROUP 组"; exit 1; }
        fi
    fi
}

# =========================
# 📁 创建必要目录
# =========================
create_directories() {
    print_step "初始化目录结构"
    local dirs=(
        /var/cache/nginx/client_temp /var/cache/nginx/proxy_temp
        /var/cache/nginx/fastcgi_temp /var/cache/nginx/uwsgi_temp
        /var/cache/nginx/scgi_temp /var/log/nginx /etc/nginx/conf.d
        /etc/nginx/sites-available /etc/nginx/sites-enabled
        /etc/nginx/default.d
    )
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir" \
            || { print_msg ERROR "无法创建目录: $dir"; exit 1; }
    done
    install -d -m 0700 "$BACKUP_DIR" \
        || { print_msg ERROR "无法创建安全备份目录: $BACKUP_DIR"; exit 1; }
    if [[ ! -d /usr/share/nginx/html ]]; then
        install -d -o root -g root -m 0755 /usr/share/nginx/html \
            || { print_msg ERROR "无法创建默认站点目录"; exit 1; }
    fi
    chown -R "$NGINX_USER:$NGINX_GROUP" /var/cache/nginx 2>/dev/null \
        || { print_msg ERROR "无法设置 Nginx 缓存目录所有权"; exit 1; }
    validate_default_site_permissions
    print_msg SUCCESS "目录结构初始化完成 📁"
}

validate_default_site_permissions() {
    local insecure_path
    insecure_path=$(find /usr/share/nginx -xdev \
        \( -user "$NGINX_USER" -perm -u=w \
        -o -group "$NGINX_GROUP" -perm -g=w \
        -o -perm -o=w \) -print -quit 2>/dev/null) \
        || { print_msg ERROR "无法检查默认站点目录权限"; exit 1; }
    if [[ -n "$insecure_path" ]]; then
        print_msg ERROR "默认站点存在 Nginx worker 可写路径: $insecure_path"
        print_msg INFO "请由管理员按站点需求修正 owner/group/mode，脚本不会递归改写现有资源权限"
        exit 1
    fi
}

# =========================
# 🔍 获取 Nginx 版本
# 修复：原版用 HTML 解析，官网改版即失效且正则脆弱。
# 改为从 nginx.org/download/ 的 .tar.gz 文件列表解析，更稳定。
# =========================
get_nginx_version() {
    local channel="${1:-mainline}"
    print_msg INFO "🔍 查询 Nginx ${channel} 最新版本..." >&2

    # 从下载目录直接解析文件名，比解析 HTML 更稳定
    local all_versions
    all_versions=$(curl -sf --max-time 15 "https://nginx.org/download/" \
        | grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
        | sort -Vu)

    if [[ -z "$all_versions" ]]; then
        print_msg ERROR "❌ 无法获取版本列表，请检查网络或 nginx.org 是否可达" >&2
        exit 1
    fi

    local version
    if [[ "$channel" == "stable" ]]; then
        # 次版本号为偶数 = 稳定版
        version=$(echo "$all_versions" \
            | awk -F'.' '$2 % 2 == 0 {print}' \
            | tail -1)
    else
        # 最新版（含主线，次版本号为奇数）
        version=$(echo "$all_versions" | tail -1)
    fi

    if [[ -z "$version" ]]; then
        print_msg ERROR "❌ 无法解析 ${channel} 版本" >&2
        exit 1
    fi

    print_msg INFO "📌 找到版本: nginx-$version" >&2
    printf "nginx-%s" "$version"
}

# =========================
# 📥 下载与密码学校验
# 修复：--show-progress 在非 TTY（CI/cron）环境输出乱码，改为按 TTY 自动切换
# =========================
download_resource() {
    local url=$1 output=$2 desc=$3 min_size=${4:-1}
    print_msg INFO "⬇️  下载 $desc ..."

    # 非 TTY 环境（CI/定时任务）关闭进度条，避免日志乱码
    local wget_args=(-q --timeout=60 --tries=1)
    [[ -t 1 ]] && wget_args+=(--show-progress)

    local ok=0
    for attempt in 1 2 3; do
        rm -f "$output"
        if wget "${wget_args[@]}" "$url" -O "$output" 2>&1 | tee -a "$LOG_FILE"; then
            ok=1; break
        fi
        if [[ "$attempt" -lt 3 ]]; then
            print_msg WARN "第 $attempt 次下载失败，${attempt}0 秒后重试..."
            sleep $((attempt * 10))
        fi
    done

    if [[ "$ok" -eq 0 ]]; then
        rm -f "$output"
        print_msg ERROR "❌ 下载 $desc 失败（已重试 3 次）"
        return 1
    fi

    local size
    size=$(wc -c < "$output")
    if [[ "$size" -lt "$min_size" ]]; then
        rm -f "$output"
        print_msg ERROR "❌ $desc 体积异常（${size}B，至少应为 ${min_size}B）"
        return 1
    fi

    print_msg SUCCESS "✅ 下载完成: $desc（$(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B")）"
}

validate_tar_archive() {
    local archive=$1 desc=$2

    local archive_list
    if ! archive_list=$(tar -tzf "$archive" 2>/dev/null); then
        rm -f "$archive"
        print_msg ERROR "❌ $desc 不是有效的 tar.gz 压缩包"
        return 1
    fi
    if grep -Eq '(^/|(^|/)\.\.(/|$))' <<< "$archive_list"; then
        rm -f "$archive"
        print_msg ERROR "❌ $desc 包含不安全路径，已拒绝使用"
        return 1
    fi
}

download_verified_archive() {
    local url=$1 output=$2 desc=$3 expected_sha256=$4

    [[ "$expected_sha256" =~ ^[0-9a-f]{64}$ ]] \
        || { print_msg ERROR "$desc 缺少有效的固定 SHA-256"; return 1; }
    download_resource "$url" "$output" "$desc" 1024 || return 1

    local actual_sha256
    actual_sha256=$(sha256sum "$output" | awk '{print $1}') \
        || { rm -f "$output"; print_msg ERROR "$desc SHA-256 计算失败"; return 1; }
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        rm -f "$output"
        print_msg ERROR "$desc SHA-256 不匹配（期望 $expected_sha256，实际 $actual_sha256）"
        return 1
    fi

    validate_tar_archive "$output" "$desc" || return 1
    print_msg SUCCESS "$desc SHA-256 校验通过 🔐"
}

download_nginx_source() {
    local version=$1 output=$2
    local signature="$output.asc"
    local keyring="$BUILD_DIR/nginx-source-signers.gpg"
    local verify_status signer
    local -a key_specs=(
        "arut|43387825DDB1BB97EC36BA5D007C8D7C15D87369"
        "pluknet|D6786CE303D9A9022998DC6CC8464D549AF75C0A"
        "sb|7338973069ED3F443F4D37DFA64FD5B17ADB39A8"
        "thresh|13C82A63B603576156E30A4EA0EA981B66B0D967"
    )

    [[ "$version" =~ ^nginx-[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || { print_msg ERROR "Nginx 版本格式非法: $version"; return 1; }
    download_resource "https://nginx.org/download/${version}.tar.gz" \
        "$output" "Nginx ${version} 源码" 1024 || return 1
    validate_tar_archive "$output" "Nginx ${version} 源码" || return 1
    download_resource "https://nginx.org/download/${version}.tar.gz.asc" \
        "$signature" "Nginx ${version} 源码签名" 128 || return 1

    : > "$keyring" || { print_msg ERROR "无法创建 Nginx 验签密钥环"; return 1; }
    chmod 0600 "$keyring" || return 1

    local spec key_name expected_fingerprint key_file key_packet actual_fingerprint
    for spec in "${key_specs[@]}"; do
        key_name=${spec%%|*}
        expected_fingerprint=${spec##*|}
        key_file="$BUILD_DIR/nginx-${key_name}.key"
        key_packet="$BUILD_DIR/nginx-${key_name}.gpg"
        download_resource "https://nginx.org/keys/${key_name}.key" \
            "$key_file" "Nginx 官方签名公钥 ${key_name}" 128 || return 1
        actual_fingerprint=$(gpg --batch --show-keys --with-colons --fingerprint \
            "$key_file" 2>> "$LOG_FILE" \
            | awk -F: '$1 == "fpr" {print $10; exit}')
        if [[ "$actual_fingerprint" != "$expected_fingerprint" ]]; then
            print_msg ERROR "Nginx 公钥 ${key_name} 指纹不匹配"
            return 1
        fi
        if ! gpg --batch --yes --dearmor --output "$key_packet" \
            "$key_file" 2>> "$LOG_FILE"; then
            print_msg ERROR "Nginx 公钥 ${key_name} 转换失败"
            return 1
        fi
        cat "$key_packet" >> "$keyring" \
            || { print_msg ERROR "Nginx 验签密钥环写入失败"; return 1; }
    done

    if ! verify_status=$(gpgv --status-fd 1 --keyring "$keyring" \
        "$signature" "$output" 2>> "$LOG_FILE"); then
        rm -f "$output" "$signature"
        print_msg ERROR "Nginx ${version} 官方签名校验失败"
        return 1
    fi
    signer=$(awk '$2 == "VALIDSIG" {print $3; exit}' <<< "$verify_status")
    case "$signer" in
        43387825DDB1BB97EC36BA5D007C8D7C15D87369|\
        D6786CE303D9A9022998DC6CC8464D549AF75C0A|\
        7338973069ED3F443F4D37DFA64FD5B17ADB39A8|\
        13C82A63B603576156E30A4EA0EA981B66B0D967) ;;
        *)
            rm -f "$output" "$signature"
            print_msg ERROR "Nginx 源码签名者不在固定白名单中: ${signer:-未知}"
            return 1
            ;;
    esac

    print_msg SUCCESS "Nginx ${version} 官方签名校验通过（${signer: -16}）🔐"
}

clone_pinned_repo() {
    local url=$1 destination=$2 commit=$3 desc=$4 actual_commit
    local attempt ok=0

    [[ "$commit" =~ ^[0-9a-f]{40}$ ]] \
        || { print_msg ERROR "$desc 缺少有效的固定 commit"; return 1; }
    [[ "$destination" == "$BUILD_DIR/"* ]] \
        || { print_msg ERROR "$desc 目标目录不在安全编译目录内"; return 1; }

    for attempt in 1 2 3; do
        rm -rf -- "$destination"
        if git init -q "$destination" \
            && git -C "$destination" remote add origin "$url" \
            && git -C "$destination" fetch --quiet --depth=1 --no-tags origin "$commit" \
            && git -C "$destination" checkout --quiet --detach FETCH_HEAD; then
            ok=1
            break
        fi
        if [[ "$attempt" -lt 3 ]]; then
            print_msg WARN "$desc 第 $attempt 次下载失败，稍后重试..."
            sleep $((attempt * 5))
        fi
    done
    if [[ "$ok" -ne 1 ]]; then
        print_msg ERROR "$desc 固定提交下载失败"
        return 1
    fi
    actual_commit=$(git -C "$destination" rev-parse HEAD 2>/dev/null || true)
    if [[ "$actual_commit" != "$commit" ]]; then
        print_msg ERROR "$desc commit 不匹配（期望 $commit，实际 ${actual_commit:-未知}）"
        return 1
    fi
    print_msg SUCCESS "$desc 固定提交校验通过（${commit:0:12}）🔐"
}

# =========================
# 📦 下载编译依赖模块
# =========================
download_dependencies() {
    print_step "下载编译依赖模块"
    [[ -n "$BUILD_DIR" && -d "$BUILD_DIR" && ! -L "$BUILD_DIR" ]] \
        || { print_msg ERROR "临时编译目录无效"; exit 1; }

    # --- ngx_brotli（固定提交及其 submodule commit）---
    if [[ ! -d "$BUILD_DIR/ngx_brotli" ]]; then
        print_msg INFO "📥 下载固定版本 ngx_brotli..."
        clone_pinned_repo https://github.com/google/ngx_brotli.git \
            "$BUILD_DIR/ngx_brotli" "$NGX_BROTLI_COMMIT" "ngx_brotli" \
            || exit 1
        git -C "$BUILD_DIR/ngx_brotli" submodule update \
            --init --recursive --depth=1 \
            || { print_msg ERROR "ngx_brotli submodule 下载失败"; exit 1; }
        if git -C "$BUILD_DIR/ngx_brotli" submodule status --recursive \
            | grep -Eq '^[+-U]'; then
            print_msg ERROR "ngx_brotli submodule 未处于固定提交"
            exit 1
        fi
        print_msg SUCCESS "ngx_brotli 固定版本准备完成 ✅"
    else
        print_msg INFO "ngx_brotli 已存在，跳过克隆"
    fi

    # --- ngx_http_geoip2_module（固定提交）---
    if [[ ! -d "$BUILD_DIR/ngx_http_geoip2_module" ]]; then
        print_msg INFO "📥 下载固定版本 ngx_http_geoip2_module..."
        clone_pinned_repo https://github.com/leev/ngx_http_geoip2_module.git \
            "$BUILD_DIR/ngx_http_geoip2_module" "$NGX_GEOIP2_COMMIT" \
            "ngx_http_geoip2_module" || exit 1
        print_msg SUCCESS "ngx_http_geoip2_module 固定版本准备完成 ✅"
    else
        print_msg INFO "ngx_http_geoip2_module 已存在，跳过克隆"
    fi

    # --- OpenSSL（固定 LTS release commit）---
    if [[ ! -d "$BUILD_DIR/openssl" ]]; then
        print_msg INFO "📌 使用固定 OpenSSL LTS: $OPENSSL_VERSION"
        clone_pinned_repo https://github.com/openssl/openssl.git \
            "$BUILD_DIR/openssl" "$OPENSSL_COMMIT" \
            "OpenSSL $OPENSSL_VERSION" || exit 1
    else
        print_msg INFO "OpenSSL 已存在，跳过克隆"
    fi

    # --- PCRE2（固定 release 资产及 SHA-256）---
    if [[ ! -d "$BUILD_DIR/pcre2" ]]; then
        local pcre2_ver="$PCRE2_VERSION"
        local pcre2_tag="pcre2-${pcre2_ver}"
        local pcre2_tar="$BUILD_DIR/${pcre2_tag}.tar.gz"
        local pcre2_url="https://github.com/PCRE2Project/pcre2/releases/download/${pcre2_tag}/${pcre2_tag}.tar.gz"

        print_msg INFO "📌 使用 PCRE2: $pcre2_tag"
        download_verified_archive "$pcre2_url" "$pcre2_tar" \
            "PCRE2 $pcre2_ver" "$PCRE2_SHA256" \
            || { print_msg ERROR "PCRE2 下载失败"; exit 1; }

        local top_dir
        top_dir=$(tar -tzf "$pcre2_tar" | head -1 | cut -d/ -f1)
        tar -xzf "$pcre2_tar" -C "$BUILD_DIR" \
            || { print_msg ERROR "PCRE2 解压失败"; exit 1; }
        mv "$BUILD_DIR/$top_dir" "$BUILD_DIR/pcre2" \
            || { print_msg ERROR "PCRE2 目录重命名失败"; exit 1; }
        rm -f "$pcre2_tar"
        print_msg SUCCESS "PCRE2 $pcre2_ver 准备完成 ✅"
    else
        print_msg INFO "PCRE2 已存在，跳过下载"
    fi

    # --- zlib（固定 release 资产及 SHA-256）---
    if [[ ! -d "$BUILD_DIR/zlib" ]]; then
        local zlib_ver="$ZLIB_VERSION"
        local zlib_tar="$BUILD_DIR/zlib-${zlib_ver}.tar.gz"
        local zlib_url="https://github.com/madler/zlib/releases/download/v${zlib_ver}/zlib-${zlib_ver}.tar.gz"

        download_verified_archive "$zlib_url" "$zlib_tar" \
            "zlib $zlib_ver" "$ZLIB_SHA256" \
            || { print_msg ERROR "zlib 下载失败"; exit 1; }

        # 先获取顶层目录名再解压，避免 tar 路径假设（可移植）
        local top_dir
        top_dir=$(tar -tzf "$zlib_tar" | head -1 | cut -d/ -f1)
        tar -xzf "$zlib_tar" -C "$BUILD_DIR" \
            || { print_msg ERROR "zlib 解压失败"; exit 1; }
        mv "$BUILD_DIR/$top_dir" "$BUILD_DIR/zlib" \
            || { print_msg ERROR "zlib 目录重命名失败"; exit 1; }
        rm -f "$zlib_tar"
        print_msg SUCCESS "zlib $zlib_ver 准备完成 ✅"
    else
        print_msg INFO "zlib 已存在，跳过下载"
    fi
}

# =========================
# 💾 备份现有 Nginx
# =========================
backup_nginx() {
    print_step "备份现有 Nginx"
    local ts
    ts=$(date +%Y%m%d_%H%M%S)

    if [[ -x /usr/sbin/nginx ]]; then
        BINARY_WAS_PRESENT=1
        LAST_BINARY_BACKUP="$BACKUP_DIR/nginx_${ts}.bin"
        cp -p /usr/sbin/nginx "$LAST_BINARY_BACKUP" \
            || { print_msg ERROR "现有 Nginx 二进制备份失败，停止升级"; exit 1; }
        chmod 0600 "$LAST_BINARY_BACKUP" \
            || { print_msg ERROR "二进制备份权限设置失败"; exit 1; }
        print_msg INFO "二进制备份: $LAST_BINARY_BACKUP"
    else
        print_msg INFO "未检测到已安装的 Nginx，将按首次安装处理"
    fi

    if [[ -f /etc/nginx/nginx.conf ]]; then
        NGINX_CONF_WAS_PRESENT=1
        LAST_NGINX_CONF_BACKUP="$BACKUP_DIR/nginx_${ts}.conf"
        cp -p /etc/nginx/nginx.conf "$LAST_NGINX_CONF_BACKUP" \
            || { print_msg ERROR "现有 nginx.conf 备份失败，停止升级"; exit 1; }
        chmod 0600 "$LAST_NGINX_CONF_BACKUP" \
            || { print_msg ERROR "配置备份权限设置失败"; exit 1; }
    fi

    SYSTEMD_UNIT_PATH=$(systemctl show -p FragmentPath --value nginx.service 2>/dev/null || true)
    NGINX_ENABLE_STATE=$(systemctl is-enabled nginx.service 2>/dev/null || true)
    if [[ -n "$SYSTEMD_UNIT_PATH" ]]; then
        SYSTEMD_UNIT_WAS_PRESENT=1
        if [[ -f "$SYSTEMD_UNIT_PATH" ]]; then
            LAST_SYSTEMD_UNIT_BACKUP="$BACKUP_DIR/nginx_${ts}.service"
            cp -p "$SYSTEMD_UNIT_PATH" "$LAST_SYSTEMD_UNIT_BACKUP" \
                || { print_msg ERROR "现有 systemd 单元备份失败，停止升级"; exit 1; }
            chmod 0600 "$LAST_SYSTEMD_UNIT_BACKUP" \
                || { print_msg ERROR "systemd 单元备份权限设置失败"; exit 1; }
        fi
        print_msg INFO "保留现有 systemd 单元: $SYSTEMD_UNIT_PATH"
    fi

    if systemctl is-active --quiet nginx 2>/dev/null; then
        NGINX_WAS_ACTIVE=1
    fi

    if [[ -d /etc/nginx ]]; then
        local config_archive="$BACKUP_DIR/nginx_${ts}_config.tar.gz"
        if (umask 077; tar -czf "$config_archive" -C /etc nginx); then
            chmod 0600 "$config_archive" \
                || { print_msg ERROR "配置归档权限设置失败"; exit 1; }
            print_msg INFO "配置备份: $config_archive"
        else
            print_msg ERROR "Nginx 配置归档备份失败，停止升级"
            exit 1
        fi
    fi
    INSTALL_PENDING=1
    print_msg SUCCESS "备份完成 💾"
}

# =========================
# 🔧 检测 CPU 特性，生成最优 CFLAGS
# =========================
get_cpu_flags() {
    local flags="-march=native -mtune=native"
    # 按优先级依次检测，取最高可用指令集
    if grep -q "avx512" /proc/cpuinfo 2>/dev/null; then
        flags+=" -mavx512f"
    elif grep -q "avx2" /proc/cpuinfo 2>/dev/null; then
        flags+=" -mavx2"
    elif grep -q "avx" /proc/cpuinfo 2>/dev/null; then
        flags+=" -mavx"
    fi
    echo "$flags"
}

# =========================
# ⚙️  编译并安装 Nginx
# 修复：增加源码目录存在性检查，避免 cd 到不存在的路径后静默失败
# =========================
compile_and_install() {
    local version=$1
    local src_dir="$BUILD_DIR/$version"
    print_step "编译安装 Nginx $version"

    # 源码目录存在性检查（修复：原版直接 cd，目录不存在时静默失败）
    if [[ ! -d "$src_dir" ]]; then
        print_msg ERROR "源码目录不存在: $src_dir（解压可能失败）"
        exit 1
    fi
    cd "$src_dir" || { print_msg ERROR "无法进入源码目录: $src_dir"; exit 1; }

    # --- OpenSSL 3.x ASN1_INTEGER 兼容补丁 ---
    # 背景：OpenSSL 3.x 将 ASN1_INTEGER 改为 opaque type，
    #       nginx OCSP Stapling 代码直接访问 .data/.length 会编译报错。
    local stapling_src="$src_dir/src/event/ngx_event_openssl_stapling.c"
    if grep -q "serial->data" "$stapling_src" 2>/dev/null; then
        print_msg INFO "🩹 应用 OpenSSL 3.x ASN1_INTEGER 兼容补丁..."
        sed -i 's/serial->data/ASN1_STRING_get0_data(serial)/g' "$stapling_src"
        sed -i 's/serial->length/ASN1_STRING_length(serial)/g' "$stapling_src"
        print_msg SUCCESS "补丁已应用 ✅"
    fi

    # --- 构建参数 ---
    local openssl_opts="enable-ec_nistp_64_gcc_128 no-nextprotoneg no-weak-ssl-ciphers no-ssl3 enable-tls1_3"
    [[ "$KTLS_SUPPORTED" -eq 1 ]] && openssl_opts="enable-ktls $openssl_opts"

    local cpu_flags
    cpu_flags=$(get_cpu_flags)
    print_msg INFO "🔧 CPU 特性标志: $cpu_flags"

    # 修复：-O3 在部分 GCC 版本下有优化激进导致的潜在问题，改为 -O2 更稳定；
    #       移除已废弃的 --param=ssp-buffer-size（GCC 10+ 会告警）
    local cflags="-O2 -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong -fPIC $cpu_flags"

    print_msg INFO "⚙️  配置编译选项..."
    CFLAGS="$cflags" CXXFLAGS="$cflags" \
    ./configure \
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/run/nginx.pid \
        --lock-path=/run/nginx.lock \
        --http-client-body-temp-path=/var/cache/nginx/client_temp \
        --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
        --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
        --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
        --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
        --user="$NGINX_USER" \
        --group="$NGINX_GROUP" \
        --with-compat \
        --with-file-aio \
        --with-threads \
        --with-http_addition_module \
        --with-http_auth_request_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_mp4_module \
        --with-http_random_index_module \
        --with-http_realip_module \
        --with-http_secure_link_module \
        --with-http_slice_module \
        --with-http_ssl_module \
        --with-http_stub_status_module \
        --with-http_sub_module \
        --with-http_v2_module \
        --with-http_v3_module \
        --with-mail \
        --with-mail_ssl_module \
        --with-stream \
        --with-stream_realip_module \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-pcre="$BUILD_DIR/pcre2" \
        --with-pcre-jit \
        --with-openssl="$BUILD_DIR/openssl" \
        --with-openssl-opt="$openssl_opts" \
        --with-zlib="$BUILD_DIR/zlib" \
        --add-module="$BUILD_DIR/ngx_brotli" \
        --add-module="$BUILD_DIR/ngx_http_geoip2_module" \
        --with-cc-opt="$cflags" \
        --with-ld-opt="-Wl,-rpath,/usr/lib" \
        || { print_msg ERROR "configure 失败，详情请查看: $LOG_FILE"; exit 1; }

    print_msg INFO "🔨 开始编译（使用 ${CPU_CORES} 核心并行，预计需要几分钟）..."
    make -j"$CPU_CORES" 2>&1 | tee -a "$LOG_FILE" \
        || { print_msg ERROR "编译失败，请查看: $LOG_FILE"; exit 1; }

    # 安装前先验证新二进制。升级时无需提前停止旧进程，避免安装失败造成停机。
    if [[ -f /etc/nginx/nginx.conf ]]; then
        print_msg INFO "🧪 使用新编译二进制预检现有配置..."
        "$src_dir/objs/nginx" -t -c /etc/nginx/nginx.conf 2>&1 | tee -a "$LOG_FILE" \
            || { print_msg ERROR "新二进制无法加载现有配置，已取消安装"; exit 1; }
    elif ! "$src_dir/objs/nginx" -V >/dev/null 2>&1; then
        print_msg ERROR "新编译二进制自检失败"
        exit 1
    fi

    make install 2>&1 | tee -a "$LOG_FILE" \
        || { print_msg ERROR "make install 失败"; exit 1; }
    print_msg SUCCESS "Nginx $version 安装完成 🎉"
}

rollback_installation() {
    [[ "$INSTALL_PENDING" -eq 1 ]] || return 0
    INSTALL_PENDING=0
    local failed=0
    local restore_tmp=""

    print_msg WARN "安装未完成，正在恢复升级前状态..."

    if [[ "$BINARY_WAS_PRESENT" -eq 1 && -f "$LAST_BINARY_BACKUP" ]]; then
        restore_tmp=$(mktemp /usr/sbin/.nginx.restore.XXXXXX) || failed=1
        if [[ -n "$restore_tmp" ]]; then
            cp -p "$LAST_BINARY_BACKUP" "$restore_tmp" \
                && chmod 0755 "$restore_tmp" \
                && mv -f "$restore_tmp" /usr/sbin/nginx \
                || failed=1
            rm -f "$restore_tmp"
        fi
    else
        rm -f /usr/sbin/nginx || failed=1
    fi

    if [[ "$NGINX_CONF_WAS_PRESENT" -eq 1 && -f "$LAST_NGINX_CONF_BACKUP" ]]; then
        install -m 0644 "$LAST_NGINX_CONF_BACKUP" /etc/nginx/nginx.conf || failed=1
    else
        rm -f /etc/nginx/nginx.conf || failed=1
    fi

    if [[ "$SYSTEMD_UNIT_WAS_PRESENT" -eq 0 ]]; then
        systemctl disable nginx.service >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/nginx.service || failed=1
    fi

    systemctl daemon-reload >/dev/null 2>&1 || failed=1
    case "$NGINX_ENABLE_STATE" in
        enabled|enabled-runtime)
            systemctl enable nginx.service >/dev/null 2>&1 || failed=1
            ;;
        disabled)
            systemctl disable nginx.service >/dev/null 2>&1 || failed=1
            ;;
        masked|masked-runtime)
            systemctl mask nginx.service >/dev/null 2>&1 || failed=1
            ;;
    esac
    if [[ "$NGINX_WAS_ACTIVE" -eq 1 ]]; then
        systemctl restart nginx >/dev/null 2>&1 || failed=1
    else
        systemctl stop nginx >/dev/null 2>&1 || true
    fi

    if [[ "$failed" -eq 0 ]]; then
        print_msg SUCCESS "升级前状态已恢复"
        return 0
    fi

    print_msg ERROR "自动回滚不完整，请使用 $BACKUP_DIR 中的备份手动恢复"
    return 1
}

# =========================
# 🔧 修复旧路径（/var/run → /run）
# =========================
fix_existing_paths() {
    if [[ -f /etc/nginx/nginx.conf ]] && grep -q "/var/run/nginx.pid" /etc/nginx/nginx.conf; then
        local bak
        bak="/etc/nginx/nginx.conf.bak.$(date +%Y%m%d_%H%M%S)"
        cp -p /etc/nginx/nginx.conf "$bak" \
            || { print_msg ERROR "nginx.conf PID 路径修复前备份失败"; exit 1; }
        sed -i 's|/var/run/nginx.pid|/run/nginx.pid|g' /etc/nginx/nginx.conf \
            || { cp -p "$bak" /etc/nginx/nginx.conf; print_msg ERROR "nginx.conf PID 路径修复失败"; exit 1; }
        print_msg SUCCESS "🔧 nginx.conf PID 路径已更新（备份: $bak）"
    fi
}

# =========================
# 📝 创建默认 nginx.conf（仅首次安装时）
# =========================
create_nginx_config() {
    if [[ -f /etc/nginx/nginx.conf ]]; then
        print_msg INFO "nginx.conf 已存在，跳过创建（保留现有配置）"
        return 0
    fi
    print_step "创建默认 nginx.conf"
    local conf_tmp="$BUILD_DIR/nginx.conf.new"
    cat > "$conf_tmp" <<EOF
user ${NGINX_USER};
worker_processes auto;
worker_rlimit_nofile 65535;
error_log /var/log/nginx/error.log notice;
pid /run/nginx.pid;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 4096;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    include /etc/nginx/conf.d/*.conf;

    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name _;
        root /usr/share/nginx/html;
        include /etc/nginx/default.d/*.conf;

        location / { index index.html index.htm; }
        error_page 500 502 503 504 /50x.html;
        location = /50x.html { root /usr/share/nginx/html; }
    }
}
EOF
    install -m 0644 "$conf_tmp" /etc/nginx/nginx.conf \
        || { print_msg ERROR "默认 nginx.conf 写入失败"; exit 1; }
    cat > "$BUILD_DIR/index.html.new" <<'HTML'
<!DOCTYPE html><html><head><title>Welcome to nginx!</title></head>
<body><h1>Welcome to nginx!</h1><p>Nginx is successfully installed and working.</p></body></html>
HTML
    if [[ ! -e /usr/share/nginx/html/index.html ]]; then
        install -o root -g root -m 0644 "$BUILD_DIR/index.html.new" \
            /usr/share/nginx/html/index.html \
            || { print_msg ERROR "默认首页写入失败"; exit 1; }
    else
        print_msg INFO "默认首页已存在，保留现有文件"
    fi
    validate_default_site_permissions
    print_msg SUCCESS "默认 nginx.conf 创建完成 📝"
}

# =========================
# 🔧 创建 / 更新 systemd 服务
# =========================
create_systemd_service() {
    print_step "配置 systemd 服务"
    if [[ "$SYSTEMD_UNIT_WAS_PRESENT" -eq 1 ]]; then
        print_msg INFO "检测到现有 nginx.service，保留自定义服务定义"
        return 0
    fi

    local unit_tmp="$BUILD_DIR/nginx.service.new"
    cat > "$unit_tmp" <<'EOF'
[Unit]
Description=The nginx HTTP and reverse proxy server
After=syslog.target network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/usr/sbin/nginx -s reload
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=true
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    install -m 0644 "$unit_tmp" /etc/systemd/system/nginx.service \
        || { print_msg ERROR "systemd 服务文件写入失败"; exit 1; }
    systemctl daemon-reload \
        || { print_msg ERROR "systemd daemon-reload 失败"; exit 1; }
    print_msg SUCCESS "systemd 服务文件已写入并重载 ✅"
}

# =========================
# ✅ 验证安装
# 修复：原版 sleep 1 太短，低配机器服务还未启动就误判失败
#       改为轮询等待，最多 15 秒
# =========================
verify_installation() {
    print_step "验证安装"

    print_msg INFO "🔍 测试 nginx 配置语法..."
    if ! /usr/sbin/nginx -t 2>&1 | tee -a "$LOG_FILE"; then
        print_msg ERROR "Nginx 配置测试失败，请检查配置文件"
        exit 1
    fi

    if [[ "$BINARY_WAS_PRESENT" -eq 0 || "$NGINX_ENABLE_STATE" == "enabled" || "$NGINX_ENABLE_STATE" == "enabled-runtime" ]]; then
        systemctl enable nginx 2>&1 | tee -a "$LOG_FILE" \
            || print_msg WARN "无法设置 Nginx 开机启动，请稍后手动检查"
    else
        print_msg INFO "保留升级前的开机启动状态: ${NGINX_ENABLE_STATE:-unknown}"
    fi

    if [[ "$BINARY_WAS_PRESENT" -eq 1 && "$NGINX_WAS_ACTIVE" -eq 0 ]]; then
        print_msg INFO "升级前 Nginx 未运行，已保留停止状态"
        return 0
    fi

    if ! systemctl restart nginx 2>&1 | tee -a "$LOG_FILE"; then
        print_msg ERROR "Nginx 重启失败"
        exit 1
    fi

    # 轮询等待服务就绪（最多等 15 秒）
    local waited=0
    while ! systemctl is-active --quiet nginx 2>/dev/null && [[ $waited -lt 15 ]]; do
        sleep 1; ((waited++))
        print_msg INFO "⏳ 等待 Nginx 启动... (${waited}s)"
    done

    if systemctl is-active --quiet nginx; then
        print_msg SUCCESS "🚀 Nginx 服务运行正常（启动耗时 ${waited}s）"
    else
        print_msg ERROR "Nginx 服务启动失败，最近 30 条日志如下："
        journalctl -u nginx -n 30 --no-pager | tee -a "$LOG_FILE"
        exit 1
    fi
}

# =========================
# 📊 安装摘要
# =========================
show_summary() {
    local ver modules
    ver=$(/usr/sbin/nginx -v 2>&1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)
    modules=$(/usr/sbin/nginx -V 2>&1 | grep -oE '\-\-with-[a-z_]+' | wc -l)
    echo -e "\n${C_CYAN}╔══════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYAN}║${C_GREEN}  🎉 Nginx $ver 安装完成！                    ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}╠══════════════════════════════════════════════╣${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}  📄 配置文件 : /etc/nginx/nginx.conf         ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}  📂 日志目录 : /var/log/nginx/               ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}  🔑 PID 文件 : /run/nginx.pid                ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}  🧩 编译模块 : ${modules} 个                          ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}  📋 安装日志 : $LOG_FILE  ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}╠══════════════════════════════════════════════╣${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}  🛠  服务管理命令：                           ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}    启动: systemctl start  nginx              ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}    停止: systemctl stop   nginx              ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}    重载: systemctl reload nginx              ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}    状态: systemctl status nginx              ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}╚══════════════════════════════════════════════╝${C_RESET}\n"
}

# =========================
# 🧹 清理 & 错误诊断
# 修复：DEBUG=1 时保留 BUILD_DIR 方便排查；正常模式才清理
# =========================
cleanup() {
    local code=$?
    if [[ "$code" -ne 0 && "$INSTALL_PENDING" -eq 1 ]]; then
        rollback_installation || true
    fi
    if [[ "${DEBUG:-0}" == "1" && -n "$BUILD_DIR" ]]; then
        print_msg WARN "🐛 DEBUG 模式：保留临时目录 $BUILD_DIR 供排查"
    elif [[ -n "$BUILD_DIR" && -d "$BUILD_DIR" ]]; then
        print_msg INFO "🧹 清理临时编译目录..."
        rm -rf "$BUILD_DIR"
    fi
    if [[ $code -ne 0 && "$RUN_STARTED" -eq 1 ]]; then
        echo -e "\n${C_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        print_msg ERROR "安装失败（退出码: $code），诊断建议："
        echo -e "  1️⃣  查看完整日志 : tail -80 $LOG_FILE"
        echo -e "  2️⃣  检查外网连通 : curl -I https://nginx.org"
        echo -e "  3️⃣  检查磁盘空间 : df -h /tmp /usr"
        echo -e "  4️⃣  检查内存余量 : free -h"
        echo -e "  5️⃣  开启调试模式 : DEBUG=1 $0"
        echo -e "${C_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
    fi
    return 0
}
trap cleanup EXIT

# =========================
# 🚀 主流程
# =========================
main() {
    parse_args "$@"

    echo -e "\n${C_CYAN}╔══════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYAN}║${C_GREEN}   🌉 Nginx 编译安装脚本 v2.1                 ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}   By BuBuXSY | License: MIT                  ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}╚══════════════════════════════════════════════╝${C_RESET}\n"

    preflight
    check_network
    detect_os
    detect_nginx_identity

    # --- 版本选择 ---
    local target_version
    if [[ -z "$VERSION_CHANNEL" ]]; then
        echo -e "\n${C_YELLOW}📦 请选择安装的 Nginx 版本通道：${C_RESET}"
        echo    "   1️⃣   最新主线版本（含新功能，适合测试 / 尝鲜）"
        echo    "   2️⃣   最新稳定版本（推荐生产环境）"
        read -rp "$(echo -e "${C_CYAN}▶ 请输入 [1/2]（默认 1）：${C_RESET}")" ver_choice || ver_choice=""
        case "${ver_choice:-1}" in
            1) VERSION_CHANNEL="mainline" ;;
            2) VERSION_CHANNEL="stable" ;;
            *) print_msg ERROR "无效选择，仅支持 1 或 2"; exit 2 ;;
        esac
    fi

    if [[ "$VERSION_CHANNEL" == "stable" ]]; then
        target_version=$(get_nginx_version stable)
    else
        target_version=$(get_nginx_version mainline)
    fi

    # --- 对比当前版本 ---
    local installed_version="未安装"
    if [[ -x /usr/sbin/nginx ]]; then
        installed_version=$(/usr/sbin/nginx -v 2>&1 \
            | grep -oE "nginx/[0-9]+\.[0-9]+\.[0-9]+" \
            | awk -F/ '{print "nginx-"$2}')
    fi

    echo -e "\n${C_BLUE}📌 当前版本：${C_YELLOW}${installed_version}${C_RESET}"
    echo -e "${C_BLUE}📌 目标版本：${C_GREEN}${target_version}${C_RESET}\n"

    if [[ "$installed_version" == "$target_version" ]]; then
        print_msg WARN "⚠️  当前已是最新版本 $target_version"
        if [[ "$ASSUME_YES" -ne 1 ]]; then
            read -rp "$(echo -e "${C_YELLOW}❓ 是否仍要重新编译安装？[y/N]：${C_RESET}")" confirm || confirm=""
            [[ "${confirm,,}" != "y" ]] && { print_msg INFO "已取消，退出 👋"; exit 0; }
        fi
    else
        if [[ "$ASSUME_YES" -ne 1 ]]; then
            read -rp "$(echo -e "${C_YELLOW}❓ 确认安装 ${target_version}？[Y/n]：${C_RESET}")" confirm || confirm=""
            case "${confirm,,}" in
                ""|y|yes) ;;
                n|no) print_msg INFO "已取消，退出 👋"; exit 0 ;;
                *) print_msg ERROR "无效确认输入，请输入 y 或 n"; exit 2 ;;
            esac
        fi
    fi

    # --- 执行安装流程 ---
    install_dependencies
    create_nginx_user
    create_directories
    backup_nginx
    fix_existing_paths
    download_dependencies

    # 下载 Nginx 源码
    local tar_file="$BUILD_DIR/${target_version}.tar.gz"
    download_nginx_source "$target_version" "$tar_file" \
        || { print_msg ERROR "源码下载失败"; exit 1; }

    print_msg INFO "📂 解压源码..."
    tar -xzf "$tar_file" -C "$BUILD_DIR" \
        || { print_msg ERROR "源码解压失败（tar 文件可能不完整）"; exit 1; }
    rm -f "$tar_file"   # 解压后即删，节省 /tmp 空间

    compile_and_install "$target_version"
    create_nginx_config
    create_systemd_service
    verify_installation
    INSTALL_PENDING=0
    show_summary
}

main "$@"
