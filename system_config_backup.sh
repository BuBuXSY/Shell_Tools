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
# Version: 2026-07-11
# ====================================================

set -euo pipefail
umask 077

GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

BACKUP_DIR="${BACKUP_DIR:-/var/backups/shell_tools}"
EXTRA_PATHS="${EXTRA_PATHS:-}"
KEEP_DAYS="${KEEP_DAYS:-30}"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
HOSTNAME_SAFE="$(hostname 2>/dev/null | tr -c 'a-zA-Z0-9._-' '_' | sed 's/_$//' || echo server)"
WORK_DIR=""
ARCHIVE_PATH=""
TEMP_ARCHIVE=""
BACKED_UP=0
COPY_FAILURES=0
CLEANUP_FAILURES=0
PLAN_ONLY=0

usage() {
    cat <<EOF
💾 系统关键配置备份

用法:
  sudo ./system_config_backup.sh
  BACKUP_DIR=/root/backups ./system_config_backup.sh
  EXTRA_PATHS="/etc/x-ui /opt/app/config.yml" ./system_config_backup.sh
  ./system_config_backup.sh --plan

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
    [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf -- "$WORK_DIR"
    [[ -n "$TEMP_ARCHIVE" && -f "$TEMP_ARCHIVE" ]] && rm -f -- "$TEMP_ARCHIVE"
    return 0
}
trap cleanup EXIT

prepare() {
    case "$#" in
        0) ;;
        1)
            if [[ "$1" == "-h" || "$1" == "--help" ]]; then
                usage
                exit 0
            elif [[ "$1" == "--plan" ]]; then
                PLAN_ONLY=1
            else
                log_error "未知参数：$1"
                usage >&2
                exit 2
            fi
            ;;
        *)
            log_error "参数过多，本脚本通过环境变量接收配置"
            usage >&2
            exit 2
            ;;
    esac

    if [[ -z "$BACKUP_DIR" || "$BACKUP_DIR" == "/" ]]; then
        log_error "BACKUP_DIR 不能为空或根目录 /"
        exit 2
    fi
    if [[ ! "$KEEP_DAYS" =~ ^[0-9]+$ ]]; then
        log_error "KEEP_DAYS 必须是大于等于 0 的整数"
        exit 2
    fi

    [[ "$PLAN_ONLY" -eq 0 ]] || return 0

    local cmd
    for cmd in mkdir mktemp cp tar find dirname date hostname readlink ln; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "缺少必要命令：$cmd"
            exit 1
        fi
    done

    mkdir -p "$BACKUP_DIR" || {
        log_error "无法创建备份目录：$BACKUP_DIR"
        exit 1
    }

    BACKUP_DIR=$(readlink -f -- "$BACKUP_DIR") || {
        log_error "无法解析备份目录：$BACKUP_DIR"
        exit 1
    }
    if [[ "$BACKUP_DIR" == "/" ]]; then
        log_error "BACKUP_DIR 解析后指向根目录 /，已拒绝执行"
        exit 2
    fi
    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/shell_tools_backup.XXXXXX") || {
        log_error "无法创建临时工作目录"
        exit 1
    }
    [[ -n "$HOSTNAME_SAFE" ]] || HOSTNAME_SAFE="server"
    ARCHIVE_PATH="$BACKUP_DIR/${HOSTNAME_SAFE}_config_${TIMESTAMP}_$$.tar.gz"
}

copy_path() {
    local src="$1"
    local dst
    local copy_ok=0
    local resolved_src=""

    src=${src%/}
    if [[ -z "$src" || "$src" != /* || "$src" == "/" || "$src" == *"/../"* || "$src" == */.. ]]; then
        log_warn "拒绝不安全的备份路径：${src:-<空>}"
        COPY_FAILURES=$((COPY_FAILURES + 1))
        return 0
    fi

    if [[ -e "$src" || -L "$src" ]]; then
        resolved_src=$(readlink -f -- "$src" 2>/dev/null || true)
        if [[ -z "$resolved_src" || "$resolved_src" == "/" ]]; then
            log_warn "拒绝解析后指向根目录或无法解析的路径：$src"
            COPY_FAILURES=$((COPY_FAILURES + 1))
            return 0
        fi
    else
        return 0
    fi

    if [[ "$WORK_DIR" == "$resolved_src" || "$WORK_DIR" == "$resolved_src/"* ]]; then
        log_warn "拒绝包含临时工作目录的路径：$src"
        COPY_FAILURES=$((COPY_FAILURES + 1))
        return 0
    fi

    if [[ "$BACKUP_DIR" == "$resolved_src" || "$BACKUP_DIR" == "$resolved_src/"* ]]; then
        log_warn "拒绝包含备份输出目录的路径：$src"
        COPY_FAILURES=$((COPY_FAILURES + 1))
        return 0
    fi

    dst="$WORK_DIR/files/${src#/}"

    if [[ -d "$src" && ! -L "$src" ]]; then
        if mkdir -p "$dst" && cp -a "$src"/. "$dst"/ 2>/dev/null; then
            copy_ok=1
        fi
    else
        if mkdir -p "$(dirname "$dst")" && cp -a "$src" "$dst" 2>/dev/null; then
            copy_ok=1
        fi
    fi

    if [[ "$copy_ok" -eq 1 ]]; then
        BACKED_UP=$((BACKED_UP + 1))
        log_ok "已备份：$src"
    else
        COPY_FAILURES=$((COPY_FAILURES + 1))
        log_warn "备份失败或权限不足：$src"
    fi
}

