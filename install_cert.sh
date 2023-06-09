#!/bin/bash

# 定义变量
acme_sh_path="$HOME/.acme.sh/acme.sh"
cert_dir="/etc/nginx/cert_file"

# 安装 acme.sh
if [ ! -d "$HOME/.acme.sh" ]; then
  echo -e "\e[31m未安装acme.sh，正在安装...\e[0m"
  curl https://get.acme.sh | sh
else 
  echo -e "\e[32m已安装.acme.sh\e[0m"
fi

# 切换默认 CA 为 Let's Encrypt
"$acme_sh_path" --set-default-ca --server letsencrypt

# 添加软链接
ln -s "$acme_sh_path" /usr/bin/acme.sh

# 判断系统类型
if [ -f "/etc/openwrt_release" ]; then
  echo "Detected OpenWrt system"
  INSTALL_CMD="opkg install socat"
  RELOAD_CMD="service nginx reload"
elif [ -f "/etc/lsb-release" ]; then
  echo "Detected Debian series system"
  INSTALL_CMD="apt install -y socat"
  RELOAD_CMD="service nginx force-reload"
else
  echo "Unsupported system"
  exit 1
fi

# 安装 socat（如果未安装）
if ! command -v socat >/dev/null 2>&1; then
  echo -e "\e[31m未安装socat，正在安装...\e[0m"
  eval "$install_cmd"
fi



# 定义函数：安装证书
install_certificate() {
  domain="$1"
  
# 检查证书是否已经安装
  samecert_file="$HOME/.acme.sh/${domain}_ecc" 
  if [ -d "$samecert_file" ]; then
    echo -e "\e[31m证书已经安装\e[0m：$domain"
    read -p "证书已存在，是否强制更新？(y/n): " answer
    if [[ "$answer" == "y" ]] || [[ "$answer" == "Y" ]]; then
      "$acme_sh_path" --force --renew --ecc --dns -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please
      echo -e "\e[32m已更新证书\e[0m：$domain"
    else
      echo -e "\e[31m未更新证书\e[0m：$domain"
    fi
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
  "$acme_sh_path" --install-cert -d "$domain" --cert-file "$cert_dir/cert.crt" --key-file "$cert_dir/key.crt" --fullchain-file "$cert_dir/fullchain.pem" --ecc --reloadcmd "$reload_cmd"

  echo "已安装证书：$domain"
}

# 定义函数：检查证书安装情况
check_certificate() {
  domain="$1"
  cert_file="$cert_dir/cert.crt"
  
  if [ -f "$cert_file" ]; then
    echo -e "\e[32m已安装证书\e[0m：$domain"
  else
    echo -e "\e[31m未安装证书\e[0m：$domain"
  fi
}

# 创建证书存储目录
mkdir -p "$cert_dir"

# 安装证书
echo -e "\e[32m请输入要安装的域名（多个域名请使用空格分隔）：\e[0m"
read -r domains

for domain in $domains; do
  install_certificate "$domain"
done

# 检查证书安装情况
echo -e "\xE2\x9D\xA4证书安装情况：\xE2\x9D\xA4"
for domain in $domains; do
  check_certificate "$domain"
done


