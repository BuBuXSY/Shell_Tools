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
# Version: 2026-05-16
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
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    if [[ ! "$TOP_N" =~ ^[0-9]+$ || "$TOP_N" -lt 1 ]]; then
        error "TOP_N 必须是大于 0 的数字"
        exit 1
    fi

    if [[ ! "$MAX_DEPTH" =~ ^[0-9]+$ || "$MAX_DEPTH" -lt 1 ]]; then
        error "MAX_DEPTH 必须是大于 0 的数字"
        exit 1
    fi
}

show_filesystems() {
    section "文件系统使用率"
    df -hT | awk 'NR==1 {print "   📌 " $0; next} {print "   💾 " $0}'
}

show_inode_usage() {
    section "Inode 使用率"
    df -ih | awk 'NR==1 {print "   📌 " $0; next} {print "   🧩 " $0}'
}

show_top_dirs() {
    section "大目录排行"
    local target
    for target in $TARGETS; do
        [[ -d "$target" ]] || continue
        info "📁 分析目录：$target"
        du -xhd "$MAX_DEPTH" "$target" 2>/dev/null \
            | sort -hr \
            | head -n "$TOP_N" \
            | sed 's/^/   📦 /' || true
    done
}

show_large_files() {
    section "大文件排行"
    local target
    for target in $TARGETS; do
        [[ -d "$target" ]] || continue
        info "🔍 查找目录：$target"
        find "$target" -xdev -type f -size +100M -printf '%s\t%p\n' 2>/dev/null \
            | sort -nr \
            | head -n "$TOP_N" \
            | awk '{size=$1; $1=""; sub(/^\t? ?/, ""); printf "   🧱 %.2f GB  %s\n", size/1024/1024/1024, $0}' || true
    done
}

show_log_usage() {
    section "日志占用"
    if [[ -d /var/log ]]; then
        du -sh /var/log 2>/dev/null | awk '{print "   🧾 /var/log 总占用：" $1}'
        find /var/log -type f -size +50M -printf '%s\t%p\n' 2>/dev/null \
            | sort -nr \
            | head -n "$TOP_N" \
            | awk '{size=$1; $1=""; sub(/^\t? ?/, ""); printf "   🔥 %.2f MB  %s\n", size/1024/1024, $0}' || true
    else
        warn "未找到 /var/log"
    fi

    if has_cmd journalctl; then
        journalctl --disk-usage 2>/dev/null | sed 's/^/   📚 /' || true
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
    echo "   🧹 journal 日志过大时：journalctl --vacuum-time=7d"
    echo "   🧹 apt 缓存可清理：sudo apt-get clean"
    echo "   🧹 Docker 需谨慎清理：docker system prune"
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
