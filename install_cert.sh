#!/bin/bash
# 证书管理终极脚本，支持多CA，DNS API/手动验证，ECC证书，自动部署并重载nginx
# 作者: BuBuXSY
# 版本: 2025-06-25

set -euo pipefail

# ==== 颜色和格式 ====
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

info()    { echo -e "${CYAN}ℹ️ [INFO]${RESET} $*"; }
success() { echo -e "${GREEN}✅ [SUCCESS]${RESET} $*"; }
warn()    { echo -e "${YELLOW}⚠️ [WARN]${RESET} $*"; }
error()   { echo -e "${RED}❌ [ERROR]${RESET} $*" >&2; }
prompt()  { echo -ne "${MAGENTA}👉 $*${RESET}"; }

# ==== 变量 ====
acme_home="$HOME/.acme.sh"
cert_dir="/etc/nginx/cert_file"

# ==== 函数 ====

# 依赖检查和安装
check_dependency() {
  local dep=$1
  if ! command -v "$dep" >/dev/null 2>&1; then
    warn "$dep 未安装，尝试安装中..."
    install_dependency "$dep"
  else
    success "$dep 已安装"
  fi
}

# 安装依赖
install_dependency() {
  local dep=$1
  if [[ -f /etc/openwrt_release ]]; then
    opkg update && opkg install "$dep"
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y "$dep"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "$dep"
  else
    error "无法自动安装 $dep，请手动安装后重试"
    exit 1
  fi
  success "$dep 安装完成"
}

# 检查acme.sh
check_acme_sh() {
  if [ ! -x "$acme_home/acme.sh" ]; then
    warn "未检测到 acme.sh，尝试安装中..."
    curl https://get.acme.sh | sh
    success "acme.sh 安装完成"
  else
    success "acme.sh 已安装"
  fi
}

# 检查是否为IPv6-only环境
check_ipv6_only() {
  if command -v ip >/dev/null 2>&1; then
    local has_ipv4_route has_ipv6_route
    has_ipv4_route=$(ip route | grep default | grep -v "::" || true)
    has_ipv6_route=$(ip -6 route | grep default || true)
    if [[ -z "$has_ipv4_route" && -n "$has_ipv6_route" ]]; then
      warn "检测到当前主机为 IPv6-only 环境，部分服务可能无法正常使用。"
    else
      success "检测到支持 IPv4 和/或 IPv6 网络。"
    fi
  else
    warn "未检测到 ip 命令，无法检测网络类型。"
  fi
}

# 安装acme.sh cron任务
install_cron_job() {
  if command -v crontab >/dev/null 2>&1; then
    if crontab -l 2>/dev/null | grep -q "acme.sh --cron"; then
      info "已存在 acme.sh 定时任务"
    else
      (crontab -l 2>/dev/null; echo "0 3 * * * \"$acme_home\"/acme.sh --cron --home \"$acme_home\" > /dev/null 2>&1") | crontab -
      success "已添加每日凌晨3点自动续期的定时任务"
    fi
  elif [[ -f /etc/openwrt_release ]]; then
    local cron_file="/etc/crontabs/root"
    if grep -q "acme.sh --cron" "$cron_file" 2>/dev/null; then
      info "已存在 acme.sh 定时任务 (OpenWrt crond)"
    else
      echo "0 3 * * * $acme_home/acme.sh --cron --home $acme_home > /dev/null 2>&1" >> "$cron_file"
      /etc/init.d/cron restart
      success "已添加每日凌晨3点自动续期的定时任务 (OpenWrt crond)"
    fi
  else
    warn "未检测到 crontab，无法添加自动续期定时任务，请手动设置"
  fi
}

# 选择CA服务器
select_ca_server() {
  info "请选择 CA 服务器："
  echo "  1) Let's Encrypt 正式环境"
  echo "  2) Let's Encrypt 测试环境（Staging）"
  echo "  3) Buypass"
  echo "  4) ZeroSSL"
  echo "  5) SSL.com"
  prompt "请输入数字并回车 (默认1): "
  read -r ca_choice
  ca_choice=${ca_choice:-1}
  case $ca_choice in
    1) ca_server="https://acme-v02.api.letsencrypt.org/directory" ;;
    2) ca_server="https://acme-staging-v02.api.letsencrypt.org/directory" ;;
    3) ca_server="https://api.buypass.com/acme/directory" ;;
    4) ca_server="https://acme.zerossl.com/v2/DV90/directory" ;;
    5) ca_server="https://api.ssl.com/cli/dv/acme/directory" ;;
    *) warn "无效输入，默认使用 Let's Encrypt 正式环境"; ca_server="https://acme-v02.api.letsencrypt.org/directory" ;;
  esac
  info "当前选择 CA 服务器为：$ca_server"
  prompt "确认选择此 CA 服务器吗？ [Y/n]: "
  read -r confirm
  confirm=${confirm:-Y}
  if [[ ! $confirm =~ ^[Yy]$ ]]; then
    info "请重新选择 CA 服务器"
    select_ca_server
  fi
}

