#!/bin/bash
# 证书管理终极脚本，支持多CA，DNS API/手动验证，ECC证书，自动部署并重载nginx
# By: BuBuXSY
# Version: 2025-06-25

# 显示欢迎信息
welcome_message() {
    echo "欢迎使用 ACME 证书申请简化工具！"
    echo "本工具帮助你简化证书申请流程，支持自动化的证书申请和更新。"
    echo "默认 CA 供应商为 Let's Encrypt。"
}

# 选择 CA 供应商
select_ca() {
    echo "请选择一个 CA 供应商："
    echo "1) Let's Encrypt (默认)"
    echo "2) Buypass"
    echo "3) ZeroSSL"
    echo "按回车键使用默认的 Let's Encrypt"
    read -p "请输入选项 [1/2/3]（默认直接回车选择 Let's Encrypt）: " ca_choice

    # 如果用户没有输入任何内容，默认使用 Let's Encrypt
    if [ -z "$ca_choice" ]; then
        ca_choice=1
    fi

    case $ca_choice in
        1)
            CA_URL="https://acme-v02.api.letsencrypt.org/directory"
            echo "选择了 Let's Encrypt 作为 CA。"
            ;;
        2)
            CA_URL="https://api.buypass.com/acme/directory"
            echo "选择了 Buypass 作为 CA。"
            ;;
        3)
            CA_URL="https://acme.zerossl.com/v2/DV90"
            echo "选择了 ZeroSSL 作为 CA。"
            ;;
        *)
            echo "无效选项，使用默认的 Let's Encrypt 作为 CA。"
            CA_URL="https://acme-v02.api.letsencrypt.org/directory"
            ;;
    esac
}


# 选择操作
select_operation() {
    echo "你现在要做什么？"
    echo "1) 申请新证书"
    echo "2) 续期证书"
    echo "3) 强制重新更新证书"
    read -p "请输入选项 [1/2/3]: " operation_choice

    case $operation_choice in
        1)
            operation="issue"
            echo "你选择了申请新证书。"
            ;;
        2)
            operation="renew"
            echo "你选择了续期证书。"
            ;;
        3)
            operation="force_renew"
            echo "你选择了强制重新更新证书。"
            ;;
        *)
            echo "无效选项，默认为申请新证书。"
            operation="issue"
            ;;
    esac
}

# 检查域名是否已存在证书
check_domain_exists() {
    read -p "请输入你的域名（例如: *.example.com 或 example.com）: " domain
    # 使用 acme.sh --list 检查证书列表
    existing_cert=$(acme.sh --list | grep "$domain")

    if [ -n "$existing_cert" ]; then
        # 获取该域名的证书有效期
        cert_expiry=$(acme.sh --list | grep "$domain" | awk '{print $3}')
        echo "域名 $domain 已有证书，有效期至: $cert_expiry"
        read -p "是否需要强制更新证书？[y/n]: " force_renew
        if [ "$force_renew" == "y" ]; then
            operation="force_renew"
        else
            operation="renew"
        fi
    else
        echo "域名 $domain 还没有证书，准备申请新证书。"
        operation="issue"
    fi
}

# 安装 socat
install_socat() {
    if ! command -v socat &> /dev/null; then
        echo "socat 未安装，开始安装..."
        sudo apt update && sudo apt install -y socat
    else
        echo "socat 已安装，跳过安装"
    fi
}

# 安装 acme.sh
install_acme() {
    if ! command -v acme.sh &> /dev/null; then
        echo "acme.sh 未安装，开始安装..."
        curl https://get.acme.sh | sh
    else
        echo "acme.sh 已安装，跳过安装"
    fi
    # 创建软链接前检查是否存在
    if [ ! -f /usr/bin/acme.sh ]; then
        ln -s /root/.acme.sh/acme.sh /usr/bin/acme.sh
    else
        echo "/usr/bin/acme.sh 已存在，跳过创建软链接"
    fi
}

# 设置 CA
set_ca() {
    acme.sh --set-default-ca --server "$CA_URL"
}

# 申请证书
issue_cert() {
    echo "开始申请证书..."
    acme.sh --issue --keylength ec-256 --dns -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please
    echo "请按照以下提示添加 DNS TXT 记录："
    echo "Domain: '_acme-challenge.$domain'"
    echo "TXT value: $(acme.sh --issue --keylength ec-256 --dns -d "$domain" | grep "TXT value" | awk '{print $3}')"
    echo "添加完毕后，按 [Enter] 键继续..."
    read -p "按 [Enter] 键继续..."
}

# 续期证书
renew_cert() {
    echo "开始续期证书..."
    renewal_output=$(acme.sh --renew --ecc --dns -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please)
    if echo "$renewal_output" | grep -q "Skipping"; then
        echo "证书尚未到续期时间，下一次续期时间为 $(echo "$renewal_output" | grep 'Next renewal time')"
        read -p "是否强制续期证书？[y/n]: " force_renew
        if [ "$force_renew" == "y" ]; then
            acme.sh --renew --ecc --dns -d "$domain" --force --yes-I-know-dns-manual-mode-enough-go-ahead-please
        fi
    fi
}

# 强制重新更新证书
force_renew_cert() {
    echo "强制重新更新证书..."
    acme.sh --renew --ecc --dns -d "$domain" --force --yes-I-know-dns-manual-mode-enough-go-ahead-please
}

# 安装证书到 Nginx
install_cert() {
    echo "安装证书到 Nginx..."
    mkdir -p /etc/nginx/cert_file
    acme.sh --install-cert -d "$domain" \
        --cert-file /etc/nginx/cert_file/cert.pem \
        --key-file /etc/nginx/cert_file/key.pem \
        --fullchain-file /etc/nginx/cert_file/fullchain.pem \
        --ecc \
        --reloadcmd "service nginx reload"
}

# 主函数
main() {
    welcome_message
    select_ca
    select_operation
    install_socat
    install_acme
    set_ca
    check_domain_exists

    case $operation in
        "issue")
            issue_cert
            ;;
        "renew")
            renew_cert
            ;;
        "force_renew")
            force_renew_cert
            ;;
    esac

    install_cert
    echo "证书操作完成！"
}

# 执行脚本
main
