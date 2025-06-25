#!/bin/bash
# Nginx 编译安装性能拉满脚本
# By: BuBuXSY
# Version: 2025-06-25

# 设置颜色和格式
COLORS=(
    "\e[1;32m"  # 绿色
    "\e[1;31m"  # 红色
    "\e[1;33m"  # 黄色
    "\e[1;34m"  # 蓝色
    "\e[1;35m"  # 紫色
    "\e[1;36m"  # 青色
    "\e[1;37m"  # 白色
)

# 设置表情
EMOJIS=(
    "✅"  # 勾选 ✅
    "❌"  # 叉叉 ❌
    "⚡"  # 闪电 ⚡
    "🎉"  # 庆祝 🎉
    "💡"  # 灯泡 💡
    "🔧"  # 工具 🔧
    "⏳"  # 时钟 ⏳
)

# 输出装饰文字
print_decorated() {
    echo -e "${1}${2}${COLORS[0]}"
}

# 检查并安装 pv
install_pv_if_needed() {
    if ! command -v pv &> /dev/null; then
        print_decorated "🔧 未检测到 pv，正在安装..." "${COLORS[3]}"
        # 自动安装 pv（如果系统支持）
        if [[ -f /etc/debian_version ]]; then
            sudo apt update && sudo apt install -y pv
        elif [[ -f /etc/redhat-release ]]; then
            sudo yum install -y pv
        else
            print_decorated "❌ 当前系统不支持自动安装 pv，请手动安装 pv。" "${COLORS[1]}"
            return 1
        fi
    else
        print_decorated "✅ pv 已安装，继续使用进度条。" "${COLORS[3]}"
    fi
    return 0
}

# 添加带颜色的进度条
progress_bar() {
    local total=$1
    local current=$2
    local width=50  # 设置进度条的宽度
    local progress=$((current * width / total))
    local remaining=$((width - progress))
    local bar=$(printf "%${progress}s" | tr " " "█")
    local empty=$(printf "%${remaining}s" | tr " " "▒")

    # 输出进度条
    echo -e "\r[${bar}${empty}] ${current}/${total} ${COLORS[3]}${current}%${COLORS[0]}"
}

# 下载 Nginx 源代码并显示进度条
download_nginx() {
    local latest_version=$1
    local temp_dir="/tmp/nginx_build/temp"
    print_decorated "⚡ 开始下载 Nginx 源代码..." "${COLORS[3]}"
    wget -q https://nginx.org/download/$latest_version.tar.gz -P $temp_dir

    # 获取文件大小并初始化进度条
    local filesize=$(stat -c %s "$temp_dir/$latest_version.tar.gz")
    local downloaded=0

    # 如果系统安装了 pv，则显示进度条
    if command -v pv &> /dev/null; then
        # 使用 pv 命令将下载进度可视化
        pv "$temp_dir/$latest_version.tar.gz" > /dev/null 2>&1 | while read -r line; do
            downloaded=$(($downloaded + ${line}))
            progress_bar $filesize $downloaded
        done
    else
        # 如果没有 pv，使用普通的下载方式并显示简易进度条
        while [ $downloaded -lt $filesize ]; do
            sleep 1
            downloaded=$(stat -c %s "$temp_dir/$latest_version.tar.gz")
            progress_bar $filesize $downloaded
        done
    fi
}

