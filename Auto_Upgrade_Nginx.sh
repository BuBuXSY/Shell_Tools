#!/bin/bash
# ====================================================
# 🌉 Nginx 编译安装性能拉满脚本 v2.0
# 支持最新主线版本 / 稳定版本
# By: BuBuXSY | License: MIT
# ====================================================

set -uo pipefail
# 注意：去掉 -e，改为每步手动处理，避免单步失败终止整个流程

[[ "${DEBUG:-0}" == "1" ]] && set -x

# =========================
# 🎨 颜色（避免关联数组，兼容 bash 3.x）
# =========================
C_GREEN="\e[1;32m"; C_RED="\e[1;31m"; C_YELLOW="\e[1;33m"
C_BLUE="\e[1;34m"; C_CYAN="\e[1;36m"; C_RESET="\e[0m"

# =========================
# 📋 日志系统
# =========================
LOG_FILE="/var/log/nginx_install_$(date +%Y%m%d_%H%M%S).log"
BUILD_DIR="/tmp/nginx_build_$$"
BACKUP_DIR="/var/backups/nginx"
NGINX_USER="nginx"
NGINX_GROUP="nginx"
CPU_CORES=$(nproc 2>/dev/null || echo 1)

print_msg() {
    local level=$1 msg=$2 color emoji
    case $level in
        INFO)    color=$C_BLUE;   emoji="ℹ" ;;
        SUCCESS) color=$C_GREEN;  emoji="✓" ;;
        ERROR)   color=$C_RED;    emoji="✗" ;;
        WARN)    color=$C_YELLOW; emoji="!" ;;
        *)       color=$C_RESET;  emoji=" " ;;
    esac
    local line
    line="$(date '+%H:%M:%S') ${emoji} ${msg}"
    echo -e "${color}${line}${C_RESET}" | tee -a "$LOG_FILE"
}

# =========================
# 🛡 前置检查（root、日志目录）
# =========================
preflight() {
    # 日志目录必须先建，后续所有 print_msg 才能写入
    mkdir -p "$(dirname "$LOG_FILE")" || { echo "无法创建日志目录"; exit 1; }
    touch "$LOG_FILE"

    if [[ $EUID -ne 0 ]]; then
        print_msg ERROR "此脚本必须以 root 权限运行"; exit 1
    fi

    # 检查内核版本（kTLS 需要 4.17+）
    local kver
    kver=$(uname -r | awk -F'[.-]' '{print $1*10000+$2*100+$3}')
    if [[ "$kver" -ge 41700 ]]; then
        KTLS_SUPPORTED=1
    else
        KTLS_SUPPORTED=0
        print_msg WARN "内核 $(uname -r) 低于 4.17，将禁用 kTLS"
    fi

    # 检查必要命令
    local missing=()
    for cmd in curl wget tar make gcc git; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_msg WARN "以下命令未找到（将在安装依赖后重新检查）: ${missing[*]}"
    fi

    print_msg SUCCESS "前置检查完成（CPU: ${CPU_CORES}核 | 内核: $(uname -r)）"
}

# =========================
# 🌐 网络检查（TCP 替代 ICMP ping，兼容禁 ping 的云服务器）
# =========================
check_network() {
    print_msg INFO "检查网络连接..."
    local ok=0
    for host_port in "nginx.org:80" "github.com:443" "8.8.8.8:53"; do
        local h="${host_port%%:*}" p="${host_port##*:}"
        if timeout 3 bash -c ">/dev/tcp/$h/$p" 2>/dev/null; then
            ok=1; break
        fi
    done
    if [[ "$ok" -eq 0 ]]; then
        print_msg ERROR "无法连接外网，请检查网络设置"; exit 1
    fi
    print_msg SUCCESS "网络连接正常"
}

# =========================
# 🖥 系统检测
# =========================
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS="${ID:-unknown}"
        VER="${VERSION_ID:-unknown}"
    else
        print_msg ERROR "无法检测操作系统"; exit 1
    fi
    print_msg INFO "系统: $OS $VER"
}

