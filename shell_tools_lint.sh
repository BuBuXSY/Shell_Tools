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
# 🧪 Shell_Tools 仓库自检脚本
# 功能：检查 shell 语法、脚本头部规范、emoji / 色彩输出和可执行权限
# By: BuBuXSY
# Version: 2026-07-11
# ====================================================

set -euo pipefail

GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

FAILED=0
CHECKED=0
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

log_info() { echo -e "${BLUE}ℹ️  $1${RESET}"; }
log_ok() { echo -e "${GREEN}✅ $1${RESET}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${RESET}"; }
log_error() { echo -e "${RED}❌ $1${RESET}"; }

banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║        🧪 Shell_Tools 仓库自检               ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

usage() {
    cat <<EOF
🧪 Shell_Tools 仓库自检

用法:
  ./shell_tools_lint.sh
  ./shell_tools_lint.sh --help

脚本始终检查自身所在的仓库根目录，可从任意工作目录执行。
EOF
}

validate_args() {
    case "$#" in
        0) ;;
        1)
            if [[ "$1" == "-h" || "$1" == "--help" ]]; then
                usage
                exit 0
            fi
            log_error "未知参数：$1"
            usage >&2
            exit 2
            ;;
        *)
            log_error "参数过多"
            usage >&2
            exit 2
            ;;
    esac

    if ! command -v grep >/dev/null 2>&1; then
        log_error "缺少必要命令：grep"
        exit 1
    fi
}

fail() {
    FAILED=$((FAILED + 1))
    log_error "$1"
}

check_shell_syntax() {
    local file="$1"
    local shebang=""
    IFS= read -r shebang < "$file" || true

    if [[ "$shebang" == '#!/bin/sh' ]] || [[ "$shebang" == '#!/usr/bin/env sh' ]]; then
        if sh -n "$file"; then
            log_ok "语法通过（sh）：$file"
        else
            fail "语法失败（sh）：$file"
        fi
    elif bash -n "$file"; then
        log_ok "语法通过：$file"
    else
        fail "语法失败：$file"
    fi
}

check_shell_static() {
    local file="$1"
    if command -v shellcheck >/dev/null 2>&1; then
        if shellcheck --severity=warning "$file"; then
            log_ok "ShellCheck 通过：$file"
        else
            fail "ShellCheck 失败：$file"
        fi
    fi
}

check_header() {
    local file="$1"

    grep -Eq '^# .*脚本|^# .*工具' "$file" || fail "缺少 emoji 脚本名称：$file"
    grep -q '^# 功能' "$file" || grep -q '^# 支持' "$file" || grep -q '^# 📦 场景' "$file" || fail "缺少功能说明：$file"
    grep -q '^# By: BuBuXSY' "$file" || fail "缺少署名：$file"
    grep -Eq '^# Version:[[:space:]]*[^[:space:]]+' "$file" || fail "缺少版本日期：$file"
}

check_style() {
    local file="$1"

    grep -Eq '✅|⚠️|❌|ℹ️|🔧|📊|🚀|🛡️|🔐|💾|💽|🌏|🌉|🧪' "$file" || fail "缺少 emoji 输出或说明：$file"
    grep -Eq 'GREEN|C_GREEN|RED|C_RED|YELLOW|C_YELLOW|CYAN|C_CYAN|NC=' "$file" || fail "缺少色彩输出变量：$file"
}

check_executable() {
    local file="$1"
    [[ -x "$file" ]] || fail "缺少可执行权限：$file"
}

check_userscript_metadata() {
    local file="$1"
    grep -q '^// @name.*[✨🛫]' "$file" || fail "userscript 缺少 emoji 名称：$file"
    grep -q '^// @author.*BuBuXSY' "$file" || fail "userscript 缺少署名：$file"
    grep -q '^// @date' "$file" || fail "userscript 缺少日期：$file"

    if command -v node >/dev/null 2>&1; then
        node --check "$file" >/dev/null || fail "userscript JS 语法失败：$file"
    fi
}

check_userscript_smoke() {
    local test_file="$SCRIPT_DIR/tests/userscript_smoke_test.js"
    [[ -f "$test_file" ]] || return 0

    if ! command -v node >/dev/null 2>&1; then
        log_warn "未安装 node，跳过 userscript 冒烟测试"
        return 0
    fi

    if node "$test_file"; then
        log_ok "userscript 冒烟测试通过"
    else
        fail "userscript 冒烟测试失败"
    fi
}

check_readme_inventory() {
    local readme="$SCRIPT_DIR/README.md"
    local file name

    if [[ ! -f "$readme" ]]; then
        fail "缺少 README.md"
        return
    fi
    for file in "$@"; do
        name=${file##*/}
        grep -Fq "\`$name\`" "$readme" \
            || fail "README.md 未登记工具：$name"
    done
}

main() {
    validate_args "$@"
    banner

    if ! command -v shellcheck >/dev/null 2>&1; then
        log_warn "未安装 ShellCheck，仅执行语法与仓库规范检查"
    fi

    local file
    local label
    local shell_files=()
    local userscript_files=()
    local config_files=()
    shopt -s nullglob
    shell_files=("$SCRIPT_DIR"/*.sh)
    userscript_files=("$SCRIPT_DIR"/*.user.js)
    config_files=("$SCRIPT_DIR"/*.conf)
    shopt -u nullglob

    for file in "${shell_files[@]}"; do
        label="./${file##*/}"
        CHECKED=$((CHECKED + 1))
        log_info "🔍 检查 shell 脚本：$label"
        check_shell_syntax "$file"
        check_shell_static "$file"
        check_header "$file"
        check_style "$file"
        check_executable "$file"
    done

    for file in "${userscript_files[@]}"; do
        label="./${file##*/}"
        CHECKED=$((CHECKED + 1))
        log_info "🧩 检查 userscript：$label"
        check_userscript_metadata "$file"
    done

    check_userscript_smoke
    check_readme_inventory "${shell_files[@]}" "${userscript_files[@]}" "${config_files[@]}"

    if [[ "$CHECKED" -eq 0 ]]; then
        fail "仓库目录中没有可检查的 .sh 或 .user.js 文件：$SCRIPT_DIR"
    fi

    echo
    if [[ "$FAILED" -eq 0 ]]; then
        log_ok "🎉 自检完成：共检查 $CHECKED 个文件，未发现问题"
    else
        log_error "📌 自检完成：共检查 $CHECKED 个文件，发现 $FAILED 个问题"
        exit 1
    fi
}

main "$@"
