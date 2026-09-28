#!/usr/bin/env bash
# ====================================================
# MIT License
# Copyright (c) 2025 BuBuXSY
# See LICENSE for full text.
# ====================================================
# 🧭🚀 Shell_Tools 平台适配检查
# 功能：识别 Linux、macOS、OpenWrt 的运行能力并给出工具兼容提示
# By: BuBuXSY
# Version: 2026-09-29
# ====================================================

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
if [[ -r "$SCRIPT_DIR/lib/shell_tools_ui.sh" ]]; then
    # shellcheck source=lib/shell_tools_ui.sh
    source "$SCRIPT_DIR/lib/shell_tools_ui.sh"
    st_ui_init
else
    ST_UI_CYAN=''; ST_UI_GREEN=''; ST_UI_YELLOW=''; ST_UI_BOLD=''; ST_UI_RESET=''
fi

usage() {
    cat <<'EOF'
🧭 Shell_Tools 平台适配检查

用法:
  ./platform_check.sh
  ./platform_check.sh --json
  ./platform_check.sh --help

输出当前系统、包管理器、服务管理器、内核能力和脚本适配建议。
EOF
}

has() { command -v "$1" >/dev/null 2>&1; }
main() {
    local json=0 arg os id version arch init package_manager macos=false
    while (($#)); do
        case "$1" in
            --json) json=1; shift ;;
            -h|--help) usage; return 0 ;;
            *) printf '未知参数: %s\n' "$1" >&2; usage >&2; return 2 ;;
        esac
    done

    os=$(uname -s 2>/dev/null || printf unknown)
    [[ "$os" != Darwin ]] || macos=true
    arch=$(uname -m 2>/dev/null || printf unknown)
    id=unknown; version=unknown
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        id="${ID:-unknown}"; version="${VERSION_ID:-unknown}"
    elif [[ "$os" == Darwin ]]; then
        id=macos; version=$(sw_vers -productVersion 2>/dev/null || printf unknown)
    fi
    if has systemctl; then init=systemd; elif has rc-service; then init=openrc; elif has /etc/rc.common; then init=openwrt; else init=none; fi
    if has apt-get; then package_manager=apt; elif has brew; then package_manager=brew; elif has opkg; then package_manager=opkg; elif has apk; then package_manager=apk; elif has dnf; then package_manager=dnf; elif has yum; then package_manager=yum; else package_manager=none; fi

    if ((json)); then
        printf '{"os":"%s","id":"%s","version":"%s","arch":"%s","init":"%s","package_manager":"%s","capabilities":{"systemd":%s,"openwrt":%s,"macos":%s,"nginx":%s,"openssl":%s,"curl":%s}}\n' \
            "$os" "$id" "$version" "$arch" "$init" "$package_manager" \
            "$(has systemctl && printf true || printf false)" "$(has opkg && printf true || printf false)" \
            "$macos" "$(has nginx && printf true || printf false)" \
            "$(has openssl && printf true || printf false)" "$(has curl && printf true || printf false)"
        return 0
    fi

    printf '%s%s🧭 Shell_Tools 平台检查%s\n' "$ST_UI_CYAN" "$ST_UI_BOLD" "$ST_UI_RESET"
    printf '系统: %s (%s %s)\n架构: %s\n服务管理: %s\n包管理器: %s\n' "$os" "$id" "$version" "$arch" "$init" "$package_manager"
    printf '\n能力探针:\n'
    for arg in systemctl opkg brew nginx openssl curl; do
        if has "$arg"; then printf '%s✓%s %-10s 可用\n' "$ST_UI_GREEN" "$ST_UI_RESET" "$arg"; else printf '%s·%s %-10s 不可用或非必需\n' "$ST_UI_YELLOW" "$ST_UI_RESET" "$arg"; fi
    done
    printf '\n适配建议:\n'
    case "$os:$id" in
        Darwin:*) printf '🍎 macOS: 使用 brew 安装依赖；systemd 专属脚本应改用 launchd。\n' ;;
        Linux:openwrt) printf '📡 OpenWrt: 优先使用 opkg 和 procd；避免 systemd、apt 和 GNU 专属参数。\n' ;;
        Linux:*) printf '🐧 Linux: systemd/apt 或发行版对应工具可用时，服务脚本走原生管理器。\n' ;;
        *) printf '🧩 未识别平台: 只运行只读分析工具，并先检查依赖。\n' ;;
    esac
}

main "$@"
