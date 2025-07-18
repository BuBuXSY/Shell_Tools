#!/bin/bash
# Nginx 编译安装性能拉满脚本
# 支持安装最新主线版本或稳定版本
# By: BuBuXSY
# Version: 2025.07.18

# 启用严格错误处理
set -euo pipefail

# 检查是否启用调试模式
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x
fi

# 设置颜色和格式
declare -A COLORS=(
    ["GREEN"]="\e[1;32m"
    ["RED"]="\e[1;31m"
    ["YELLOW"]="\e[1;33m"
    ["BLUE"]="\e[1;34m"
    ["PURPLE"]="\e[1;35m"
    ["CYAN"]="\e[1;36m"
    ["WHITE"]="\e[1;37m"
    ["RESET"]="\e[0m"
)

# 设置表情
declare -A EMOJIS=(
    ["CHECK"]="✅"
    ["CROSS"]="❌"
    ["BOLT"]="⚡"
    ["PARTY"]="🎉"
    ["BULB"]="💡"
    ["TOOL"]="🔧"
    ["CLOCK"]="⏳"
    ["WARN"]="⚠️"
)

# 全局变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="/tmp/nginx_build_$$"
LOG_FILE="/var/log/nginx_install_$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/var/backups/nginx"
NGINX_USER="nginx"
NGINX_GROUP="nginx"

# 清理函数
cleanup() {
    local exit_code=$?
    if [[ -d "$BUILD_DIR" ]]; then
        print_msg "INFO" "清理临时文件..."
        rm -rf "$BUILD_DIR"
    fi
    if [[ $exit_code -ne 0 ]]; then
        print_msg "ERROR" "脚本执行失败，请查看日志: $LOG_FILE"
        show_error_diagnosis
    fi
}
trap cleanup EXIT

# 输出带颜色和表情的消息
print_msg() {
    local level=$1
    local message=$2
    local color emoji
    
    case $level in
        "INFO")
            color="${COLORS[BLUE]}"
            emoji="${EMOJIS[BULB]}"
            ;;
        "SUCCESS")
            color="${COLORS[GREEN]}"
            emoji="${EMOJIS[CHECK]}"
            ;;
        "ERROR")
            color="${COLORS[RED]}"
            emoji="${EMOJIS[CROSS]}"
            ;;
        "WARN")
            color="${COLORS[YELLOW]}"
            emoji="${EMOJIS[WARN]}"
            ;;
        *)
            color="${COLORS[WHITE]}"
            emoji=""
            ;;
    esac
    
    echo -e "${color}${emoji} ${message}${COLORS[RESET]}" | tee -a "$LOG_FILE"
}

# 检查并修复现有系统的路径问题
fix_existing_paths() {
    print_msg "INFO" "检查现有系统路径配置..."
    
    # 检查是否存在使用旧路径的 systemd 服务文件
    if [[ -f /etc/systemd/system/nginx.service ]]; then
        if grep -q "/var/run/nginx.pid" /etc/systemd/system/nginx.service; then
            print_msg "WARN" "发现使用旧路径的 systemd 服务文件"
            print_msg "INFO" "将在安装过程中自动更新为现代路径"
        fi
    fi
    
    # 检查现有的 nginx 配置文件
    if [[ -f /etc/nginx/nginx.conf ]]; then
        if grep -q "/var/run/nginx.pid" /etc/nginx/nginx.conf; then
            print_msg "INFO" "备份并更新现有的 nginx 配置文件..."
            cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)
            sed -i 's|/var/run/nginx.pid|/run/nginx.pid|g' /etc/nginx/nginx.conf
            print_msg "SUCCESS" "nginx 配置文件路径已更新"
        fi
    fi
}

# 检查是否以 root 权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_msg "ERROR" "此脚本必须以 root 权限运行"
        exit 1
    fi
}

# 检查网络连接
check_network() {
    print_msg "INFO" "检查网络连接..."
    
    # 测试多个站点以确保网络可用
    local test_sites=("github.com" "nginx.org" "zlib.net")
    local network_ok=false
    
    for site in "${test_sites[@]}"; do
        if ping -c 1 -W 2 "$site" &>/dev/null; then
            network_ok=true
            break
        fi
    done
    
    if [[ "$network_ok" != "true" ]]; then
        print_msg "ERROR" "无法连接到互联网，请检查网络设置"
        exit 1
    fi
    
    print_msg "SUCCESS" "网络连接正常"
}

