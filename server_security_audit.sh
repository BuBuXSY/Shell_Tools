#!/usr/bin/env bash
# ====================================================
# MIT License
#
# Copyright (c) 2025 BuBuXSY
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ====================================================
# 🛡️ 服务器安全巡检脚本
# 功能：只读检查 SSH、防火墙、开放端口、特权用户、登录失败记录等常见风险点
# By: BuBuXSY
# Version: 2026-05-16
# ====================================================

set -euo pipefail

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

WARNINGS=0
CHECKS=0

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║        🛡️  服务器安全巡检报告               ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

section() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}🔎 $1${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

ok() {
    CHECKS=$((CHECKS + 1))
    echo -e "${GREEN}✅ $1${RESET}"
}

warn() {
    CHECKS=$((CHECKS + 1))
    WARNINGS=$((WARNINGS + 1))
    echo -e "${YELLOW}⚠️  $1${RESET}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${RESET}"
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

read_sshd_value() {
    local key="$1"
    local value=""

    if has_cmd sshd; then
        value=$(sshd -T 2>/dev/null | awk -v k="$(echo "$key" | tr '[:upper:]' '[:lower:]')" '$1 == k {print $2; exit}' || true)
    fi

    if [[ -z "$value" && -f /etc/ssh/sshd_config ]]; then
        value=$(awk -v k="$key" 'tolower($1) == tolower(k) && $1 !~ /^#/ {print $2; exit}' /etc/ssh/sshd_config || true)
    fi

    echo "${value:-unknown}"
}

system_overview() {
    section "系统概览"
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        info "🐧 系统：${PRETTY_NAME:-unknown}"
    else
        info "🐧 系统：$(uname -a)"
    fi
    info "🧬 内核：$(uname -r)"
    info "⏳ 运行时间：$(uptime -p 2>/dev/null || uptime)"
    info "👤 当前用户：$(id -un) / UID $(id -u)"
}

check_ssh() {
    section "SSH 配置"
    if [[ ! -f /etc/ssh/sshd_config ]] && ! has_cmd sshd; then
        warn "未找到 sshd 配置，可能未安装 OpenSSH Server"
        return
    fi

    local port root_login password_auth pubkey_auth permit_empty
    port=$(read_sshd_value Port)
    root_login=$(read_sshd_value PermitRootLogin)
    password_auth=$(read_sshd_value PasswordAuthentication)
    pubkey_auth=$(read_sshd_value PubkeyAuthentication)
    permit_empty=$(read_sshd_value PermitEmptyPasswords)

    info "🚪 SSH 端口：$port"

    case "$root_login" in
        no) ok "Root 远程登录已禁用" ;;
        prohibit-password|without-password) ok "Root 仅允许密钥登录：$root_login" ;;
        yes) warn "Root 远程登录开启，建议改为 no 或 prohibit-password" ;;
        *) warn "Root 登录策略未知：$root_login" ;;
    esac

    case "$password_auth" in
        no) ok "SSH 密码登录已禁用" ;;
        yes) warn "SSH 密码登录开启，建议改用密钥登录并关闭 PasswordAuthentication" ;;
        *) warn "SSH 密码登录策略未知：$password_auth" ;;
    esac

    case "$pubkey_auth" in
        yes|unknown) ok "SSH 公钥登录可用或使用系统默认值：$pubkey_auth" ;;
        no) warn "SSH 公钥登录被禁用，建议开启 PubkeyAuthentication" ;;
        *) info "🔑 SSH 公钥登录：$pubkey_auth" ;;
    esac

    case "$permit_empty" in
        no|unknown) ok "空密码登录未开启或使用安全默认值：$permit_empty" ;;
        yes) warn "允许空密码登录，必须关闭 PermitEmptyPasswords" ;;
        *) info "🧩 空密码策略：$permit_empty" ;;
    esac
}

check_ports() {
    section "开放端口"
    if has_cmd ss; then
        info "📡 当前监听端口："
        ss -lntup 2>/dev/null | awk 'NR==1 || /LISTEN|UNCONN/ {print "   " $0}' || true
    elif has_cmd netstat; then
        info "📡 当前监听端口："
        netstat -lntup 2>/dev/null | awk 'NR<=2 || /LISTEN|udp/ {print "   " $0}' || true
    else
        warn "未找到 ss 或 netstat，无法检查监听端口"
        return
    fi

    ok "端口列表已输出，请确认只暴露必要服务"
}