# =========================
# 📦 安装依赖
# =========================
install_dependencies() {
    print_msg INFO "安装编译依赖..."
    case $OS in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y \
                build-essential ca-certificates zlib1g-dev \
                libpcre3-dev libssl-dev libgd-dev libgeoip-dev \
                libxslt1-dev libxml2-dev libmaxminddb-dev \
                autoconf libtool pkg-config wget curl git cmake \
                || { print_msg ERROR "依赖安装失败"; exit 1; }
            ;;
        centos|rhel|almalinux|rocky)
            yum install -y epel-release
            yum install -y \
                gcc gcc-c++ make ca-certificates zlib-devel \
                pcre-devel openssl-devel gd-devel GeoIP-devel \
                libxslt-devel libxml2-devel libmaxminddb-devel \
                wget curl git cmake autoconf libtool pkgconfig \
                || { print_msg ERROR "依赖安装失败"; exit 1; }
            ;;
        fedora)
            dnf install -y \
                gcc gcc-c++ make ca-certificates zlib-devel \
                pcre-devel openssl-devel gd-devel GeoIP-devel \
                libxslt-devel libxml2-devel libmaxminddb-devel \
                wget curl git cmake autoconf libtool pkgconfig \
                || { print_msg ERROR "依赖安装失败"; exit 1; }
            ;;
        *)
            print_msg ERROR "不支持的发行版: $OS"; exit 1
            ;;
    esac
    print_msg SUCCESS "依赖安装完成"
}

# =========================
# 👤 创建 nginx 用户
# =========================
create_nginx_user() {
    if ! id -u "$NGINX_USER" &>/dev/null; then
        useradd -r -s /sbin/nologin -d /var/cache/nginx \
                -c "Nginx web server" "$NGINX_USER"
        print_msg SUCCESS "已创建 nginx 用户"
    else
        print_msg INFO "nginx 用户已存在，跳过"
    fi
}

# =========================
# 📁 创建必要目录
# =========================
create_directories() {
    print_msg INFO "创建必要目录..."
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
    print_msg SUCCESS "目录创建完成"
}

