#!/bin/bash
# Nginx 编译安装脚本
# 支持安装最新主线版本或稳定版本
# By: BuBuXSY
# Version: 2026.03.04
# License: MIT

set -euo pipefail

########################################
# 🧩 参数解析
########################################

INSTALL_STABLE=0
AUTO_YES=0

for arg in "$@"; do
    case $arg in
        --stable)
            INSTALL_STABLE=1
            ;;
        --yes)
            AUTO_YES=1
            ;;
    esac
done

########################################
# 📦 全局变量
########################################

BUILD_DIR="/tmp/nginx_build_$$"
BACKUP_DIR="/var/backups/nginx"
LOG_FILE="/var/log/nginx_upgrade_$(date +%Y%m%d_%H%M%S).log"

########################################
# 🛡 Root 检查
########################################

if [[ $EUID -ne 0 ]]; then
    echo "❌ 请使用 root 运行"
    exit 1
fi

########################################
# 🖥 系统检测
########################################

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
else
    echo "❌ 无法识别系统"
    exit 1
fi

########################################
# 📚 安装依赖（多系统适配）
########################################

install_deps() {

    echo "📦 安装编译依赖..."

    if [[ "$OS" =~ (ubuntu|debian) ]]; then
        apt update
        apt install -y build-essential git curl wget \
        libpcre3-dev zlib1g-dev libssl-dev \
        libxslt1-dev libxml2-dev \
        libgd-dev libmaxminddb-dev \
        libjemalloc-dev cmake golang

    elif [[ "$OS" =~ (centos|rhel|fedora|rocky|almalinux) ]]; then
        yum install -y epel-release
        yum install -y gcc gcc-c++ make git curl wget \
        pcre-devel zlib-devel openssl-devel \
        libxslt-devel libxml2-devel \
        gd-devel libmaxminddb-devel \
        jemalloc-devel cmake golang
    else
        echo "❌ 不支持的系统"
        exit 1
    fi
}

########################################
# 🔍 获取版本
########################################

get_latest() {
    curl -s https://nginx.org/en/download.html |
    grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' |
    sort -V | tail -1 | sed 's/.tar.gz//'
}

get_latest_stable() {
    curl -s https://nginx.org/en/download.html |
    grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' |
    grep -E 'nginx-[0-9]+\.[0-9]*[02468]\.[0-9]+' |
    sort -V | tail -1 | sed 's/.tar.gz//'
}

########################################
# 💾 备份已有 Nginx（仅升级）
########################################

backup_nginx() {

    mkdir -p "$BACKUP_DIR"

    if [[ -x /usr/sbin/nginx ]]; then
        TS=$(date +%Y%m%d_%H%M%S)
        cp /usr/sbin/nginx "$BACKUP_DIR/nginx_$TS.bin"

        if [[ -d /etc/nginx ]]; then
            tar -czf "$BACKUP_DIR/nginx_${TS}_conf.tar.gz" -C /etc nginx
        fi

        echo "✅ 已备份当前 nginx"
    fi
}

########################################
# 📥 下载源码 + 校验
########################################

prepare_sources() {

    VERSION=$1
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    echo "⬇ 下载 Nginx $VERSION"

    wget https://nginx.org/download/$VERSION.tar.gz
    wget https://nginx.org/download/$VERSION.tar.gz.sha256

    sha256sum -c $VERSION.tar.gz.sha256

    tar -xf $VERSION.tar.gz

    # OpenSSL（非 master）
    git clone --depth=1 https://github.com/openssl/openssl.git

    # zlib 最新稳定
    ZLIB=$(curl -s https://zlib.net/ |
    grep -oE 'zlib-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' |
    head -1 | sed 's/.tar.gz//')

    wget https://zlib.net/$ZLIB.tar.gz
    tar -xf $ZLIB.tar.gz
    mv $ZLIB zlib

    # Brotli
    git clone --recursive https://github.com/google/ngx_brotli

    # GeoIP2
    git clone https://github.com/leev/ngx_http_geoip2_module

    # QUICHE（HTTP/3）
    git clone --recursive https://github.com/cloudflare/quiche
}

########################################
# ⚡ 内核优化
########################################

optimize_sysctl() {

cat > /etc/sysctl.d/99-nginx-performance.conf <<EOF
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
fs.file-max = 200000
EOF

    sysctl --system
}

########################################
# 🛠 编译
########################################

compile_nginx() {

    VERSION=$1
    cd "$BUILD_DIR/$VERSION"

    CPU_FLAGS="-march=native -mtune=native"
    CFLAGS="-O3 -flto -fstack-protector-strong $CPU_FLAGS"
    LDFLAGS="-flto -ljemalloc"

    ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/run/nginx.pid \
    --with-threads \
    --with-file-aio \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-quiche="$BUILD_DIR/quiche" \
    --with-stream \
    --with-pcre-jit \
    --with-openssl="$BUILD_DIR/openssl" \
    --with-zlib="$BUILD_DIR/zlib" \
    --add-module="$BUILD_DIR/ngx_brotli" \
    --add-module="$BUILD_DIR/ngx_http_geoip2_module" \
    --with-cc-opt="$CFLAGS" \
    --with-ld-opt="$LDFLAGS"

    make -j$(nproc)

    if systemctl is-active --quiet nginx; then
        systemctl stop nginx
    fi

    make install
}

########################################
# 🔁 回滚机制
########################################

rollback() {

    echo "⚠ 启动失败，执行回滚..."

    LATEST=$(ls -t $BACKUP_DIR/nginx_*.bin | head -1)

    if [[ -f "$LATEST" ]]; then
        cp "$LATEST" /usr/sbin/nginx
        systemctl start nginx
        echo "✅ 已回滚"
    else
        echo "❌ 未找到备份"
    fi

    exit 1
}

########################################
# ✅ 校验并启动
########################################

verify() {

    if ! /usr/sbin/nginx -t; then
        rollback
    fi

    systemctl start nginx

    if ! systemctl is-active --quiet nginx; then
        rollback
    fi

    echo "🎉 升级完成"
}

########################################
# 🚀 主程序
########################################

main() {

    install_deps
    backup_nginx

    if [[ "$INSTALL_STABLE" == "1" ]]; then
        VERSION=$(get_latest_stable)
    else
        VERSION=$(get_latest)
    fi

    echo "📌 目标版本：$VERSION"

    prepare_sources "$VERSION"
    optimize_sysctl
    compile_nginx "$VERSION"
    verify
}

main "$@"