check_firewall() {
    section "防火墙状态"
    local found=0

    if has_cmd ufw; then
        found=1
        ufw status verbose 2>/dev/null | sed 's/^/   /' || true
    fi

    if has_cmd firewall-cmd; then
        found=1
        if firewall-cmd --state >/dev/null 2>&1; then
            ok "firewalld 正在运行"
            firewall-cmd --list-all 2>/dev/null | sed 's/^/   /' || true
        else
            warn "firewalld 未运行"
        fi
    fi

    if has_cmd nft; then
        found=1
        local nft_output
        local nft_rules
        if nft_output=$(nft list ruleset 2>/dev/null); then
            nft_rules=$(printf '%s\n' "$nft_output" | wc -l | awk '{print $1}')
        else
            nft_rules=0
            warn "nftables 规则不可读取，请确认权限或内核支持"
        fi

        if [[ "$nft_rules" -gt 0 ]]; then
            ok "nftables 存在规则，共 ${nft_rules} 行"
        else
            warn "nftables 未发现规则"
        fi
    fi

    if [[ "$found" -eq 0 ]]; then
        warn "未检测到 ufw / firewalld / nft，建议确认云防火墙或本机防火墙策略"
    fi
}

check_accounts() {
    section "账号与权限"
    info "👑 UID 0 账号："
    awk -F: '$3 == 0 {print "   " $1}' /etc/passwd

    local uid0_count
    uid0_count=$(awk -F: '$3 == 0 {count++} END {print count+0}' /etc/passwd)
    if [[ "$uid0_count" -eq 1 ]]; then
        ok "只有一个 UID 0 账号"
    else
        warn "发现多个 UID 0 账号，请确认是否必要"
    fi

    if getent group sudo >/dev/null 2>&1; then
        info "🧰 sudo 组成员：$(getent group sudo | cut -d: -f4)"
    fi
    if getent group wheel >/dev/null 2>&1; then
        info "🧰 wheel 组成员：$(getent group wheel | cut -d: -f4)"
    fi
}

check_login_failures() {
    section "登录失败记录"
    if has_cmd journalctl; then
        info "🧾 最近 SSH 登录失败记录："
        journalctl -u ssh -u sshd --since "24 hours ago" --no-pager 2>/dev/null \
            | grep -Ei "failed password|invalid user|authentication failure" \
            | tail -n 10 \
            | sed 's/^/   /' || true
        ok "已检查最近 24 小时 SSH 失败日志"
    elif [[ -f /var/log/auth.log ]]; then
        grep -Ei "failed password|invalid user|authentication failure" /var/log/auth.log \
            | tail -n 10 \
            | sed 's/^/   /' || true
        ok "已检查 /var/log/auth.log"
    elif [[ -f /var/log/secure ]]; then
        grep -Ei "failed password|invalid user|authentication failure" /var/log/secure \
            | tail -n 10 \
            | sed 's/^/   /' || true
        ok "已检查 /var/log/secure"
    else
        warn "未找到可读的认证日志"
    fi
}

check_fail2ban() {
    section "防爆破组件"
    if has_cmd fail2ban-client; then
        if fail2ban-client ping >/dev/null 2>&1; then
            ok "fail2ban 正在运行"
            fail2ban-client status 2>/dev/null | sed 's/^/   /' || true
        else
            warn "fail2ban 已安装但未运行"
        fi
    else
        warn "未安装 fail2ban，公网 SSH 建议部署防爆破策略"
    fi
}

check_world_writable() {
    section "高风险权限"
    info "🧹 检查常见目录下的全局可写文件/目录（最多显示 20 条）"
    find /etc /usr/local /opt -xdev -perm -0002 -not -type l 2>/dev/null \
        | head -n 20 \
        | sed 's/^/   /' || true
    ok "全局可写项检查完成"
}

summary() {
    section "巡检结论"
    if [[ "$WARNINGS" -eq 0 ]]; then
        echo -e "${GREEN}✅🎉 共完成 ${CHECKS} 项检查，未发现明显风险。${RESET}"
    else
        echo -e "${YELLOW}⚠️📌 共完成 ${CHECKS} 项检查，发现 ${WARNINGS} 个需要确认的风险点。${RESET}"
    fi
    echo -e "${CYAN}📝 本脚本只读巡检，不会修改系统配置。${RESET}"
}

main() {
    print_banner
    system_overview
    check_ssh
    check_ports
    check_firewall
    check_accounts
    check_login_failures
    check_fail2ban
    check_world_writable
    summary
}

main "$@"