collect_configs() {
    local paths=(
        /etc/nginx
        /etc/ssh/sshd_config
        /etc/ssh/sshd_config.d
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

    local extra_paths=()
    read -r -a extra_paths <<< "$EXTRA_PATHS"
    for path in "${extra_paths[@]}"; do
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
        echo "Config Paths Backed Up: $BACKED_UP"
        echo "Config Copy Failures: $COPY_FAILURES"
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

    TEMP_ARCHIVE=$(mktemp "$BACKUP_DIR/.shell_tools_backup.XXXXXX.tar.gz") || {
        log_error "无法在备份目录创建临时归档"
        exit 1
    }

    tar -C "$WORK_DIR" -czf "$TEMP_ARCHIVE" . || {
        log_error "备份打包失败"
        exit 1
    }

    if ! ln -- "$TEMP_ARCHIVE" "$ARCHIVE_PATH"; then
        log_error "最终备份文件已存在或无法原子写入：$ARCHIVE_PATH"
        exit 1
    fi
    rm -f -- "$TEMP_ARCHIVE"
    TEMP_ARCHIVE=""

    if command -v sha256sum >/dev/null 2>&1; then
        if ! (cd "$BACKUP_DIR" && sha256sum "${ARCHIVE_PATH##*/}") > "${ARCHIVE_PATH}.sha256"; then
            rm -f -- "${ARCHIVE_PATH}.sha256"
            log_warn "SHA-256 校验文件生成失败"
            COPY_FAILURES=$((COPY_FAILURES + 1))
        fi
    elif command -v shasum >/dev/null 2>&1; then
        if ! (cd "$BACKUP_DIR" && shasum -a 256 "${ARCHIVE_PATH##*/}") > "${ARCHIVE_PATH}.sha256"; then
            rm -f -- "${ARCHIVE_PATH}.sha256"
            log_warn "SHA-256 校验文件生成失败"
            COPY_FAILURES=$((COPY_FAILURES + 1))
        fi
    else
        log_warn "缺少 sha256sum/shasum，未生成校验文件"
        COPY_FAILURES=$((COPY_FAILURES + 1))
    fi
    log_ok "备份完成：$ARCHIVE_PATH"
    [[ -f "${ARCHIVE_PATH}.sha256" ]] && log_ok "校验文件：${ARCHIVE_PATH}.sha256"
}

cleanup_old_backups() {
    if [[ "$KEEP_DAYS" -eq 0 ]]; then
        log_info "🧹 跳过旧备份清理"
        return 0
    fi

    log_info "🧹 清理 ${KEEP_DAYS} 天以前的旧备份..."
    if ! find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type f \
        \( -name "${HOSTNAME_SAFE}_config_*.tar.gz" -o -name "${HOSTNAME_SAFE}_config_*.tar.gz.sha256" \) \
        -mtime +"$KEEP_DAYS" -print -delete 2>/dev/null; then
        CLEANUP_FAILURES=$((CLEANUP_FAILURES + 1))
        log_warn "旧备份清理不完整，请检查目录权限"
    fi
}

main() {
    prepare "$@"
    if [[ "$PLAN_ONLY" -eq 1 ]]; then
        printf '配置备份预览\n输出目录: %s\n保留天数: %s\n' "$BACKUP_DIR" "$KEEP_DAYS"
        printf '默认路径: /etc/nginx /etc/ssh /etc/sysctl.d /etc/security /etc/fail2ban /etc/cron.d /etc/systemd/system /etc/mosdns /etc/x-ui\n'
        printf '额外路径: %s\n' "${EXTRA_PATHS:-无}"
        printf '正式运行将创建压缩包并清理超过保留天数的本机旧备份。\n'
        return 0
    fi
    if [[ "$(uname -s)" == Darwin ]]; then
        log_error "默认备份清单使用 Linux 配置路径；macOS 请使用 Time Machine 或按需使用 tar。"
        return 1
    fi
    banner
    log_info "📁 备份目录：$BACKUP_DIR"
    collect_configs
    collect_metadata
    create_archive
    cleanup_old_backups
    if [[ "$COPY_FAILURES" -gt 0 || "$CLEANUP_FAILURES" -gt 0 ]]; then
        log_warn "备份已生成，但存在 $COPY_FAILURES 个收集/校验失败和 $CLEANUP_FAILURES 个清理失败"
        return 2
    fi
    log_ok "🎉 所有备份任务完成"
}

main "$@"
