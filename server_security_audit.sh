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
# Version: 2026-07-11
# ====================================================

set -euo pipefail

# Optional embedded UI; the script remains standalone when the shared library is absent.
COLOR_MODE="${COLOR_MODE:-auto}"
init_colors() {
    local mode="$COLOR_MODE"
    case "$mode" in auto|always|never) ;; *) mode=auto ;; esac
    case "$mode" in
        always) COLOR_ENABLED=1 ;;
        auto)
            if [[ -t 2 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then COLOR_ENABLED=1; else COLOR_ENABLED=0; fi
            ;;
        never) COLOR_ENABLED=0 ;;
    esac
    if [[ "$COLOR_ENABLED" == 1 ]]; then
        GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; BLUE=$'\033[36m'; CYAN=$'\033[36m'; MAGENTA=$'\033[35m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
    else GREEN=; YELLOW=; RED=; BLUE=; CYAN=; MAGENTA=; BOLD=; RESET=; fi
}
init_colors

WARNINGS=0
CHECKS=0
EXIT_ON_WARNING="${EXIT_ON_WARNING:-0}"

usage() {
    cat <<EOF
🛡️ 服务器安全巡检

用法:
  ./server_security_audit.sh

环境变量:
  EXIT_ON_WARNING  🚦 设为 1 时，发现风险点后以状态码 1 退出；默认 0
EOF
}

print_banner() { printf '%b⚡ NOC // 服务器安全巡检%b
' "$CYAN$BOLD" "$RESET"; }
section() { printf '%b
◆ %s%b
' "$MAGENTA$BOLD" "$1" "$RESET"; }
ok() { CHECKS=$((CHECKS + 1)); printf '%b[✓] %s%b
' "$GREEN" "$1" "$RESET"; }
warn() { CHECKS=$((CHECKS + 1)); WARNINGS=$((WARNINGS + 1)); printf '%b[!] %s%b
' "$YELLOW" "$1" "$RESET"; }
info() { printf '%b[ℹ] %s%b
' "$BLUE" "$1" "$RESET"; }

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

validate() {
    case "$#" in
        0) ;;
        1)
            if [[ "$1" == "-h" || "$1" == "--help" ]]; then
                usage
                exit 0
            fi
            echo -e "${RED}❌ 未知参数：$1${RESET}" >&2
            usage >&2
            exit 2
            ;;
        *)
            echo -e "${RED}❌ 参数过多，本脚本通过环境变量接收配置${RESET}" >&2
            usage >&2
            exit 2
            ;;
    esac

    if [[ "$EXIT_ON_WARNING" != "0" && "$EXIT_ON_WARNING" != "1" ]]; then
        echo -e "${RED}❌ EXIT_ON_WARNING 只能是 0 或 1${RESET}" >&2
        exit 2
    fi

    local cmd
    for cmd in awk grep sed tail find uname id hostname tr; do
        if ! has_cmd "$cmd"; then
            echo -e "${RED}❌ 缺少必要命令：$cmd${RESET}" >&2
            exit 1
        fi
    done
}

SSHD_EFFECTIVE_CONFIG=""
SSHD_EFFECTIVE_OK=0
SSHD_STATIC_CONFIG_OK=0

load_sshd_effective_config() {
    if ! has_cmd sshd; then
        return 1
    fi

    local host_name
    host_name=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo localhost)
    if SSHD_EFFECTIVE_CONFIG=$(sshd -T -C "user=root,host=${host_name},addr=127.0.0.1" 2>/dev/null); then
        SSHD_EFFECTIVE_OK=1
        return 0
    fi
    return 1
}

prepare_sshd_config_source() {
    if has_cmd sshd; then
        if load_sshd_effective_config; then
            return 0
        fi
        warn "sshd -T 有效配置解析失败；为避免忽略 Include / Match，不使用主配置文件推断安全结论"
        return 1
    fi

    if [[ ! -r /etc/ssh/sshd_config ]]; then
        return 1
    fi
    if grep -Eiq '^[[:space:]]*(include|match)([[:space:]]|$)' /etc/ssh/sshd_config; then
        warn "缺少 sshd 且主配置包含 Include / Match，无法可靠计算 SSH 有效配置"
        return 1
    fi

    SSHD_STATIC_CONFIG_OK=1
    warn "缺少 sshd，仅按不含 Include / Match 的主配置做静态检查"
    return 0
}

read_sshd_value() {
    local key="$1"
    local value=""

    if [[ "$SSHD_EFFECTIVE_OK" -eq 1 ]]; then
        value=$(awk -v k="$(echo "$key" | tr '[:upper:]' '[:lower:]')" '$1 == k {print $2; exit}' \
            <<< "$SSHD_EFFECTIVE_CONFIG" || true)
    fi

    if [[ -z "$value" && "$SSHD_STATIC_CONFIG_OK" -eq 1 ]]; then
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

    prepare_sshd_config_source || true

    local port root_login password_auth kbd_auth auth_methods pubkey_auth permit_empty
    port=$(read_sshd_value Port)
    root_login=$(read_sshd_value PermitRootLogin)
    password_auth=$(read_sshd_value PasswordAuthentication)
    kbd_auth=$(read_sshd_value KbdInteractiveAuthentication)
    auth_methods=$(read_sshd_value AuthenticationMethods)
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
        no) info "PasswordAuthentication 已禁用" ;;
        yes) warn "SSH 密码登录开启，建议改用密钥登录并关闭 PasswordAuthentication" ;;
        *) warn "SSH 密码登录策略未知：$password_auth" ;;
    esac

    case "$kbd_auth" in
        no) info "KbdInteractiveAuthentication 已禁用" ;;
        yes) warn "SSH 键盘交互认证开启，仍可能允许口令登录" ;;
        *) warn "SSH 键盘交互认证策略未知：$kbd_auth" ;;
    esac

    if [[ "$password_auth" == "no" && "$kbd_auth" == "no" ]]; then
        ok "SSH 口令类登录已禁用"
    fi
    if [[ "$auth_methods" == *password* || "$auth_methods" == *keyboard-interactive* ]]; then
        warn "AuthenticationMethods 仍要求口令类认证：$auth_methods"
    elif [[ "$auth_methods" != "unknown" && "$auth_methods" != "any" ]]; then
        info "AuthenticationMethods：$auth_methods"
    fi

    case "$pubkey_auth" in
        yes) ok "SSH 公钥登录已启用" ;;
        no) warn "SSH 公钥登录被禁用，建议开启 PubkeyAuthentication" ;;
        *) warn "无法确认 SSH 公钥登录策略：$pubkey_auth" ;;
    esac

    case "$permit_empty" in
        no) ok "空密码登录已禁用" ;;
        yes) warn "允许空密码登录，必须关闭 PermitEmptyPasswords" ;;
        *) warn "无法确认空密码登录策略：$permit_empty" ;;
    esac
}