# 检测系统类型
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        print_msg "ERROR" "无法检测操作系统类型"
        exit 1
    fi
    print_msg "INFO" "检测到系统: $OS $VER"
}

# 安装依赖包
install_dependencies() {
    print_msg "INFO" "安装编译依赖..."
    
    local packages=(
        "build-essential" "ca-certificates" "zlib1g-dev" "libpcre3" 
        "libpcre3-dev" "tar" "unzip" "libssl-dev" "wget" "curl" 
        "git" "cmake" "golang" "clang" "libgd-dev" "libgeoip-dev"
        "libxslt1-dev" "libxml2-dev" "libmaxminddb-dev" "libmaxminddb0"
        "autoconf" "automake" "libtool" "pkg-config"
    )
    
    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y "${packages[@]}" || {
                print_msg "ERROR" "安装依赖失败"
                exit 1
            }
            ;;
        centos|rhel|fedora)
            # 转换包名为 RPM 系统的对应名称
            local rpm_packages=(
                "gcc" "gcc-c++" "make" "ca-certificates" "zlib-devel" 
                "pcre-devel" "tar" "unzip" "openssl-devel" "wget" "curl" 
                "git" "cmake" "golang" "clang" "gd-devel" "GeoIP-devel"
                "libxslt-devel" "libxml2-devel" "libmaxminddb-devel"
            )
            yum install -y epel-release
            yum install -y "${rpm_packages[@]}" || {
                print_msg "ERROR" "安装依赖失败"
                exit 1
            }
            ;;
        *)
            print_msg "ERROR" "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
}

# 创建 nginx 用户和组
create_nginx_user() {
    if ! id -u $NGINX_USER &>/dev/null; then
        print_msg "INFO" "创建 nginx 用户..."
        useradd -r -s /sbin/nologin -d /var/cache/nginx -c "Nginx web server" $NGINX_USER
    fi
}

# 创建必要的目录
create_directories() {
    print_msg "INFO" "创建必要的目录..."
    local dirs=(
        "/var/cache/nginx/client_temp"
        "/var/cache/nginx/proxy_temp"
        "/var/cache/nginx/fastcgi_temp"
        "/var/cache/nginx/uwsgi_temp"
        "/var/cache/nginx/scgi_temp"
        "/var/log/nginx"
        "/etc/nginx/conf.d"
        "/etc/nginx/sites-available"
        "/etc/nginx/sites-enabled"
        "/etc/nginx/default.d"
        "/usr/share/nginx/html"
        "$BACKUP_DIR"
        "/run"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        # 只对 nginx 相关目录设置权限
        case $dir in
            "/var/cache/nginx"* | "/var/log/nginx" | "/usr/share/nginx"*)
                chown -R $NGINX_USER:$NGINX_GROUP "$dir" 2>/dev/null || true
                ;;
        esac
    done
}

