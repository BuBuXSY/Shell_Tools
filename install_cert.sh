#!/bin/bash

# 安装 acme.sh
if [ ! -d "$HOME/.acme.sh" ]; then
  echo "未安装.acme.sh，正在安装..."
  curl https://get.acme.sh | sh
else
  echo "已安装.acme.sh"
fi

# 切换默认 CA 为 Let's Encrypt
acme.sh --set-default-ca --server letsencrypt

# 添加软链接
ln -s "$HOME/.acme.sh/acme.sh" /usr/bin/acme.sh

# 判断系统类型
if [ -f "/etc/openwrt_release" ]; then
  echo "Detected OpenWrt system"
  INSTALL_CMD="opkg install socat"
elif [ -f "/etc/lsb-release" ]; then
  echo "Detected Ubuntu or similar system"
  INSTALL_CMD="apt install -y socat"
else
  echo "Unsupported system"
  exit 1
fi

# 安装 socat（如果未安装）
if ! command -v socat >/dev/null 2>&1; then
  echo "socat not found, installing..."
  $INSTALL_CMD
fi

# 定义函数：安装证书
install_certificate() {
  domain="$1"
  
  # 发行证书
  acme.sh --issue --keylength ec-256 --dns -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please
  
  # 判断是否继续安装证书
  read -p "已完成 $domain 的 TXT 记录解析，是否继续安装证书？(y/n): " answer
  if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    echo "未安装证书：$domain"
    return
  fi
  acme.sh --renew --ecc --dns -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please
  # 安装证书
  acme.sh --install-cert -d "$domain" --cert-file /etc/nginx/cert_file/cert.crt --key-file /etc/nginx/cert_file/key.crt --fullchain-file /etc/nginx/cert_file/fullchain.pem --ecc --reloadcmd "$RELOAD_CMD"
  
  echo "已安装证书：$domain"
}

# 定义函数：判断是否安装证书
check_certificate() {
  domain="$1"
  cert_file="/etc/nginx/cert_file/cert.crt"
  
  if [ -f "$cert_file" ]; then
    echo "已安装证书：$domain"
  else
    echo "未安装证书：$domain"
  fi
}

# 创建证书存储目录
mkdir -p /etc/nginx/cert_file

# 安装证书
echo "请输入要安装的域名（多个域名请使用空格分隔）："
read -r domains

for domain in $domains; do
  install_certificate "$domain"
done

# 检查证书安装情况
echo "已安装的证书："
for domain in $domains; do
  check_certificate "$domain"
done

