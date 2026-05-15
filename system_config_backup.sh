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
# 💾 系统关键配置备份脚本
# 功能：备份 Nginx、SSH、sysctl、cron、systemd、mosdns、fail2ban 等关键配置
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

BACKUP_DIR="${BACKUP_DIR:-/var/backups/shell_tools}"
EXTRA_PATHS="${EXTRA_PATHS:-}"
KEEP_DAYS="${KEEP_DAYS:-30}"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
HOSTNAME_SAFE="$(hostname 2>/dev/null | tr -c 'a-zA-Z0-9._-' '_' | sed 's/_$//' || echo server)"
WORK_DIR=""
ARCHIVE_PATH=""

usage() {
    cat <<EOF
💾 系统关键配置备份

用法:
  sudo ./system_config_backup.sh
  BACKUP_DIR=/root/backups ./system_config_backup.sh
  EXTRA_PATHS="/etc/x-ui /opt/app/config.yml" ./system_config_backup.sh

环境变量:
  BACKUP_DIR   📁 备份输出目录，默认 /var/backups/shell_tools
  EXTRA_PATHS  ➕ 额外备份路径，多个路径用空格分隔
  KEEP_DAYS    🧹 清理多少天以前的旧备份，默认 30；设为 0 表示不清理
EOF
}

banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║        💾 系统关键配置备份                   ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

log_info() { echo -e "${BLUE}ℹ️  $1${RESET}"; }
log_ok() { echo -e "${GREEN}✅ $1${RESET}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${RESET}"; }
log_error() { echo -e "${RED}❌ $1${RESET}"; }

cleanup() {
    [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
    return 0
}
trap cleanup EXIT

prepare() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    mkdir -p "$BACKUP_DIR" || {
        log_error "无法创建备份目录：$BACKUP_DIR"
        exit 1
    }

    WORK_DIR=$(mktemp -d /tmp/shell_tools_backup_XXXXXX)
    ARCHIVE_PATH="$BACKUP_DIR/${HOSTNAME_SAFE}_config_${TIMESTAMP}.tar.gz"
}

copy_path() {
    local src="$1"
    local dst
    dst="$WORK_DIR/files${src}"

    if [[ ! -e "$src" ]]; then
        return 0
    fi

    mkdir -p "$(dirname "$dst")"

    if cp -a "$src" "$dst" 2>/dev/null; then
        log_ok "已备份：$src"
    else
        log_warn "备份失败或权限不足：$src"
    fi
}

collect_configs() {
    local paths=(
        /etc/nginx
        /etc/ssh/sshd_config
        /etc/sysctl.conf
        /etc/sysctl.d
        /etc/security/limits.conf
        /etc/security/limits.d
        /etc/fail2ban
        /etc/cron.d
        /etc/crontab
        /etc/systemd/system
        /etc/mosdns
        /etc/x-ui
    )

    log_info "📦 开始收集关键配置..."

    local path
    for path in "${paths[@]}"; do
        copy_path "$path"
    done

    for path in $EXTRA_PATHS; do
        copy_path "$path"
    done
}

collect_metadata() {
    local meta_dir="$WORK_DIR/metadata"
    mkdir -p "$meta_dir"

    log_info "🧾 收集系统元数据..."

    {
        echo "Backup Time: $(date '+%F %T')"
        echo "Hostname: $(hostname 2>/dev/null || echo unknown)"
        echo "Kernel: $(uname -a)"
        echo "User: $(id)"
    } > "$meta_dir/backup_info.txt"

    if [[ -f /etc/os-release ]]; then
        cp /etc/os-release "$meta_dir/os-release" 2>/dev/null || true
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl list-unit-files --no-pager > "$meta_dir/systemd_unit_files.txt" 2>/dev/null || true
        systemctl list-units --type=service --state=running --no-pager > "$meta_dir/running_services.txt" 2>/dev/null || true
    fi

    if command -v nginx >/dev/null 2>&1; then
        nginx -V > "$meta_dir/nginx_version.txt" 2>&1 || true
        nginx -T > "$meta_dir/nginx_full_config.txt" 2>&1 || true
    fi

    if command -v crontab >/dev/null 2>&1; then
        crontab -l > "$meta_dir/root_crontab.txt" 2>/dev/null || true
    fi

    if command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W > "$meta_dir/packages_dpkg.txt" 2>/dev/null || true
    elif command -v rpm >/dev/null 2>&1; then
        rpm -qa > "$meta_dir/packages_rpm.txt" 2>/dev/null || true
    fi

    log_ok "系统元数据收集完成"
}

create_archive() {
    log_info "🗜️  正在打包备份..."

    tar -C "$WORK_DIR" -czf "$ARCHIVE_PATH" . || {
        log_error "备份打包失败"
        exit 1
    }

    sha256sum "$ARCHIVE_PATH" > "${ARCHIVE_PATH}.sha256"
    log_ok "备份完成：$ARCHIVE_PATH"
    log_ok "校验文件：${ARCHIVE_PATH}.sha256"
}

cleanup_old_backups() {
    if [[ ! "$KEEP_DAYS" =~ ^[0-9]+$ || "$KEEP_DAYS" -eq 0 ]]; then
        log_info "🧹 跳过旧备份清理"
        return 0
    fi

    log_info "🧹 清理 ${KEEP_DAYS} 天以前的旧备份..."
    find "$BACKUP_DIR" -type f \( -name "*_config_*.tar.gz" -o -name "*_config_*.tar.gz.sha256" \) -mtime +"$KEEP_DAYS" -print -delete 2>/dev/null || true
}

main() {
    prepare "$@"
    banner
    log_info "📁 备份目录：$BACKUP_DIR"
    collect_configs
    collect_metadata
    create_archive
    cleanup_old_backups
    log_ok "🎉 所有备份任务完成"
}

main "$@"