# 获取最新版本（包括主线版本）
get_latest_version() {
    print_msg "INFO" "查询最新的 Nginx 版本..." >&2
    
    # 获取所有版本，包括主线版本
    local latest_version=$(curl -s https://nginx.org/en/download.html | \
        grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' | \
        sort -V | tail -1 | sed 's/\.tar\.gz//')
    
    if [[ -z "$latest_version" ]]; then
        print_msg "ERROR" "无法获取最新版本信息" >&2
        exit 1
    fi
    
    print_msg "INFO" "找到最新版本: $latest_version" >&2
    # 只输出纯净的版本号到标准输出
    printf "%s" "$latest_version"
}

# 获取最新的稳定版本
get_latest_stable_version() {
    print_msg "INFO" "查询最新的 Nginx 稳定版本..." >&2
    
    # 只获取偶数版本号（稳定版）
    local latest_version=$(curl -s https://nginx.org/en/download.html | \
        grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' | \
        grep -E 'nginx-[0-9]+\.[0-9]*[02468]\.[0-9]+' | \
        sort -V | tail -1 | sed 's/\.tar\.gz//')
    
    if [[ -z "$latest_version" ]]; then
        print_msg "ERROR" "无法获取最新稳定版本信息" >&2
        exit 1
    fi
    
    print_msg "INFO" "找到最新稳定版本: $latest_version" >&2
    # 只输出纯净的版本号到标准输出
    printf "%s" "$latest_version"
}

# 获取已安装版本
get_installed_version() {
    if [[ -x /usr/sbin/nginx ]]; then
        local version=$(/usr/sbin/nginx -v 2>&1 | grep -oE "nginx/[0-9]+\.[0-9]+\.[0-9]+" | awk -F/ '{print "nginx-"$2}' | head -1)
        printf "%s" "$version"
    else
        printf "未安装"
    fi
}

# 下载带进度条
download_with_progress() {
    local url=$1
    local output=$2
    local desc=$3
    
    print_msg "INFO" "下载 $desc..."
    
    # 使用 wget 的进度条功能，添加超时和重试
    if ! wget --progress=bar:force:noscroll \
         --timeout=30 \
         --tries=3 \
         --no-check-certificate \
         "$url" -O "$output" 2>&1 | \
        grep --line-buffered "%" | \
        sed -u -e "s,\x1B\[[0-9;]*[a-zA-Z],,g"; then
        print_msg "ERROR" "下载 $desc 失败"
        return 1
    fi
    
    # 验证文件是否下载成功
    if [[ ! -f "$output" ]] || [[ ! -s "$output" ]]; then
        print_msg "ERROR" "下载的文件无效: $output"
        return 1
    fi
    
    print_msg "SUCCESS" "下载 $desc 完成"
    return 0
}

# 下载指定版本的依赖 - 修复版
download_dependencies() {
    print_msg "INFO" "下载编译依赖模块..."
    
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # Brotli 模块
    if [[ ! -d "$BUILD_DIR/ngx_brotli" ]]; then
        print_msg "INFO" "下载 ngx_brotli 模块..."
        git clone --depth=1 https://github.com/google/ngx_brotli "$BUILD_DIR/ngx_brotli" || {
            print_msg "ERROR" "克隆 ngx_brotli 失败"
            exit 1
        }
        cd "$BUILD_DIR/ngx_brotli"
        git submodule update --init --recursive || {
            print_msg "ERROR" "初始化 ngx_brotli 子模块失败"
            exit 1
        }
        cd "$BUILD_DIR"
    fi
    
    # GeoIP2 模块
    if [[ ! -d "$BUILD_DIR/ngx_http_geoip2_module" ]]; then
        print_msg "INFO" "下载 ngx_http_geoip2_module..."
        git clone --depth=1 https://github.com/leev/ngx_http_geoip2_module "$BUILD_DIR/ngx_http_geoip2_module"
    fi
    
    # OpenSSL - 使用最新的 git 版本
    if [[ ! -d "$BUILD_DIR/openssl" ]]; then
        print_msg "INFO" "克隆最新版 OpenSSL..."
        git clone --depth=1 https://github.com/openssl/openssl.git "$BUILD_DIR/openssl" || {
            print_msg "ERROR" "克隆 OpenSSL 失败"
            exit 1
        }
        cd "$BUILD_DIR/openssl"
        # 获取最新的提交信息
        local openssl_version=$(git describe --always --tags 2>/dev/null || echo "latest")
        print_msg "INFO" "OpenSSL 版本: $openssl_version"
        cd "$BUILD_DIR"
    fi
    
    # Zlib - 修复版本处理
    if [[ ! -d "$BUILD_DIR/zlib" ]]; then
        print_msg "INFO" "准备下载 zlib..."
        # 先尝试主站点
        local zlib_url="https://www.zlib.net/zlib-1.3.1.tar.gz"
        if ! wget --spider --timeout=5 "$zlib_url" 2>/dev/null; then
            # 如果主站点不可用，使用 GitHub 备用源
            print_msg "WARN" "主站点不可用，使用 GitHub 源..."
            zlib_url="https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz"
        fi
        
        if ! download_with_progress \
            "$zlib_url" \
            "$BUILD_DIR/zlib-1.3.1.tar.gz" \
            "zlib 1.3.1"; then
            print_msg "ERROR" "无法下载 zlib"
            exit 1
        fi
        
        print_msg "INFO" "解压 zlib..."
        tar -xzf "$BUILD_DIR/zlib-1.3.1.tar.gz" || {
            print_msg "ERROR" "解压 zlib 失败"
            exit 1
        }
        
        # 修复：检查实际解压出来的目录名称
        local extracted_dir=$(tar -tzf "$BUILD_DIR/zlib-1.3.1.tar.gz" | head -1 | cut -d/ -f1)
        print_msg "INFO" "检测到解压目录: $extracted_dir"
        
        if [[ -d "$BUILD_DIR/$extracted_dir" ]]; then
            mv "$BUILD_DIR/$extracted_dir" "$BUILD_DIR/zlib" || {
                print_msg "ERROR" "重命名 zlib 目录失败"
                exit 1
            }
        else
            print_msg "ERROR" "未找到解压的 zlib 目录: $extracted_dir"
            # 列出当前目录内容以便调试
            print_msg "INFO" "当前目录内容:"
            ls -la "$BUILD_DIR/" | tee -a "$LOG_FILE"
            exit 1
        fi
        
        rm -f "$BUILD_DIR/zlib-1.3.1.tar.gz"
        print_msg "SUCCESS" "zlib 准备完成"
    fi
}

