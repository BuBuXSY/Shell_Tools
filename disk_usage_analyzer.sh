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
# 💽 磁盘空间分析脚本
# 功能：只读分析磁盘使用率、大目录、大文件、日志、Docker 和 systemd journal 占用
# By: BuBuXSY
# Version: 2026-07-11
# ====================================================

set -euo pipefail

GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

TARGETS="${TARGETS:-/ /var /home /opt /usr/local}"
TOP_N="${TOP_N:-15}"
MAX_DEPTH="${MAX_DEPTH:-2}"
TARGET_PATHS=()

usage() {
    cat <<EOF
💽 磁盘空间分析

用法:
  ./disk_usage_analyzer.sh
  TARGETS="/ /var/www /opt" TOP_N=20 ./disk_usage_analyzer.sh

环境变量:
  TARGETS    📁 要分析的目录，多个目录用空格分隔
  TOP_N      🔢 Top 列表数量，默认 15
  MAX_DEPTH  🧱 目录统计深度，默认 2
EOF
}

banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║        💽 磁盘空间分析                       ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

section() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}🔎 $1${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

info() { echo -e "${BLUE}ℹ️  $1${RESET}"; }
ok() { echo -e "${GREEN}✅ $1${RESET}"; }
warn() { echo -e "${YELLOW}⚠️  $1${RESET}"; }
error() { echo -e "${RED}❌ $1${RESET}"; }

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
            error "未知参数：$1"
            usage >&2
            exit 2
            ;;
        *)
            error "参数过多，本脚本通过环境变量接收配置"
            usage >&2
            exit 2
            ;;
    esac

    if [[ ! "$TOP_N" =~ ^[0-9]+$ || "$TOP_N" -lt 1 ]]; then
        error "TOP_N 必须是大于 0 的数字"
        exit 2
    fi

    if [[ ! "$MAX_DEPTH" =~ ^[0-9]+$ || "$MAX_DEPTH" -lt 1 ]]; then
        error "MAX_DEPTH 必须是大于 0 的数字"
        exit 2
    fi

    read -r -a TARGET_PATHS <<< "$TARGETS"
    if [[ "${#TARGET_PATHS[@]}" -eq 0 ]]; then
        error "TARGETS 不能为空"
        exit 2
    fi

    local cmd
    for cmd in df du find sort head awk sed wc mktemp; do
        if ! has_cmd "$cmd"; then
            error "缺少必要命令：$cmd"
            exit 1
        fi
    done

    local target
    local valid_targets=0
    for target in "${TARGET_PATHS[@]}"; do
        if [[ ! -d "$target" ]]; then
            warn "跳过不存在的目录：$target"
        elif [[ ! -r "$target" || ! -x "$target" ]]; then
            warn "跳过不可读取的目录：$target"
        else
            valid_targets=$((valid_targets + 1))
        fi
    done

    if [[ "$valid_targets" -eq 0 ]]; then
        error "TARGETS 中没有可读取的目录"
        exit 1
    fi
}

show_filesystems() {
    section "文件系统使用率"
    if df -hT >/dev/null 2>&1; then
        df -hT | awk 'NR==1 {print "   📌 " $0; next} {print "   💾 " $0}'
    elif df -h >/dev/null 2>&1; then
        df -h | awk 'NR==1 {print "   📌 " $0; next} {print "   💾 " $0}'
    else
        warn "无法读取文件系统使用率"
    fi
}

show_inode_usage() {
    section "Inode 使用率"
    if df -ih >/dev/null 2>&1; then
        df -ih | awk 'NR==1 {print "   📌 " $0; next} {print "   🧩 " $0}'
    elif df -hi >/dev/null 2>&1; then
        df -hi | awk 'NR==1 {print "   📌 " $0; next} {print "   🧩 " $0}'
    else
        warn "当前 df 不支持 Inode 统计或读取失败"
    fi
}

show_top_dirs() {
    section "大目录排行"
    local target
    local output
    local raw_output
    local scan_status
    for target in "${TARGET_PATHS[@]}"; do
        [[ -d "$target" && -r "$target" && -x "$target" ]] || continue
        info "📁 分析目录：$target"
        raw_output=$(mktemp "${TMPDIR:-/tmp}/disk-usage-du.XXXXXX") || { warn "无法创建临时文件"; continue; }
        scan_status=0
        du -xk -d "$MAX_DEPTH" "$target" > "$raw_output" 2>/dev/null || scan_status=$?
        output=$(sort -nr "$raw_output" \
            | head -n "$TOP_N" \
            | awk '{size=$1; $1=""; sub(/^ /, ""); unit="KB"; if (size >= 1099511627776) {size/=1099511627776; unit="PB"} else if (size >= 1073741824) {size/=1073741824; unit="TB"} else if (size >= 1048576) {size/=1048576; unit="GB"} else if (size >= 1024) {size/=1024; unit="MB"} printf "   📦 %8.2f %-2s  %s\n", size, unit, $0}' || true)
        rm -f -- "$raw_output"
        if [[ -n "$output" ]]; then
            printf '%s\n' "$output"
        else
            warn "未能读取目录占用：$target"
        fi
        [[ "$scan_status" -eq 0 ]] || warn "目录占用扫描不完整，部分无权限或已变化的路径未计入：$target"
    done
}

