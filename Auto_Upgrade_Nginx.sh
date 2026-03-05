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
# By: BuBuXSY 2026.3.6
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
BUILD_DIR="/tmp/nginx_build_$$"        # 用 PID 隔离，防多实例冲突
BACKUP_DIR="/var/backups/nginx"
NGINX_USER="nginx"
NGINX_GROUP="nginx"
CPU_CORES=$(nproc 2>/dev/null || echo 1)
KTLS_SUPPORTED=0                       # 默认关闭，preflight 中按内核版本覆盖

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
    echo -e "${color}${line}${C_RESET}" | tee -a "$LOG_FILE"
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
    print_step "前置检查"

    # 日志目录必须先建，后续所有 print_msg 才能写入
    mkdir -p "$(dirname "$LOG_FILE")" || { echo "❌ 无法创建日志目录"; exit 1; }
    touch "$LOG_FILE"

    # root 权限检查
    if [[ $EUID -ne 0 ]]; then
        print_msg ERROR "此脚本必须以 root 权限运行（请使用 sudo 或切换到 root）"
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

    # 必要命令检查
    local missing=()
    for cmd in curl wget tar make gcc git; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_msg WARN "以下命令未找到（将在安装依赖后重新检查）: ${missing[*]}"
    fi

    print_msg SUCCESS "前置检查完成（🖥️  CPU: ${CPU_CORES} 核 | 🐧 内核: $(uname -r)）"
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
                autoconf libtool pkg-config wget curl git cmake \
                || { print_msg ERROR "依赖安装失败，请检查 apt 源"; exit 1; }
            ;;
        centos|rhel|almalinux|rocky)
            print_msg INFO "使用 yum 安装依赖..."
            yum install -y epel-release
            yum install -y \
                gcc gcc-c++ make ca-certificates zlib-devel \
                pcre2-devel openssl-devel gd-devel GeoIP-devel \
                libxslt-devel libxml2-devel libmaxminddb-devel \
                wget curl git cmake autoconf libtool pkgconfig \
                || { print_msg ERROR "依赖安装失败，请检查 yum 源"; exit 1; }
            ;;
        fedora)
            print_msg INFO "使用 dnf 安装依赖..."
            dnf install -y \
                gcc gcc-c++ make ca-certificates zlib-devel \
                pcre2-devel openssl-devel gd-devel GeoIP-devel \
                libxslt-devel libxml2-devel libmaxminddb-devel \
                wget curl git cmake autoconf libtool pkgconfig \
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
    mkdir -p /var/cache/nginx
    if ! id -u "$NGINX_USER" &>/dev/null; then
        useradd -r -s /sbin/nologin -d /var/cache/nginx \
                -c "Nginx web server" "$NGINX_USER"
        print_msg SUCCESS "已创建系统用户: $NGINX_USER 👤"
    else
        print_msg INFO "nginx 用户已存在，跳过创建"
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
        /etc/nginx/default.d /usr/share/nginx/html "$BACKUP_DIR"
    )
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done
    chown -R "$NGINX_USER:$NGINX_GROUP" \
        /var/cache/nginx /var/log/nginx /usr/share/nginx 2>/dev/null || true
    print_msg SUCCESS "目录结构初始化完成 📁"
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
# 📥 下载文件（带重试，自动判断 TTY 决定是否显示进度条）
# 修复：--show-progress 在非 TTY（CI/cron）环境输出乱码，改为按 TTY 自动切换
# =========================
download_file() {
    local url=$1 output=$2 desc=$3
    print_msg INFO "⬇️  下载 $desc ..."

    # 非 TTY 环境（CI/定时任务）关闭进度条，避免日志乱码
    local progress_flag=""
    [[ -t 1 ]] && progress_flag="--show-progress"

    local ok=0
    for attempt in 1 2 3; do
        # shellcheck disable=SC2086
        if wget -q $progress_flag --timeout=60 --tries=1 "$url" -O "$output" 2>&1 | tee -a "$LOG_FILE"; then
            ok=1; break
        fi
        print_msg WARN "第 $attempt 次下载失败，${attempt}0 秒后重试..."
        sleep $((attempt * 10))   # 指数退避：10s / 20s / 30s
    done

    if [[ "$ok" -eq 0 ]]; then
        print_msg ERROR "❌ 下载 $desc 失败（已重试 3 次）"
        return 1
    fi

    # 基础完整性校验（文件不能为空或极小）
    local size
    size=$(wc -c < "$output")
    if [[ "$size" -lt 1024 ]]; then
        print_msg ERROR "❌ 下载文件异常，体积过小（${size}B），可能为错误页面"
        return 1
    fi

    print_msg SUCCESS "✅ 下载完成: $desc（$(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B")）"
}