# 获取 CPU 核心数
get_cpu_cores() {
    local cores=$(nproc 2>/dev/null || echo 1)
    echo $cores
}

# 备份当前 Nginx
backup_nginx() {
    if [[ -x /usr/sbin/nginx ]]; then
        print_msg "INFO" "备份当前 Nginx..."
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="$BACKUP_DIR/nginx_$timestamp"
        
        # 备份二进制文件
        cp /usr/sbin/nginx "${backup_file}.bin"
        
        # 备份配置文件
        if [[ -d /etc/nginx ]]; then
            tar -czf "${backup_file}_config.tar.gz" -C /etc nginx
        fi
        
        print_msg "SUCCESS" "备份完成: $backup_file"
    fi
}

# 编译和安装 Nginx
compile_and_install() {
    local version=$1
    cd "$BUILD_DIR/$version"
    
    print_msg "INFO" "配置编译选项..."
    
    # 检测 CPU 特性并添加优化
    local cpu_flags=""
    if grep -q "avx2" /proc/cpuinfo; then
        cpu_flags="-march=native -mtune=native -mavx2"
    elif grep -q "avx" /proc/cpuinfo; then
        cpu_flags="-march=native -mtune=native -mavx"
    else
        cpu_flags="-march=native -mtune=native"
    fi
    
    # 配置编译选项
    CFLAGS="-O3 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong --param=ssp-buffer-size=4 -fPIC $cpu_flags" \
    CXXFLAGS="-O3 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong --param=ssp-buffer-size=4 -fPIC $cpu_flags" \
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
        --user=$NGINX_USER \
        --group=$NGINX_GROUP \
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
        --with-openssl-opt="enable-ktls enable-ec_nistp_64_gcc_128 no-nextprotoneg no-weak-ssl-ciphers no-ssl3 enable-tls1_3" \
        --with-zlib="$BUILD_DIR/zlib" \
        --add-module="$BUILD_DIR/ngx_brotli" \
        --add-module="$BUILD_DIR/ngx_http_geoip2_module" \
        --with-cc-opt="-O3" \
        --with-ld-opt="-Wl,-rpath,/usr/lib" \
        || {
            print_msg "ERROR" "配置失败，请查看日志"
            exit 1
        }
    
    # 编译
    print_msg "INFO" "开始编译 (使用 $(get_cpu_cores) 个核心)..."
    make -j$(get_cpu_cores) || {
        print_msg "ERROR" "编译失败"
        exit 1
    }
    
    # 停止现有服务
    if systemctl is-active --quiet nginx; then
        print_msg "INFO" "停止 Nginx 服务..."
        systemctl stop nginx
        sleep 2
    fi
    
    # 安装
    print_msg "INFO" "安装 Nginx..."
    make install || {
        print_msg "ERROR" "安装失败"
        exit 1
    }
}

