#!/bin/bash
# 证书管理终极脚本，支持多CA，DNS API/手动验证，ECC证书，自动部署并重载nginx
# By: BuBuXSY
# Version: 2025-06-25

# 设置颜色和格式
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"
UNDERLINE="\e[4m"

# 设置表情
SUCCESS="✔️"
ERROR="❌"
INFO="ℹ️"
WARNING="⚠️"
THINKING="🤔"
LOADING="⏳"

# 显示欢迎信息
welcome_message() {
    echo -e "${CYAN}${BOLD}欢迎使用 ACME 证书申请简化工具！${RESET}"
    echo -e "${CYAN}本工具帮助你简化证书申请流程，支持自动化的证书申请和更新。${RESET}"
    echo -e "${CYAN}默认 CA 供应商为 Let's Encrypt。${RESET}"
    sleep 1
}

# 显示加载动画
loading_animation() {
    local -r msg="$1"
    local -r pid=$!
    echo -e "${CYAN}$msg ${LOADING}"
    while kill -0 $pid 2>/dev/null; do
        for i in "." ".." "..."; do
            echo -n "$i"
            sleep 0.5
            echo -ne "\r"
        done
    done
}

# 选择 CA 供应商
select_ca() {
    echo -e "${GREEN}请选择一个 CA 供应商：${RESET}"
    echo -e "1) Let's Encrypt (默认)"
    echo -e "2) Buypass"
    echo -e "3) ZeroSSL"
    echo -e "按回车键使用默认的 Let's Encrypt"
    read -p "请输入选项 [1/2/3]（默认直接回车选择 Let's Encrypt）: " ca_choice

    if [ -z "$ca_choice" ]; then
        ca_choice=1
    fi

    case $ca_choice in
        1)
            CA_URL="https://acme-v02.api.letsencrypt.org/directory"
            echo -e "${SUCCESS}选择了 Let's Encrypt 作为 CA。${RESET}"
            ;;
        2)
            CA_URL="https://api.buypass.com/acme/directory"
            echo -e "${SUCCESS}选择了 Buypass 作为 CA。${RESET}"
            ;;
        3)
            CA_URL="https://acme.zerossl.com/v2/DV90"
            echo -e "${SUCCESS}选择了 ZeroSSL 作为 CA。${RESET}"
            ;;
        *)
            echo -e "${ERROR}无效选项，使用默认的 Let's Encrypt 作为 CA。${RESET}"
            CA_URL="https://acme-v02.api.letsencrypt.org/directory"
            ;;
    esac
}

# 选择操作
select_operation() {
    echo -e "${GREEN}你现在要做什么？${RESET}"
    echo -e "1) 申请新证书"
    echo -e "2) 续期证书"
    echo -e "3) 强制重新更新证书"
    read -p "请输入选项 [1/2/3]: " operation_choice

    case $operation_choice in
        1)
            operation="issue"
            echo -e "${SUCCESS}你选择了申请新证书。${RESET}"
            ;;
        2)
            operation="renew"
            echo -e "${SUCCESS}你选择了续期证书。${RESET}"
            # 获取已存在的域名列表
            domains=$(acme.sh --list | awk '{print $1}')
            echo -e "${INFO}已存在以下证书："
            select domain in $domains; do
                if [ -n "$domain" ]; then
                    echo -e "${SUCCESS}你选择了域名 $domain 进行续期。${RESET}"
                    break
                else
                    echo -e "${ERROR}无效选择，请重新选择一个域名。${RESET}"
                fi
            done
            ;;
        3)
            operation="force_renew"
            echo -e "${SUCCESS}你选择了强制重新更新证书。${RESET}"
            # 获取已存在的域名列表
            domains=$(acme.sh --list | awk '{print $1}')
            echo -e "${INFO}已存在以下证书："
            select domain in $domains; do
                if [ -n "$domain" ]; then
                    echo -e "${SUCCESS}你选择了域名 $domain 进行强制更新。${RESET}"
                    break
                else
                    echo -e "${ERROR}无效选择，请重新选择一个域名。${RESET}"
                fi
            done
            ;;
        *)
            echo -e "${ERROR}无效选项，默认为申请新证书。${RESET}"
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
        echo -e "${INFO}域名 $domain 已有证书，有效期至: $cert_expiry${RESET}"
        read -p "是否需要强制更新证书？[y/n]: " force_renew
        if [ "$force_renew" == "y" ]; then
            operation="force_renew"
        else
            operation="renew"
        fi
    else
        echo -e "${INFO}域名 $domain 还没有证书，准备申请新证书。${RESET}"
        operation="issue"
    fi
}

# 安装 socat
install_socat() {
    if ! command -v socat &> /dev/null; then
        echo -e "${YELLOW}socat 未安装，开始安装...${RESET}"
        sudo apt update && sudo apt install -y socat
    else
        echo -e "${SUCCESS}socat 已安装，跳过安装${RESET}"
    fi
}

# 安装 acme.sh
install_acme() {
    if ! command -v acme.sh &> /dev/null; then
        echo -e "${YELLOW}acme.sh 未安装，开始安装...${RESET}"
        curl https://get.acme.sh | sh
    else
        echo -e "${SUCCESS}acme.sh 已安装，跳过安装${RESET}"
    fi
    if [ ! -f /usr/bin/acme.sh ]; then
        ln -s /root/.acme.sh/acme.sh /usr/bin/acme.sh
    else
        echo -e "${SUCCESS}/usr/bin/acme.sh 已存在，跳过创建软链接${RESET}"
    fi
}

# 设置 CA
set_ca() {
    acme.sh --set-default-ca --server "$CA_URL"
}

# 申请证书
issue_cert() {
    echo -e "${CYAN}开始申请证书...${RESET}"
    acme.sh --issue --keylength ec-256 --dns -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please
    echo -e "${INFO}请按照以下提示添加 DNS TXT 记录：${RESET}"
    echo -e "${INFO}Domain: '_acme-challenge.$domain'${RESET}"
    echo -e "${INFO}TXT value: $(acme.sh --issue --keylength ec-256 --dns -d "$domain" | grep "TXT value" | awk '{print $3}')${RESET}"
    echo -e "${INFO}添加完毕后，按 [Enter] 键继续...${RESET}"
    read -p "按 [Enter] 键继续..."

    # 等待 DNS 记录生效并验证
    echo -e "${CYAN}验证 TXT 记录是否生效...${RESET}"
    acme.sh --renew --ecc --dns -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please
}

# 续期证书
renew_cert() {
    echo -e "${CYAN}开始续期证书...${RESET}"
    renewal_output=$(acme.sh --renew --ecc --dns -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please)
    if echo "$renewal_output" | grep -q "Skipping"; then
        echo -e "${INFO}证书尚未到续期时间，下一次续期时间为 $(echo "$renewal_output" | grep 'Next renewal time')${RESET}"
        read -p "是否强制续期证书？[y/n]: " force_renew
        if [ "$force_renew" == "y" ]; then
            acme.sh --renew --ecc --dns -d "$domain" --force --yes-I-know-dns-manual-mode-enough-go-ahead-please
        fi
    fi
}

# 强制重新更新证书
force_renew_cert() {
    echo -e "${CYAN}强制重新更新证书...${RESET}"
    acme.sh --renew --ecc --dns -d "$domain" --force --yes-I-know-dns-manual-mode-enough-go-ahead-please
}

# 安装证书到 Nginx
install_cert() {
    echo -e "${CYAN}安装证书到 Nginx...${RESET}"
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
    echo -e "${SUCCESS}证书操作完成！${RESET}"
}

# 执行脚本
main