# =========================
# 📦 下载编译依赖模块
# =========================
download_dependencies() {
    print_step "下载编译依赖模块"
    mkdir -p "$BUILD_DIR"

    # --- ngx_brotli ---
    if [[ ! -d "$BUILD_DIR/ngx_brotli" ]]; then
        print_msg INFO "📥 克隆 ngx_brotli..."
        git clone --depth=1 https://github.com/google/ngx_brotli \
            "$BUILD_DIR/ngx_brotli" \
            && git -C "$BUILD_DIR/ngx_brotli" submodule update --init --recursive \
            || { print_msg ERROR "克隆 ngx_brotli 失败"; exit 1; }
        print_msg SUCCESS "ngx_brotli 克隆完成 ✅"
    else
        print_msg INFO "ngx_brotli 已存在，跳过克隆"
    fi

    # --- ngx_http_geoip2_module ---
    if [[ ! -d "$BUILD_DIR/ngx_http_geoip2_module" ]]; then
        print_msg INFO "📥 克隆 ngx_http_geoip2_module..."
        git clone --depth=1 https://github.com/leev/ngx_http_geoip2_module \
            "$BUILD_DIR/ngx_http_geoip2_module" \
            || { print_msg ERROR "克隆 ngx_http_geoip2_module 失败"; exit 1; }
        print_msg SUCCESS "ngx_http_geoip2_module 克隆完成 ✅"
    else
        print_msg INFO "ngx_http_geoip2_module 已存在，跳过克隆"
    fi

    # --- OpenSSL（锁定最新稳定 tag，避免 master HEAD 破坏性 API 变更）---
    # 背景：OpenSSL 3.x 将 ASN1_INTEGER 改为 opaque type，直接用 HEAD 编译
    #       nginx OCSP Stapling 代码会报错，必须用正式 release tag。
    # 修复：原版 git ls-remote 在国内网络经常超时卡住，增加 --timeout 和超时保护。
    if [[ ! -d "$BUILD_DIR/openssl" ]]; then
        print_msg INFO "🔍 查询 OpenSSL 最新稳定 tag..."
        local ossl_tag
        # timeout 保护：15 秒内拿不到结果就用已知稳定版兜底
        ossl_tag=$(timeout 15 git ls-remote --tags --sort="-v:refname" \
            https://github.com/openssl/openssl.git \
            'refs/tags/openssl-3.*' \
            2>/dev/null \
            | grep -v '\^{}' \
            | grep -v -E 'alpha|beta|pre' \
            | head -1 \
            | awk '{print $2}' \
            | sed 's|refs/tags/||') || true

        if [[ -z "$ossl_tag" ]]; then
            print_msg WARN "⚠️  无法查询 OpenSSL tag（网络超时或受限），回退至已知稳定版 openssl-3.3.2"
            ossl_tag="openssl-3.3.2"
        fi

        print_msg INFO "📌 使用 OpenSSL: $ossl_tag"
        git clone --depth=1 --branch "$ossl_tag" \
            https://github.com/openssl/openssl.git "$BUILD_DIR/openssl" \
            || { print_msg ERROR "克隆 OpenSSL 失败（tag: $ossl_tag）"; exit 1; }
        print_msg SUCCESS "OpenSSL 克隆完成: $ossl_tag ✅"
    else
        print_msg INFO "OpenSSL 已存在，跳过克隆"
    fi

    # --- PCRE2（替代 PCRE，nginx 1.21.5+ 原生支持，JIT 更完善，性能更好）---
    if [[ ! -d "$BUILD_DIR/pcre2" ]]; then
        print_msg INFO "🔍 查询 PCRE2 最新稳定版本..."
        # 从 GitHub releases 获取最新 tag（格式：pcre2-10.xx）
        local pcre2_tag
        pcre2_tag=$(timeout 15 git ls-remote --tags --sort="-v:refname" \
            https://github.com/PCRE2Project/pcre2.git \
            'refs/tags/pcre2-*' \
            2>/dev/null \
            | grep -v '\^{}' \
            | grep -v -E 'alpha|beta|rc' \
            | head -1 \
            | awk '{print $2}' \
            | sed 's|refs/tags/||') || true

        if [[ -z "$pcre2_tag" ]]; then
            print_msg WARN "⚠️  无法查询 PCRE2 tag，回退至已知稳定版 pcre2-10.44"
            pcre2_tag="pcre2-10.44"
        fi

        local pcre2_ver="${pcre2_tag#pcre2-}"   # 提取纯版本号，如 10.44
        local pcre2_tar="$BUILD_DIR/${pcre2_tag}.tar.gz"
        local pcre2_url="https://github.com/PCRE2Project/pcre2/releases/download/${pcre2_tag}/${pcre2_tag}.tar.gz"

        print_msg INFO "📌 使用 PCRE2: $pcre2_tag"
        download_file "$pcre2_url" "$pcre2_tar" "PCRE2 $pcre2_ver" \
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

    # --- zlib ---
    if [[ ! -d "$BUILD_DIR/zlib" ]]; then
        local zlib_ver="1.3.1"
        local zlib_tar="$BUILD_DIR/zlib-${zlib_ver}.tar.gz"
        local primary_url="https://www.zlib.net/zlib-${zlib_ver}.tar.gz"
        local fallback_url="https://github.com/madler/zlib/releases/download/v${zlib_ver}/zlib-${zlib_ver}.tar.gz"

        # 主站可达性探测
        if ! curl -sf --head --max-time 5 "$primary_url" >/dev/null 2>&1; then
            print_msg WARN "⚠️  zlib 主站不可达，切换至 GitHub 镜像"
            primary_url="$fallback_url"
        fi

        download_file "$primary_url" "$zlib_tar" "zlib $zlib_ver" \
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
    if [[ ! -x /usr/sbin/nginx ]]; then
        print_msg INFO "未检测到已安装的 Nginx，跳过备份"
        return 0
    fi
    local ts; ts=$(date +%Y%m%d_%H%M%S)
    cp /usr/sbin/nginx "$BACKUP_DIR/nginx_${ts}.bin" \
        && print_msg INFO "二进制备份: $BACKUP_DIR/nginx_${ts}.bin"
    if [[ -d /etc/nginx ]]; then
        tar -czf "$BACKUP_DIR/nginx_${ts}_config.tar.gz" -C /etc nginx \
            && print_msg INFO "配置备份: $BACKUP_DIR/nginx_${ts}_config.tar.gz"
    fi
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

    # 停止现有服务（先优雅停止，等待连接排空）
    if systemctl is-active --quiet nginx 2>/dev/null; then
        print_msg INFO "⏹️  停止现有 Nginx 服务..."
        systemctl stop nginx
        # 等待进程完全退出，最多 10 秒
        local waited=0
        while pgrep -x nginx >/dev/null 2>&1 && [[ $waited -lt 10 ]]; do
            sleep 1; ((waited++))
        done
        if pgrep -x nginx >/dev/null 2>&1; then
            print_msg WARN "Nginx 进程未完全退出，强制终止..."
            pkill -9 -x nginx 2>/dev/null || true
        fi
    fi

    make install 2>&1 | tee -a "$LOG_FILE" \
        || { print_msg ERROR "make install 失败"; exit 1; }
    print_msg SUCCESS "Nginx $version 安装完成 🎉"
}