check_ports() {
    section "开放端口"
    local output
    if has_cmd ss; then
        info "📡 当前监听端口："
        if output=$(ss -lntup 2>/dev/null); then
            printf '%s\n' "$output" | awk 'NR==1 || /LISTEN|UNCONN/ {print "   " $0}'
        else
            warn "ss 存在，但无法读取监听端口"
            return
        fi
    elif has_cmd netstat; then
        info "📡 当前监听端口："
        if output=$(netstat -lntup 2>/dev/null); then
            printf '%s\n' "$output" | awk 'NR<=2 || /LISTEN|udp/ {print "   " $0}'
        else
            warn "netstat 存在，但无法读取监听端口"
            return
        fi
    else
        warn "未找到 ss 或 netstat，无法检查监听端口"
        return
    fi

    ok "端口列表已输出，请确认只暴露必要服务"
}

check_firewall() {
    section "防火墙状态"
    local found=0
    local output

    if has_cmd ufw; then
        found=1
        if output=$(ufw status verbose 2>/dev/null); then
            printf '%s\n' "$output" | sed 's/^/   /'
            if printf '%s\n' "$output" | grep -Eqi '^Status:[[:space:]]+active'; then
                ok "ufw 正在运行"
            else
                warn "ufw 未启用"
            fi
        else
            warn "ufw 状态不可读取，请确认权限"
        fi
    fi

    if has_cmd firewall-cmd; then
        found=1
        if firewall-cmd --state >/dev/null 2>&1; then
            ok "firewalld 正在运行"
            if output=$(firewall-cmd --list-all 2>/dev/null); then
                printf '%s\n' "$output" | sed 's/^/   /'
            else
                warn "firewalld 规则不可读取，请确认权限"
            fi
        else
            warn "firewalld 未运行"
        fi
    fi

    if has_cmd nft; then
        found=1
        local nft_output
        local nft_rules
        if nft_output=$(nft list ruleset 2>/dev/null); then
            nft_rules=$(printf '%s\n' "$nft_output" | awk 'NF {count++} END {print count+0}')
            local input_chain_summary
            local input_chain_count
            local input_drop_count
            input_chain_summary=$(awk '
                function finish_chain() {
                    if (block ~ /type[[:space:]]+filter([[:space:]]|;)/ &&
                        block ~ /hook[[:space:]]+input([[:space:]]|;)/) {
                        input_count++
                        if (block ~ /policy[[:space:]]+drop[[:space:]]*;/) drop_count++
                    }
                    block=""
                    in_chain=0
                }
                /^[[:space:]]*chain[[:space:]]+/ {
                    if (in_chain) finish_chain()
                    block=$0 ORS
                    in_chain=1
                    next
                }
                in_chain {
                    block=block $0 ORS
                    if (/^[[:space:]]*}/) finish_chain()
                }
                END {
                    if (in_chain) finish_chain()
                    print input_count+0, drop_count+0
                }
            ' <<< "$nft_output")
            read -r input_chain_count input_drop_count <<< "$input_chain_summary"
            if [[ "$nft_rules" -eq 0 ]]; then
                warn "nftables 未发现规则"
            elif [[ "$input_chain_count" -eq 0 ]]; then
                warn "nftables 有 ${nft_rules} 行规则，但未发现 type filter / hook input 基础链，可能只有 NAT/容器规则"
            elif [[ "$input_drop_count" -eq "$input_chain_count" ]]; then
                ok "nftables 的 ${input_chain_count} 个 filter/input 基础链默认策略均为 drop"
            else
                warn "nftables 的 ${input_chain_count} 个 filter/input 基础链中仅 ${input_drop_count} 个使用 policy drop，不能确认默认拒绝"
            fi
        else
            warn "nftables 规则不可读取，请确认权限或内核支持"
        fi
    fi

    if [[ "$found" -eq 0 ]]; then
        warn "未检测到 ufw / firewalld / nft，建议确认云防火墙或本机防火墙策略"
    fi
}