# 使用DNS API自动验证
check_dns_api_env() {
  local mode=$1
  if [[ "$mode" == "1" ]]; then
    case "$DNS_API_PROVIDER" in
      dns_cf)
        if [[ -z "${CF_Token:-}" && -z "${CF_Key:-}" ]]; then
          error "未检测到 Cloudflare API 环境变量，请设置 CF_Token 或 CF_Key"
          exit 1
        else
          success "检测到 Cloudflare API 环境变量"
        fi
        ;;
      dns_ali)
        if [[ -z "${Ali_Key:-}" && -z "${Ali_Secret:-}" ]]; then
          error "未检测到阿里云API环境变量，请设置 Ali_Key 和 Ali_Secret"
          exit 1
        else
          success "检测到阿里云 API 环境变量"
        fi
        ;;
      *)
        warn "未实现针对 $DNS_API_PROVIDER 的环境变量检测"
        ;;
    esac
  fi
}

# 自动部署证书
deploy_certificate() {
  local domains="$1"
  local target_dir="${2:-$cert_dir}"

  local reload_cmd
  if [[ -f /etc/openwrt_release ]]; then
    reload_cmd="/etc/init.d/nginx reload"
  else
    reload_cmd="systemctl reload nginx"
  fi

  info "注册证书安装与自动部署..."
  if acme.sh --install-cert -d "$domains" \
    --cert-file "$target_dir/cert.pem" \
    --key-file "$target_dir/key.pem" \
    --fullchain-file "$target_dir/fullchain.pem" \
    --reloadcmd "$reload_cmd" \
    --ecc; then
    success "证书部署命令已注册成功！"
    info "证书路径：$target_dir/cert.pem"
    info "私钥路径：$target_dir/key.pem"
    info "完整链路径：$target_dir/fullchain.pem"
  else
    error "注册证书部署失败，请检查日志。"
    exit 1
  fi

  info "尝试立即重载 nginx..."
  if command -v nginx >/dev/null 2>&1; then
    if nginx -t >/dev/null 2>&1; then
      eval "$reload_cmd" && success "nginx 重载成功！" || warn "nginx 重载失败，请手动检查"
    else
      warn "nginx 配置检测失败，跳过重载"
    fi
  else
    warn "未检测到 nginx 命令，跳过重载"
  fi
}

# 证书申请函数
apply_certificate() {
  local domains="$1"
  local mode="$2"
  local ca="$3"

  info "开始申请证书，域名：$domains"
  info "使用 CA 服务器：$ca"

  check_dns_api_env "$mode"  # 传入mode参数检测

  # 证书申请流程...
}

# 显示证书状态
show_certificate_status() {
  local cert_file="${1:-$cert_dir/fullchain.pem}"
  if [ ! -f "$cert_file" ]; then
    warn "证书文件不存在：$cert_file"
    return
  fi
  # 证书有效期检测...
}

# 主菜单
main_menu() {
  while true; do
    echo
    info "欢迎使用证书管理脚本，请选择操作："
    echo "  1) 申请新证书"
    echo "  2) 查看已安装证书状态"
    echo "  3) 检测证书有效期并续期"
    echo "  4) 输出 nginx TLS 配置示例"
    echo "  5) 退出"
    prompt "请输入数字并回车: "
    read -r choice
    case $choice in
      1)
        prompt "请输入要申请证书的域名（支持泛域名，多个空格分隔，如 *.example.com）: "
        read -r domains
        if [[ -z "$domains" ]]; then
          warn "域名不能为空"
          continue
        fi
        echo
        info "请选择验证方式："
        echo "  1) DNS API 自动验证（需预先配置对应API环境变量）"
        echo "  2) DNS 手动验证（需手动添加TXT记录）"
        prompt "输入 1 或 2 并回车: "
        read -r mode
        if [[ "$mode" != "1" && "$mode" != "2" ]]; then
          warn "无效输入，默认手动验证"
          mode=2
        fi
        echo
        select_ca_server
        echo
        apply_certificate "$domains" "$mode" "$ca_server"
        ;;
      2)
        prompt "请输入要查看状态的证书文件完整路径（回车默认使用 $cert_dir/fullchain.pem）: "
        read -r cert_file_input
        cert_file_input=${cert_file_input:-$cert_dir/fullchain.pem}
        show_certificate_status "$cert_file_input"
        ;;
      3)
        prompt "请输入要续期的证书域名: "
        read -r domain
        if [[ -z "$domain" ]]; then
          warn "域名不能为空"
          continue
        fi
        renew_certificate "$domain"
        ;;
      4)
        print_nginx_tls_template
        ;;
      5)
        info "退出脚本，拜拜！"
        exit 0
        ;;
      *)
        warn "无效输入，请重新选择"
        ;;
    esac
  done
}

# ==== 主程序 ====
check_and_install_dependencies
main_menu