show_large_files() {
    section "大文件排行"
    local target
    local output
    local raw_output
    local scan_status
    for target in "${TARGET_PATHS[@]}"; do
        [[ -d "$target" && -r "$target" && -x "$target" ]] || continue
        info "🔍 查找目录：$target"
        raw_output=$(mktemp "${TMPDIR:-/tmp}/disk-usage-find.XXXXXX") || { warn "无法创建临时文件"; continue; }
        scan_status=0
        if find "$target" -prune -printf '' >/dev/null 2>&1; then
            find "$target" -xdev -type f -size +100M -printf '%s\t%p\n' > "$raw_output" 2>/dev/null \
                || scan_status=$?
            output=$(sort -nr "$raw_output" \
                | head -n "$TOP_N" \
                | awk '{size=$1; $1=""; sub(/^\t? ?/, ""); printf "   🧱 %.2f GB  %s\n", size/1024/1024/1024, $0}' || true)
        else
            find "$target" -xdev -type f -size +100M -exec sh -c '
                for file do
                    size=$(wc -c < "$file" 2>/dev/null) || continue
                    printf "%s\t%s\n" "$size" "$file"
                done
            ' sh {} + > "$raw_output" 2>/dev/null || scan_status=$?
            output=$(sort -nr "$raw_output" \
                | head -n "$TOP_N" \
                | awk '{size=$1; $1=""; sub(/^\t? ?/, ""); printf "   🧱 %.2f GB  %s\n", size/1024/1024/1024, $0}' || true)
        fi
        rm -f -- "$raw_output"

        if [[ -n "$output" ]]; then
            printf '%s\n' "$output"
        else
            info "未发现大于 100 MB 的普通文件"
        fi
        [[ "$scan_status" -eq 0 ]] || warn "大文件扫描不完整，部分无权限或已变化的路径未计入：$target"
    done
}

show_log_usage() {
    section "日志占用"
    if [[ -d /var/log ]]; then
        local log_size
        log_size=$(du -sh /var/log 2>/dev/null | awk 'NR == 1 {print $1}' || true)
        if [[ -n "$log_size" ]]; then
            echo "   🧾 /var/log 总占用：$log_size"
        else
            warn "当前用户无法统计 /var/log 总占用"
        fi
        find /var/log -type f -size +50M -printf '%s\t%p\n' 2>/dev/null \
            | sort -nr \
            | head -n "$TOP_N" \
            | awk '{size=$1; $1=""; sub(/^\t? ?/, ""); printf "   🔥 %.2f MB  %s\n", size/1024/1024, $0}' || true
    else
        warn "未找到 /var/log"
    fi

    if has_cmd journalctl; then
        local journal_usage
        if journal_usage=$(journalctl --disk-usage 2>/dev/null); then
            printf '%s\n' "$journal_usage" | sed 's/^/   📚 /'
        else
            warn "无法读取 systemd journal 占用"
        fi
    fi
}

show_docker_usage() {
    section "Docker 占用"
    if has_cmd docker; then
        docker system df 2>/dev/null | sed 's/^/   🐳 /' || warn "Docker 命令存在但当前用户不可读取 Docker 信息"
    else
        info "未安装 Docker，跳过"
    fi
}

show_suggestions() {
    section "清理建议"
    has_cmd journalctl && echo "   🧹 journal 日志过大时：journalctl --vacuum-time=7d"
    has_cmd apt-get && echo "   🧹 apt 缓存可清理：sudo apt-get clean"
    has_cmd docker && echo "   🧹 Docker 需谨慎清理：docker system prune"
    echo "   🧹 大文件删除前先确认用途，尤其是数据库、证书、日志和备份文件"
    ok "本脚本只读分析，不会删除任何文件"
}

main() {
    validate "$@"
    banner
    info "📁 分析目标：$TARGETS"
    info "🔢 Top 数量：$TOP_N"
    show_filesystems
    show_inode_usage
    show_top_dirs
    show_large_files
    show_log_usage
    show_docker_usage
    show_suggestions
}

main "$@"