check_accounts() {
    section "账号与权限"
    if [[ ! -r /etc/passwd ]]; then
        warn "无法读取 /etc/passwd"
        return
    fi

    info "👑 UID 0 账号："
    awk -F: '$3 == 0 {print "   " $1}' /etc/passwd

    local uid0_count
    uid0_count=$(awk -F: '$3 == 0 {count++} END {print count+0}' /etc/passwd)
    if [[ "$uid0_count" -eq 1 ]]; then
        ok "只有一个 UID 0 账号"
    else
        warn "发现多个 UID 0 账号，请确认是否必要"
    fi

    if has_cmd getent && getent group sudo >/dev/null 2>&1; then
        local sudo_group
        sudo_group=$(getent group sudo)
        info "🧰 sudo 组成员：${sudo_group##*:}"
    fi
    if has_cmd getent && getent group wheel >/dev/null 2>&1; then
        local wheel_group
        wheel_group=$(getent group wheel)
        info "🧰 wheel 组成员：${wheel_group##*:}"
    fi
}

check_login_failures() {
    section "登录失败记录"
    local auth_data=""
    local hits=""
    local source=""

    if has_cmd journalctl; then
        if auth_data=$(journalctl -u ssh -u sshd --since "24 hours ago" --no-pager 2>/dev/null); then
            source="最近 24 小时 systemd journal"
        fi
    fi

    if [[ -z "$source" && -r /var/log/auth.log ]]; then
        auth_data=$(tail -n 5000 /var/log/auth.log 2>/dev/null || true)
        source="/var/log/auth.log 最近 5000 行"
    elif [[ -z "$source" && -r /var/log/secure ]]; then
        auth_data=$(tail -n 5000 /var/log/secure 2>/dev/null || true)
        source="/var/log/secure 最近 5000 行"
    fi

    if [[ -z "$source" ]]; then
        warn "未找到可读的认证日志"
        return
    fi

    hits=$(printf '%s\n' "$auth_data" \
        | grep -Ei "failed password|invalid user|authentication failure" \
        | tail -n 10 || true)
    if [[ -n "$hits" ]]; then
        info "🧾 最近 SSH 登录失败记录："
        printf '%s\n' "$hits" | sed 's/^/   /'
        warn "在 ${source} 中发现登录失败记录，请结合来源 IP 判断是否为爆破"
    else
        ok "${source}中未发现 SSH 登录失败记录"
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
    local dirs=()
    local dir
    local output
    for dir in /etc /usr/local /opt; do
        [[ -d "$dir" ]] && dirs+=("$dir")
    done

    if [[ "${#dirs[@]}" -eq 0 ]]; then
        warn "未找到可检查的常见目录"
        return
    fi

    local scan_status=0
    output=$(find "${dirs[@]}" -xdev -perm -0002 -not -type l -print 2>/dev/null \
        | sed -n '1,20p') || scan_status=$?

    if [[ -n "$output" ]]; then
        printf '%s\n' "$output" | sed 's/^/   /'
        warn "发现全局可写文件或目录，请逐项确认权限是否必要"
    elif [[ "$scan_status" -eq 0 ]]; then
        ok "未发现全局可写文件或目录"
    fi

    if [[ "$scan_status" -ne 0 ]]; then
        warn "全局可写项检查不完整，以上结果可能不是全部，请检查目录权限"
    fi
}

summary() {
    section "巡检结论"
    if [[ "$WARNINGS" -eq 0 ]]; then
        echo -e "${GREEN}✅🎉 共完成 ${CHECKS} 项检查，未发现明显风险。${RESET}"
    else
        echo -e "${YELLOW}⚠️📌 共完成 ${CHECKS} 项检查，发现 ${WARNINGS} 个需要确认的风险点。${RESET}"
    fi
    echo -e "${CYAN}📝 本脚本只读巡检，不会修改系统配置。${RESET}"

    if [[ "$EXIT_ON_WARNING" == "1" && "$WARNINGS" -gt 0 ]]; then
        return 1
    fi
}

main() {
    validate "$@"
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