# =========================
# 🔧 修复旧路径（/var/run → /run）
# =========================
fix_existing_paths() {
    if [[ -f /etc/nginx/nginx.conf ]] && grep -q "/var/run/nginx.pid" /etc/nginx/nginx.conf; then
        local bak="/etc/nginx/nginx.conf.bak.$(date +%Y%m%d_%H%M%S)"
        cp /etc/nginx/nginx.conf "$bak"
        sed -i 's|/var/run/nginx.pid|/run/nginx.pid|g' /etc/nginx/nginx.conf
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
    cat > /etc/nginx/nginx.conf <<EOF
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
    cat > /usr/share/nginx/html/index.html <<'HTML'
<!DOCTYPE html><html><head><title>Welcome to nginx!</title></head>
<body><h1>Welcome to nginx!</h1><p>Nginx is successfully installed and working.</p></body></html>
HTML
    chown -R "$NGINX_USER:$NGINX_GROUP" /usr/share/nginx/html
    print_msg SUCCESS "默认 nginx.conf 创建完成 📝"
}

# =========================
# 🔧 创建 / 更新 systemd 服务
# =========================
create_systemd_service() {
    print_step "配置 systemd 服务"
    cat > /etc/systemd/system/nginx.service <<'EOF'
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
    systemctl daemon-reload
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
    /usr/sbin/nginx -t 2>&1 | tee -a "$LOG_FILE" \
        || { print_msg ERROR "Nginx 配置测试失败，请检查配置文件"; exit 1; }

    systemctl enable nginx 2>&1 | tee -a "$LOG_FILE"
    systemctl restart nginx 2>&1 | tee -a "$LOG_FILE"

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
    if [[ "${DEBUG:-0}" == "1" ]]; then
        print_msg WARN "🐛 DEBUG 模式：保留临时目录 $BUILD_DIR 供排查"
    elif [[ -d "$BUILD_DIR" ]]; then
        print_msg INFO "🧹 清理临时编译目录..."
        rm -rf "$BUILD_DIR"
    fi
    if [[ $code -ne 0 ]]; then
        echo -e "\n${C_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        print_msg ERROR "安装失败（退出码: $code），诊断建议："
        echo -e "  1️⃣  查看完整日志 : tail -80 $LOG_FILE"
        echo -e "  2️⃣  检查外网连通 : curl -I https://nginx.org"
        echo -e "  3️⃣  检查磁盘空间 : df -h /tmp /usr"
        echo -e "  4️⃣  检查内存余量 : free -h"
        echo -e "  5️⃣  开启调试模式 : DEBUG=1 $0"
        echo -e "${C_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
    fi
}
trap cleanup EXIT

