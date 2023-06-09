#!/bin/bash

# 定义变量
acme_sh_path="$HOME/.acme.sh/acme.sh"
cert_dir="/etc/nginx/cert_file"

# 安装 acme.sh
if [ ! -d "$HOME/.acme.sh" ]; then
  echo "未安装.acme.sh，正在安装..."
  curl https://get.acme.sh | sh
else
  echo "已安装.acme.sh"
fi

# 切换默认 CA 为 Let's Encrypt
"$acme_sh_path" --set-default-ca --server letsencrypt

# 添加软链接
ln -s "$acme_sh_path" /usr/bin/acme.sh

# 判断系统类型
os_type=$(uname -a)
if [[ $os_type == *"OpenWrt"* ]]; then
  echo "Detected OpenWrt system"
  install_cmd="opkg install socat"
  reload_cmd="service nginx reload"
elif [[ $os_type == *"Ubuntu"* ]] || [[ $os_type == *"Debian"* ]]; then
  echo "Detected Ubuntu or similar system"
  install_cmd="apt install -y socat"
  reload_cmd="service nginx force-reload"
else
  echo "Unsupported system"
  exit 1
fi

# 安装 socat（如果未安装）
if ! command -v socat >/dev/null 2>&1; then
  echo "socat not found, installing..."
  eval "$install_cmd"
fi

# 定义函数：安装证书
install_certificate() {
  domain="$1"
  
  # 检查证书是否已经安装
  cert_file="$cert_dir/$domain.crt"
  if [ -f "$cert_file" ]; then
    echo "证书已经安装：$domain"
    return
  fi
  
  # 发行证书
  "$acme_sh_path" --issue --keylength ec-256 --dns -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please
  
  # 判断是否继续安装证书
  read -p "请将TXT记录复制到DNS解析商，如果已完成 $domain 的 TXT 记录解析，请选“Y”继续安装证书(y/n): " answer
  if [[ "$answer" != "y" ]] && [[ "$answer" != "Y" ]]; then
    echo "未安装证书：$domain"
    return
  fi
  
  # 安装证书
  "$acme_sh_path" --renew --ecc --dns -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please
  "$acme_sh_path" --install-cert -d "$domain" --cert-file "$cert_dir/$domain.crt" --key-file "$cert_dir/$domain.key" --fullchain-file "$cert_dir/$domain.pem" --ecc --reloadcmd "$reload_cmd"

  echo "已安装证书：$domain"
}

# 定义函数：检查证书安装情况
check_certificate() {
  domain="$1"
  cert_file="$cert_dir/$domain.crt"
  
  if [ -f "$cert_file" ]; then
    echo "已安装证书：$domain"
  else
    echo "未安装证书：$domain"
  fi
}

# 创建证书存储目录
mkdir -p "$cert_dir"

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


