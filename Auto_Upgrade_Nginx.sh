#!/bin/bash

# Ubuntu 2204 Nginx

source /etc/profile

# 开始计时
starttime=`date +'%Y-%m-%d %H:%M:%S'`

# 查询最新版本
latest_version=$(curl -s https://nginx.org/download/ | grep nginx-1.2 | tail -n 1 | awk -F\" '{print $2}' | sed 's/.zip.asc//g')

# 查询本地版本
installed_version=$(/usr/sbin/nginx -v 2>&1 | grep -oE "nginx/[0-9]+\.[0-9]+\.[0-9]+" | awk -F/ '{print "nginx-"$2}')

if [[ "$installed_version" == "$latest_version" ]]; then
    
    echo -e "\e[1;32m你已经拥有最新的Nginx，不需要更新。\e[0m"

    read -p "是否要执行强制更新？[Y/n]: " choice
    
    if [[ -z "$choice" || "$choice" == "Y" || "$choice" == "y" ]]; then

    echo -e "\e[1;32m执行强制更新操作...\e[0m"

    #  安装所需的依赖
apt update && apt install build-essential ca-certificates zlib1g-dev libpcre3 libpcre3-dev tar unzip libssl-dev wget curl git cmake  golang clang -y && apt build-dep nginx -y 

# 下载源码
mkdir -p temp
mkdir -p /var/cache/nginx/client_temp
cd temp

mkdir -p ext

#latest_version=$(curl -s https://nginx.org/download/ | grep nginx-1.2 | tail -n 1 | awk -F\" '{print $2}' | sed 's/.zip.asc//g')

nginx_source() {
    wget https://nginx.org/download/$latest_version.tar.gz
    tar -zxf $latest_version.tar.gz
}

ngx_brotli_source() {
    git clone https://github.com/google/ngx_brotli --recurse-submodules --depth=1
}

ngx_http_geoip2_module_source() {
    git clone https://github.com/leev/ngx_http_geoip2_module --depth=1
}

pcre2_source() { 
    git clone https://github.com/PCRE2Project/pcre2.git --recurse-submodules --depth=1
    #wget https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.42/pcre2-10.42.tar.gz --no-check-certificate
    #tar -zxf pcre2-10.42.tar.gz && mv pcre2-10.42 pcre2 && rm -f pcre2-10.42.tar.gz
}

quictls_source() {
    git clone https://github.com/quictls/openssl -b openssl-3.0.8+quic-release1 quictls --recurse-submodules --depth=1 
}

#libressl_source(){
#	curl -sL https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-3.8.0.tar.gz | tar --strip-components 1 -C ./libressl -xzvf -
#} 
	
zlib_source() {
    wget https://zlib.net/zlib-1.2.13.tar.gz --no-check-certificate
    tar -zxf zlib-1.2.13.tar.gz && mv zlib-1.2.13 zlib && rm -f zlib-1.2.13.tar.gz
}

pushd ext
    [ ! -d ngx_brotli ] && ngx_brotli_source
    [ ! -d ngx_http_geoip2_module ] && ngx_http_geoip2_module_source
    [ ! -d pcre2 ] && pcre2_source
    [ ! -d quictls ] && quictls_source
#    [ ! -d libressl ] && libressl_source
    [ ! -d zlib ] && zlib_source
popd


# 进入目录
if ls $latest_version >/dev/null 2>&1; then
    cd $latest_version
else
    nginx_source
    cd $latest_version
fi
# 编译
make clean >/dev/null 2>&1
./configure  \
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
  --with-stream  \
  --with-stream_realip_module  \
  --with-stream_ssl_module  \
  --with-stream_ssl_preread_module \
  --with-openssl-opt='enable-tls1_3' \
  --with-openssl-opt='enable-ktls' \
  --with-openssl="../ext/quictls" \
  --with-pcre="../ext/pcre2" \
  --with-zlib="../ext/zlib" \
  --add-module="../ext/ngx_brotli" \
  --add-module="../ext/ngx_http_geoip2_module" \
  --with-cc=clang \
  --with-cpp=clang++
  

CC=clang CXX=clang++ make -j $(cat /proc/cpuinfo | grep "processor" | wc -l)

if [ $? -eq 0 ]; then
    llvm-strip objs/nginx
    \cp -f objs/nginx ../nginx
    endtime=`date +'%Y-%m-%d %H:%M:%S'`
    start_seconds=$(date --date="$starttime" +%s);
    end_seconds=$(date --date="$endtime" +%s);
    echo
    ../nginx -V
    echo
    echo -e " \e[1;32m编译成功！\e[0m"
    echo -e " 编译耗时：\e[1;32m"$((end_seconds-start_seconds))"\e[0m 秒"
    echo "systemctl stop nginx"
    systemctl stop nginx
    echo -e "\e[1;32mNginx已经停止\e[0m"
    echo "cp /usr/sbin/nginx{,.bak}"
    echo -e "\e[1;32m旧的nginx已做备份\e[0m"
    cp /usr/sbin/nginx{,.bak}
    cp ~/temp/nginx /usr/sbin/nginx
    echo "systemctl start nginx"
    systemctl start nginx
    echo -e "\e[1;32m新的nginx已成功安装\e[0m"
else
    echo
    echo -e " \e[1;31m编译失败！\033[0m"
    echo -e " 编译耗时：\e[1;31m"$((end_seconds-start_seconds))"\e[0m 秒"
fi
    else
        echo -e "\e[1;31m取消更新操作.\e[0m"
        exit 0
	fi        
else 
    echo -e "\e[1;32m本地安装的Nginx版本\e[0m：$installed_version"
    echo -e "\e[1;32m官网最新版本\e[0m：$latest_version"
    echo -e "\e[1;31m版本不一致\e[0m"        
    echo -e "\e[1;32m执行更新操作...\e[0m"

#  安装所需的依赖
apt update && apt install build-essential ca-certificates zlib1g-dev libpcre3 libpcre3-dev tar unzip libssl-dev wget curl git cmake  golang clang -y && apt build-dep nginx -y 

# 下载源码
mkdir -p temp
mkdir -p /var/cache/nginx/client_temp
cd temp

mkdir -p ext

#latest_version=$(curl -s https://nginx.org/download/ | grep nginx-1.2 | tail -n 1 | awk -F\" '{print $2}' | sed 's/.zip.asc//g')

nginx_source() {
    wget https://nginx.org/download/$latest_version.tar.gz
    tar -zxf $latest_version.tar.gz
}

ngx_brotli_source() {
    git clone https://github.com/google/ngx_brotli --recurse-submodules --depth=1
}

ngx_http_geoip2_module_source() {
    git clone https://github.com/leev/ngx_http_geoip2_module --depth=1
}

pcre2_source() { 
    git clone https://github.com/PCRE2Project/pcre2.git --recurse-submodules --depth=1
    #wget https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.42/pcre2-10.42.tar.gz --no-check-certificate
    #tar -zxf pcre2-10.42.tar.gz && mv pcre2-10.42 pcre2 && rm -f pcre2-10.42.tar.gz
}

quictls_source() {
    git clone https://github.com/quictls/openssl -b openssl-3.0.9+quic-release1 quictls --recurse-submodules --depth=1 
}

#libressl_source(){
#	curl -sL https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-3.8.0.tar.gz | tar --strip-components 1 -C ./libressl -xzvf -
#} 
	
zlib_source() {
    wget https://zlib.net/zlib-1.2.13.tar.gz --no-check-certificate
    tar -zxf zlib-1.2.13.tar.gz && mv zlib-1.2.13 zlib && rm -f zlib-1.2.13.tar.gz
}

pushd ext
    [ ! -d ngx_brotli ] && ngx_brotli_source
    [ ! -d ngx_http_geoip2_module ] && ngx_http_geoip2_module_source
    [ ! -d pcre2 ] && pcre2_source
    [ ! -d quictls ] && quictls_source
#    [ ! -d libressl ] && libressl_source
    [ ! -d zlib ] && zlib_source
popd


# 进入目录
if ls $latest_version >/dev/null 2>&1; then
    cd $latest_version
else
    nginx_source
    cd $latest_version
fi

# 编译
make clean >/dev/null 2>&1
./configure  \
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
  --with-stream  \
  --with-stream_realip_module  \
  --with-stream_ssl_module  \
  --with-stream_ssl_preread_module \
  --with-openssl-opt='enable-tls1_3' \
  --with-openssl-opt='enable-ktls' \
  --with-openssl="../ext/quictls" \
  --with-pcre="../ext/pcre2" \
  --with-zlib="../ext/zlib" \
  --add-module="../ext/ngx_brotli" \
  --add-module="../ext/ngx_http_geoip2_module" \
  --with-cc=clang \
  --with-cpp=clang++
  

CC=clang CXX=clang++ make -j $(cat /proc/cpuinfo | grep "processor" | wc -l)

if [ $? -eq 0 ]; then
    llvm-strip objs/nginx
    \cp -f objs/nginx ../nginx
    endtime=`date +'%Y-%m-%d %H:%M:%S'`
    start_seconds=$(date --date="$starttime" +%s);
    end_seconds=$(date --date="$endtime" +%s);
    echo
    ../nginx -V
    echo
    echo -e " \e[1;32m编译成功！\e[0m"
    echo -e " 编译耗时：\e[1;32m"$((end_seconds-start_seconds))"\e[0m 秒"
    echo "systemctl stop nginx"
    systemctl stop nginx
    echo -e "\e[1;32mNginx已经停止\e[0m"
    echo "cp /usr/sbin/nginx{,.bak}"
    echo -e "\e[1;32m旧的nginx已做备份\e[0m"
    cp /usr/sbin/nginx{,.bak}
    cp ~/temp/nginx /usr/sbin/nginx
    echo "systemctl start nginx"
    systemctl start nginx
    echo -e "\e[1;32m新的nginx已成功安装\e[0m"
else
    echo
    echo -e " \e[1;31m编译失败！\033[0m"
    echo -e " 编译耗时：\e[1;31m"$((end_seconds-start_seconds))"\e[0m 秒"
fi

fi