# =========================
# 🚀 主流程
# =========================
main() {
    echo -e "\n${C_CYAN}╔══════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYAN}║${C_GREEN}   🌉 Nginx 编译安装脚本 v2.1                 ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}   By BuBuXSY | License: MIT                  ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}╚══════════════════════════════════════════════╝${C_RESET}\n"

    preflight
    check_network
    detect_os
    install_dependencies

    # --- 版本选择 ---
    echo -e "\n${C_YELLOW}📦 请选择安装的 Nginx 版本通道：${C_RESET}"
    echo    "   1️⃣   最新主线版本（含新功能，适合测试 / 尝鲜）"
    echo    "   2️⃣   最新稳定版本（推荐生产环境）"
    read -rp "$(echo -e "${C_CYAN}▶ 请输入 [1/2]（默认 1）：${C_RESET}")" ver_choice
    ver_choice="${ver_choice:-1}"

    local target_version
    if [[ "$ver_choice" == "2" ]]; then
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
        read -rp "$(echo -e "${C_YELLOW}❓ 是否仍要重新编译安装？[y/N]：${C_RESET}")" confirm
        [[ "${confirm,,}" != "y" ]] && { print_msg INFO "已取消，退出 👋"; exit 0; }
    else
        read -rp "$(echo -e "${C_YELLOW}❓ 确认安装 ${target_version}？[Y/n]：${C_RESET}")" confirm
        [[ "${confirm,,}" == "n" ]] && { print_msg INFO "已取消，退出 👋"; exit 0; }
    fi

    # --- 执行安装流程 ---
    create_nginx_user
    create_directories
    backup_nginx
    fix_existing_paths
    download_dependencies

    # 下载 Nginx 源码
    local tar_file="$BUILD_DIR/${target_version}.tar.gz"
    download_file \
        "https://nginx.org/download/${target_version}.tar.gz" \
        "$tar_file" \
        "Nginx ${target_version} 源码" \
        || { print_msg ERROR "源码下载失败"; exit 1; }

    print_msg INFO "📂 解压源码..."
    tar -xzf "$tar_file" -C "$BUILD_DIR" \
        || { print_msg ERROR "源码解压失败（tar 文件可能不完整）"; exit 1; }
    rm -f "$tar_file"   # 解压后即删，节省 /tmp 空间

    compile_and_install "$target_version"
    create_nginx_config
    create_systemd_service
    verify_installation
    show_summary
}

main "$@"