# 创建 systemd 服务文件
create_systemd_service() {
    print_msg "INFO" "创建/更新 systemd 服务文件..."
    
    # 如果已存在旧的服务文件，先停止服务
    if [[ -f /etc/systemd/system/nginx.service ]]; then
        if systemctl is-active --quiet nginx; then
            systemctl stop nginx
        fi
        systemctl disable nginx 2>/dev/null || true
    fi
    
    # 创建新的服务文件
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

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    print_msg "SUCCESS" "systemd 服务文件已更新"
}

# 创建基本的 nginx 配置文件
create_nginx_config() {
    if [[ ! -f /etc/nginx/nginx.conf ]]; then
        print_msg "INFO" "创建基本的 nginx 配置文件..."
        cat > /etc/nginx/nginx.conf <<'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/lib/nginx/modules/*.conf;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 4096;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    include /etc/nginx/conf.d/*.conf;

    # Default server configuration
    server {
        listen       80 default_server;
        listen       [::]:80 default_server;
        server_name  _;
        root         /usr/share/nginx/html;

        # Load configuration files for the default server block.
        include /etc/nginx/default.d/*.conf;

        location / {
            root   /usr/share/nginx/html;
            index  index.html index.htm;
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   /usr/share/nginx/html;
        }
    }
}
EOF
        
        # 创建默认页面目录
        mkdir -p /usr/share/nginx/html
        
        # 创建简单的默认页面
        cat > /usr/share/nginx/html/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to nginx!</title>
    <style>
        body {
            width: 35em;
            margin: 0 auto;
            font-family: Tahoma, Verdana, Arial, sans-serif;
        }
    </style>
</head>
<body>
    <h1>Welcome to nginx!</h1>
    <p>If you see this page, the nginx web server is successfully installed and
    working. Further configuration is required.</p>

    <p>For online documentation and support please refer to
    <a href="http://nginx.org/">nginx.org</a>.<br/>
    Commercial support is available at
    <a href="http://nginx.com/">nginx.com</a>.</p>

    <p><em>Thank you for using nginx.</em></p>
</body>
</html>
EOF
        
        chown -R $NGINX_USER:$NGINX_GROUP /usr/share/nginx/html
        print_msg "SUCCESS" "nginx 配置文件已创建"
    fi
}

# 验证安装
verify_installation() {
    print_msg "INFO" "验证 Nginx 安装..."
    
    # 测试配置文件
    /usr/sbin/nginx -t || {
        print_msg "ERROR" "Nginx 配置测试失败"
        exit 1
    }
    
    # 启动服务
    systemctl start nginx
    systemctl enable nginx
    
    # 检查服务状态
    if systemctl is-active --quiet nginx; then
        print_msg "SUCCESS" "Nginx 服务启动成功"
        
        # 显示版本信息
        /usr/sbin/nginx -V
    else
        print_msg "ERROR" "Nginx 服务启动失败"
        exit 1
    fi
}

# 显示安装摘要
show_summary() {
    local installed_version=$(get_installed_version)
    
    print_msg "SUCCESS" "Nginx 安装完成！"
    echo -e "${COLORS[CYAN]}========================================${COLORS[RESET]}"
    echo -e "${COLORS[GREEN]}版本: $installed_version${COLORS[RESET]}"
    echo -e "${COLORS[GREEN]}配置文件: /etc/nginx/nginx.conf${COLORS[RESET]}"
    echo -e "${COLORS[GREEN]}日志目录: /var/log/nginx/${COLORS[RESET]}"
    echo -e "${COLORS[GREEN]}PID 文件: /run/nginx.pid${COLORS[RESET]}"
    echo -e "${COLORS[GREEN]}服务管理: systemctl {start|stop|reload|status} nginx${COLORS[RESET]}"
    echo -e "${COLORS[GREEN]}备份目录: $BACKUP_DIR${COLORS[RESET]}"
    echo -e "${COLORS[GREEN]}安装日志: $LOG_FILE${COLORS[RESET]}"
    echo -e "${COLORS[CYAN]}========================================${COLORS[RESET]}"
    echo -e "${COLORS[YELLOW]}注意: 已更新为使用现代路径 /run/ 而不是 /var/run/${COLORS[RESET]}"
}

# 显示错误诊断信息
show_error_diagnosis() {
    print_msg "ERROR" "安装过程中出现错误，以下是一些诊断建议："
    echo "1. 查看完整的错误日志: tail -n 50 $LOG_FILE"
    echo "2. 检查网络连接: ping -c 3 github.com"
    echo "3. 检查磁盘空间: df -h"
    echo "4. 尝试使用调试模式重新运行: DEBUG=1 $0"
    echo ""
    echo "常见问题："
    echo "- 如果是下载失败，可能是网络问题或源站点暂时不可用"
    echo "- 如果是编译失败，可能缺少某些依赖包"
    echo "- 如果是权限问题，确保以 root 用户运行"
}

# 主函数
main() {
    print_msg "INFO" "开始 Nginx 编译安装脚本..."
    
    # 初始化日志
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    # 检查权限
    check_root
    
    # 修复现有路径问题
    fix_existing_paths
    
    # 检查网络
    check_network
    
    # 检测系统
    detect_os
    
    # 询问用户要安装哪个版本
    print_msg "INFO" "请选择要安装的版本类型："
    echo "1) 最新主线版本（可能包含新功能但可能不够稳定）"
    echo "2) 最新稳定版本（推荐用于生产环境）"
    read -p "请输入选择 [1/2] (默认: 1): " version_choice
    
    # 默认选择最新版本
    version_choice=${version_choice:-1}
    
    # 获取版本信息
    local installed_version=$(get_installed_version)
    local latest_version
    
    if [[ "$version_choice" == "2" ]]; then
        latest_version=$(get_latest_stable_version)
        print_msg "INFO" "选择了稳定版本"
    else
        latest_version=$(get_latest_version)
        print_msg "INFO" "选择了最新主线版本"
    fi
    
    print_msg "INFO" "当前版本: $installed_version"
    print_msg "INFO" "目标版本: $latest_version"
    
    # 调试：显示版本号的实际内容
    if [[ "${DEBUG:-0}" == "1" ]]; then
        print_msg "INFO" "调试信息 - 当前版本: [$installed_version] (长度: ${#installed_version})"
        print_msg "INFO" "调试信息 - 目标版本: [$latest_version] (长度: ${#latest_version})"
    fi
    
    # 询问是否继续
    if [[ "$installed_version" == "$latest_version" ]]; then
        print_msg "WARN" "已经是最新版本"
        read -p "是否要重新编译安装？[y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_msg "INFO" "取消安装"
            exit 0
        fi
    else
        print_msg "INFO" "发现新版本可用"
        read -p "是否要安装最新版本？[Y/n]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            print_msg "INFO" "取消安装"
            exit 0
        fi
    fi
    
    # 安装依赖
    install_dependencies
    
    # 创建用户和目录
    create_nginx_user
    create_directories
    
    # 备份现有安装
    backup_nginx
    
    # 下载源码和依赖
    download_dependencies
    
    # 下载 Nginx 源码
    cd "$BUILD_DIR"
    print_msg "INFO" "准备下载 Nginx 源码: $latest_version"
    
    if ! download_with_progress \
        "https://nginx.org/download/$latest_version.tar.gz" \
        "$BUILD_DIR/$latest_version.tar.gz" \
        "Nginx $latest_version"; then
        print_msg "ERROR" "下载 Nginx 源码失败"
        exit 1
    fi
    
    print_msg "INFO" "解压 Nginx 源码..."
    tar -xzf "$latest_version.tar.gz" || {
        print_msg "ERROR" "解压 Nginx 源码失败"
        exit 1
    }
    
    # 编译安装
    compile_and_install "$latest_version"
    
    # 创建配置文件
    create_nginx_config
    
    # 创建服务文件
    create_systemd_service
    
    # 验证安装
    verify_installation
    
    # 显示摘要
    show_summary
}

# 运行主函数
main "$@"