# 查询最新版本
get_latest_stable_version() {
    latest_version=$(curl -s https://nginx.org/download/ | grep nginx-1.2 | tail -n 1 | awk -F\" '{print $2}' | sed 's/.zip.asc//g')
    if [[ -z "$latest_version" ]]; then
        echo -e "${COLORS[1]}未能获取到最新的稳定版本号，请检查官网格式变化。${COLORS[0]}"
        exit 1
    fi
    echo "$latest_version"
}

# 查询本地版本
get_installed_version() {
    installed_version=$(/usr/sbin/nginx -v 2>&1 | grep -oE "nginx/[0-9]+\.[0-9]+\.[0-9]+" | awk -F/ '{print "nginx-"$2}')
    echo "$installed_version"
}

# 比对版本并提示是否更新
compare_versions() {
    installed_version=$(get_installed_version)
    latest_version=$(get_latest_stable_version)

    echo -e "***** 当前安装版本: ${COLORS[3]}$installed_version${COLORS[0]}，最新稳定版本: ${COLORS[3]}$latest_version${COLORS[0]} *****"

    if [[ "$installed_version" == "$latest_version" ]]; then
        print_decorated "🎉 ✅ 你已经拥有最新的Nginx，不需要更新。" "${COLORS[2]}"
        read -p "是否要强制更新？[Y/n]: " choice
        if [[ -z "$choice" || "$choice" == "Y" || "$choice" == "y" ]]; then
            print_decorated "⚡ ${EMOJIS[3]} 执行强制更新操作..." "${COLORS[3]}"
            perform_update
        else
            print_decorated "❌ ${EMOJIS[1]} 取消更新操作。" "${COLORS[1]}"
            exit 0
        fi
    else
        print_decorated "⚠️ ❌ 当前安装版本与最新稳定版本不一致。现在可以为您安装最新的稳定版本。是否需要更新？[Y/n]" "${COLORS[1]}"
        read -p "是否要执行更新操作？[Y/n]: " choice
        if [[ -z "$choice" || "$choice" == "Y" || "$choice" == "y" ]]; then
            print_decorated "⚡ ${EMOJIS[3]} 执行更新操作..." "${COLORS[3]}"
            perform_update
        else
            print_decorated "❌ ${EMOJIS[1]} 取消更新操作。" "${COLORS[1]}"
            exit 0
        fi
    fi
}

# 下载模块
ngx_brotli_source() {
    git clone https://github.com/google/ngx_brotli --recurse-submodules --depth=1 /tmp/nginx_build/ngx_brotli
}

ngx_http_geoip2_module_source() {
    git clone https://github.com/leev/ngx_http_geoip2_module --depth=1 /tmp/nginx_build/ngx_http_geoip2_module
}

openssl_source() {
    git clone https://github.com/openssl/openssl --recurse-submodules --depth=1 /tmp/nginx_build/openssl
}

zlib_source() {
    wget https://zlib.net/zlib-1.3.1.tar.gz --no-check-certificate
    tar -zxf zlib-1.3.1.tar.gz && mv zlib-1.3.1 /tmp/nginx_build/zlib && rm -f zlib-1.3.1.tar.gz
}

perform_update() {
    # 安装所需的依赖
    print_decorated "🔧 安装依赖..." "${COLORS[3]}"
    apt update && apt install -y build-essential ca-certificates zlib1g-dev libpcre3 libpcre3-dev tar unzip libssl-dev wget curl git cmake golang clang

    # 创建必要的目录
    mkdir -p /tmp/nginx_build/temp
    cd /tmp/nginx_build/temp

    # 下载 Nginx 源码
    latest_version=$(get_latest_stable_version)
    if [ ! -f "$latest_version.tar.gz" ]; then
        wget https://nginx.org/download/$latest_version.tar.gz
    fi
    tar -zxf $latest_version.tar.gz
    cd $latest_version

    # 下载所需模块
    if [ ! -d "/tmp/nginx_build/ngx_brotli" ]; then
        ngx_brotli_source
    fi
    if [ ! -d "/tmp/nginx_build/ngx_http_geoip2_module" ]; then
        ngx_http_geoip2_module_source
    fi
    if [ ! -d "/tmp/nginx_build/openssl" ]; then
        openssl_source
    fi
    if [ ! -d "/tmp/nginx_build/zlib" ]; then
        zlib_source
    fi

    # 配置和编译 Nginx
    print_decorated "⚡ 配置和编译 Nginx..." "${COLORS[3]}"
    ./configure \
      --prefix=/etc/nginx \
      --user=nginx \
      --group=nginx \
      --modules-path=/usr/lib/nginx/modules \
      --conf-path=/etc/nginx/nginx.conf \
      --error-log-path=/var/log/nginx/error.log \
      --http-log-path=/var/log/nginx/access.log \
      --pid-path=/var/run/nginx.pid \
      --lock-path=/var/run/nginx.lock \
      --http-client-body-temp-path=/var/cache/nginx/client_temp \
      --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
      --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
      --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
      --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
      --with-debug \
      --with-compat \
      --with-file-aio \
      --with-threads \
      --with-http_addition_module \
      --with-http_auth_request_module \
      --with-http_dav_module \
      --with-http_degradation_module \
      --with-http_flv_module \
      --with-http_gunzip_module \
      --with-http_gzip_static_module \
      --with-http_image_filter_module \
      --with-http_mp4_module \
      --with-http_random_index_module \
      --with-http_realip_module \
      --with-http_secure_link_module \
      --with-http_slice_module \
      --with-http_ssl_module \
      --with-http_stub_status_module \
      --with-http_sub_module \
      --with-http_xslt_module \
      --with-http_v2_module \
      --with-http_v3_module \
      --with-mail \
      --with-mail_ssl_module \
      --with-stream \
      --with-stream_realip_module \
      --with-stream_ssl_module \
      --with-stream_ssl_preread_module \
      --with-openssl-opt='enable-tls1_3' \
      --with-openssl-opt='enable-ktls' \
      --with-openssl="/tmp/nginx_build/openssl" \
      --with-pcre-jit \
      --with-zlib="/tmp/nginx_build/zlib" \
      --add-module="/tmp/nginx_build/ngx_brotli" \
      --add-module="/tmp/nginx_build/ngx_http_geoip2_module" \
      --with-cc=clang \
      --with-cpp=clang++

    # 编译并安装
    make -j$(nproc)
    make install

    # 停止 Nginx 服务，避免 "Text file busy" 错误
    print_decorated "🔧 停止 Nginx 服务..." "${COLORS[3]}"
    systemctl stop nginx

    # 备份旧版本并重启 Nginx
    print_decorated "🔧 备份旧版本并重启 Nginx..." "${COLORS[3]}"
    cp /usr/sbin/nginx{,.bak}
    cp /tmp/nginx_build/temp/$latest_version/objs/nginx /usr/sbin/nginx
    systemctl start nginx
    print_decorated "🎉 新的 Nginx 已成功安装！" "${COLORS[0]}"

    # 清理临时文件
    rm -rf /tmp/nginx_build
}

# 主流程
install_pv_if_needed
compare_versions