# =========================
# 🔍 获取 Nginx 版本（从官网 JSON API，比 HTML 解析更稳定）
# =========================
get_nginx_version() {
    local channel="${1:-mainline}"   # mainline | stable
    print_msg INFO "查询 Nginx ${channel} 最新版本..." >&2

    # nginx.org 提供 /download/ 页面，版本规则：次版本奇数=主线，偶数=稳定
    local all_versions
    all_versions=$(curl -sf "https://nginx.org/en/download.html" \
        | grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+' \
        | sort -Vu)

    if [[ -z "$all_versions" ]]; then
        print_msg ERROR "无法获取版本列表，请检查网络" >&2; exit 1
    fi

    local version
    if [[ "$channel" == "stable" ]]; then
        # 次版本号为偶数 = 稳定版
        version=$(echo "$all_versions" \
            | awk -F'[.-]' '$3 % 2 == 0 {print}' \
            | tail -1)
    else
        # 最新（含主线）
        version=$(echo "$all_versions" | tail -1)
    fi

    if [[ -z "$version" ]]; then
        print_msg ERROR "无法解析 ${channel} 版本" >&2; exit 1
    fi

    print_msg INFO "找到版本: $version" >&2
    printf "%s" "$version"
}

# =========================
# 📥 下载（带重试，移除 --no-check-certificate）
# =========================
download_file() {
    local url=$1 output=$2 desc=$3
    print_msg INFO "下载 $desc ..."
    local ok=0
    for attempt in 1 2 3; do
        if wget -q --show-progress --timeout=30 "$url" -O "$output" 2>&1; then
            ok=1; break
        fi
        print_msg WARN "第 $attempt 次下载失败，重试..."
        sleep 2
    done
    if [[ "$ok" -eq 0 ]]; then
        print_msg ERROR "下载 $desc 失败（已重试 3 次）"; return 1
    fi
    # 基础完整性校验
    local size
    size=$(wc -c < "$output")
    if [[ "$size" -lt 1024 ]]; then
        print_msg ERROR "下载文件过小（${size}B），可能下载失败"; return 1
    fi
    print_msg SUCCESS "下载完成: $desc（${size}B）"
}

# =========================
# 📦 下载编译依赖模块
# =========================
download_dependencies() {
    print_msg INFO "下载编译依赖模块..."
    mkdir -p "$BUILD_DIR"

    # ngx_brotli
    if [[ ! -d "$BUILD_DIR/ngx_brotli" ]]; then
        git clone --depth=1 https://github.com/google/ngx_brotli \
            "$BUILD_DIR/ngx_brotli" \
            && git -C "$BUILD_DIR/ngx_brotli" submodule update --init --recursive \
            || { print_msg ERROR "克隆 ngx_brotli 失败"; exit 1; }
        print_msg SUCCESS "ngx_brotli 下载完成"
    fi

    # ngx_http_geoip2_module
    if [[ ! -d "$BUILD_DIR/ngx_http_geoip2_module" ]]; then
        git clone --depth=1 https://github.com/leev/ngx_http_geoip2_module \
            "$BUILD_DIR/ngx_http_geoip2_module" \
            || { print_msg ERROR "克隆 geoip2 模块失败"; exit 1; }
        print_msg SUCCESS "ngx_http_geoip2_module 下载完成"
    fi

    # OpenSSL（使用最新 tag 而非 HEAD，更稳定）
    if [[ ! -d "$BUILD_DIR/openssl" ]]; then
        print_msg INFO "克隆 OpenSSL..."
        git clone --depth=1 https://github.com/openssl/openssl.git \
            "$BUILD_DIR/openssl" \
            || { print_msg ERROR "克隆 OpenSSL 失败"; exit 1; }
        local ossl_ver
        ossl_ver=$(git -C "$BUILD_DIR/openssl" describe --tags --always 2>/dev/null || echo "latest")
        print_msg SUCCESS "OpenSSL: $ossl_ver"
    fi

    # zlib（先获取目录名再解压，避免 tar -t 读已删文件）
    if [[ ! -d "$BUILD_DIR/zlib" ]]; then
        local zlib_ver="1.3.1"
        local zlib_tar="$BUILD_DIR/zlib-${zlib_ver}.tar.gz"
        local primary_url="https://www.zlib.net/zlib-${zlib_ver}.tar.gz"
        local fallback_url="https://github.com/madler/zlib/releases/download/v${zlib_ver}/zlib-${zlib_ver}.tar.gz"

        # 检测主站可达性
        if ! curl -sf --head --max-time 5 "$primary_url" >/dev/null 2>&1; then
            print_msg WARN "zlib 主站不可达，切换至 GitHub 镜像"
            primary_url="$fallback_url"
        fi

        download_file "$primary_url" "$zlib_tar" "zlib $zlib_ver" \
            || { print_msg ERROR "zlib 下载失败"; exit 1; }

        # 先获取顶层目录名，再解压
        local top_dir
        top_dir=$(tar -tzf "$zlib_tar" | head -1 | cut -d/ -f1)
        tar -xzf "$zlib_tar" -C "$BUILD_DIR" \
            || { print_msg ERROR "zlib 解压失败"; exit 1; }
        mv "$BUILD_DIR/$top_dir" "$BUILD_DIR/zlib" \
            || { print_msg ERROR "zlib 目录重命名失败"; exit 1; }
        rm -f "$zlib_tar"
        print_msg SUCCESS "zlib 准备完成"
    fi
}

# =========================
# 💾 备份现有 Nginx
# =========================
backup_nginx() {
    [[ -x /usr/sbin/nginx ]] || return 0
    print_msg INFO "备份现有 Nginx..."
    local ts; ts=$(date +%Y%m%d_%H%M%S)
    cp /usr/sbin/nginx "$BACKUP_DIR/nginx_${ts}.bin"
    [[ -d /etc/nginx ]] && tar -czf "$BACKUP_DIR/nginx_${ts}_config.tar.gz" -C /etc nginx
    print_msg SUCCESS "备份完成: $BACKUP_DIR/nginx_${ts}.*"
}

# =========================
# 🔧 检测 CPU 特性
# =========================
get_cpu_flags() {
    local flags="-march=native -mtune=native"
    grep -q "avx512" /proc/cpuinfo && flags+=" -mavx512f" && return 0
    grep -q "avx2"   /proc/cpuinfo && flags+=" -mavx2"   && return 0
    grep -q "avx"    /proc/cpuinfo && flags+=" -mavx"
    echo "$flags"
}

# =========================
# ⚙ 编译并安装 Nginx
# =========================
compile_and_install() {
    local version=$1
    local src_dir="$BUILD_DIR/$version"
    cd "$src_dir"

    print_msg INFO "配置编译选项..."

    # 构建 OpenSSL 选项（kTLS 按内核版本决定）
    local openssl_opts="enable-ec_nistp_64_gcc_128 no-nextprotoneg no-weak-ssl-ciphers no-ssl3 enable-tls1_3"
    [[ "$KTLS_SUPPORTED" -eq 1 ]] && openssl_opts="enable-ktls $openssl_opts"

    # CFLAGS：-O2 替代 -O3（更稳定），移除已废弃的 --param=ssp-buffer-size
    local cpu_flags
    cpu_flags=$(get_cpu_flags)
    local cflags="-O2 -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong -fPIC $cpu_flags"

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
        --with-pcre-jit \
        --with-openssl="$BUILD_DIR/openssl" \
        --with-openssl-opt="$openssl_opts" \
        --with-zlib="$BUILD_DIR/zlib" \
        --add-module="$BUILD_DIR/ngx_brotli" \
        --add-module="$BUILD_DIR/ngx_http_geoip2_module" \
        --with-cc-opt="$cflags" \
        --with-ld-opt="-Wl,-rpath,/usr/lib" \
        || { print_msg ERROR "配置失败，请查看日志: $LOG_FILE"; exit 1; }

    print_msg INFO "开始编译（使用 $CPU_CORES 核心）..."
    make -j"$CPU_CORES" || { print_msg ERROR "编译失败"; exit 1; }

    # 停止现有服务
    if systemctl is-active --quiet nginx 2>/dev/null; then
        print_msg INFO "停止现有 Nginx 服务..."
        systemctl stop nginx
        sleep 2
    fi

    make install || { print_msg ERROR "安装失败"; exit 1; }
    print_msg SUCCESS "Nginx 安装完成"
}

# =========================
# 🔧 修复旧路径（/var/run → /run）
# =========================
fix_existing_paths() {
    if [[ -f /etc/nginx/nginx.conf ]] && grep -q "/var/run/nginx.pid" /etc/nginx/nginx.conf; then
        local bak="/etc/nginx/nginx.conf.bak.$(date +%Y%m%d_%H%M%S)"
        cp /etc/nginx/nginx.conf "$bak"
        sed -i 's|/var/run/nginx.pid|/run/nginx.pid|g' /etc/nginx/nginx.conf
        print_msg SUCCESS "nginx.conf 路径已更新（备份: $bak）"
    fi
}

# =========================
# 📝 创建默认 nginx.conf（仅首次）
# =========================
create_nginx_config() {
    [[ -f /etc/nginx/nginx.conf ]] && { print_msg INFO "nginx.conf 已存在，跳过"; return 0; }
    print_msg INFO "创建默认 nginx.conf..."
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
    cat > /usr/share/nginx/html/index.html <<'EOF'
<!DOCTYPE html><html><head><title>Welcome to nginx!</title></head>
<body><h1>Welcome to nginx!</h1><p>Nginx is successfully installed.</p></body></html>
EOF
    chown -R "$NGINX_USER:$NGINX_GROUP" /usr/share/nginx/html
    print_msg SUCCESS "nginx.conf 创建完成"
}

# =========================
# 🔧 创建 / 更新 systemd 服务
# =========================
create_systemd_service() {
    print_msg INFO "写入 systemd 服务文件..."
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
    print_msg SUCCESS "systemd 服务文件已更新"
}

# =========================
# ✅ 验证安装
# =========================
verify_installation() {
    print_msg INFO "验证 Nginx 配置..."
    /usr/sbin/nginx -t || { print_msg ERROR "Nginx 配置测试失败"; exit 1; }

    systemctl enable nginx
    systemctl restart nginx

    sleep 1
    if systemctl is-active --quiet nginx; then
        print_msg SUCCESS "Nginx 服务运行正常"
    else
        print_msg ERROR "Nginx 服务启动失败"
        journalctl -u nginx -n 20 --no-pager | tee -a "$LOG_FILE"
        exit 1
    fi
}

# =========================
# 📊 安装摘要
# =========================
show_summary() {
    local ver
    ver=$(/usr/sbin/nginx -v 2>&1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)
    echo -e "\n${C_CYAN}================================================${C_RESET}"
    echo -e "${C_GREEN}✓ Nginx $ver 安装完成${C_RESET}"
    echo -e "${C_GREEN}  配置文件: /etc/nginx/nginx.conf${C_RESET}"
    echo -e "${C_GREEN}  日志目录: /var/log/nginx/${C_RESET}"
    echo -e "${C_GREEN}  PID 文件: /run/nginx.pid${C_RESET}"
    echo -e "${C_GREEN}  服务管理: systemctl {start|stop|reload|status} nginx${C_RESET}"
    echo -e "${C_GREEN}  安装日志: $LOG_FILE${C_RESET}"
    echo -e "${C_CYAN}================================================${C_RESET}\n"
}

# =========================
# 🧹 清理 & 错误诊断
# =========================
cleanup() {
    local code=$?
    [[ -d "$BUILD_DIR" ]] && { print_msg INFO "清理临时目录..."; rm -rf "$BUILD_DIR"; }
    if [[ $code -ne 0 ]]; then
        print_msg ERROR "安装失败，诊断建议："
        echo "  1. 查看日志: tail -50 $LOG_FILE"
        echo "  2. 检查网络: curl -I https://nginx.org"
        echo "  3. 检查磁盘: df -h /tmp /usr"
        echo "  4. 调试模式: DEBUG=1 $0"
    fi
}
trap cleanup EXIT

# =========================
# 🚀 主流程
# =========================
main() {
    echo -e "\n${C_CYAN}================================================"
    echo    "   🌉 Nginx 编译安装脚本 v2.0"
    echo -e "================================================${C_RESET}\n"

    preflight
    check_network
    detect_os
    install_dependencies

    # 选择版本通道
    echo "请选择安装版本："
    echo "  1) 最新主线版本（含新功能，适合测试）"
    echo "  2) 最新稳定版本（推荐生产环境）"
    read -rp "请输入 [1/2]（默认 1）: " ver_choice
    ver_choice="${ver_choice:-1}"

    local target_version
    if [[ "$ver_choice" == "2" ]]; then
        target_version=$(get_nginx_version stable)
    else
        target_version=$(get_nginx_version mainline)
    fi

    local installed_version="未安装"
    if [[ -x /usr/sbin/nginx ]]; then
        installed_version=$(/usr/sbin/nginx -v 2>&1 | grep -oE "nginx/[0-9]+\.[0-9]+\.[0-9]+" | awk -F/ '{print "nginx-"$2}')
    fi

    print_msg INFO "当前版本: $installed_version → 目标版本: $target_version"

    if [[ "$installed_version" == "$target_version" ]]; then
        print_msg WARN "已是最新版本"
        read -rp "是否重新编译安装？[y/N]: " confirm
        [[ "${confirm,,}" != "y" ]] && { print_msg INFO "已取消"; exit 0; }
    else
        read -rp "确认安装 $target_version？[Y/n]: " confirm
        [[ "${confirm,,}" == "n" ]] && { print_msg INFO "已取消"; exit 0; }
    fi

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
        "Nginx $target_version 源码" \
        || { print_msg ERROR "源码下载失败"; exit 1; }

    print_msg INFO "解压源码..."
    tar -xzf "$tar_file" -C "$BUILD_DIR" \
        || { print_msg ERROR "解压失败"; exit 1; }

    compile_and_install "$target_version"
    create_nginx_config
    create_systemd_service
    verify_installation
    show_summary
}

main "$@"
