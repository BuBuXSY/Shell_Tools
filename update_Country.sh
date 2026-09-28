#!/bin/bash
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
# 🌏 GeoIP 国家数据库更新脚本
# 功能：更新 Country.mmdb，支持 ETag / Last-Modified 缓存、备份和 Nginx 重载
# By: BuBuXSY
# Version: 2026-07-11
# ====================================================

# ===== 脚本设置 =====
set -euo pipefail

# ===== 色彩输出 =====
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

# ===== 配置项 =====
tmp_dir=""
tmp_path=""
stage_path=""
backup_path=""
target_was_present=0
lock_file="/run/lock/geoip-country-update.lock"
db_url="https://raw.githubusercontent.com/Loyalsoldier/geoip/release/Country-without-asn.mmdb"
checksum_url="${db_url}.sha256sum"
target_path="/usr/share/geoip/Country.mmdb"
etag_file="/var/lib/geoip_country_wo_asn.etag"
last_modified_file="/var/lib/geoip_country_wo_asn.last"
version_file="/var/lib/geoip_country_wo_asn.version"
log_file="/var/log/geoip_update.log"

# 企业微信 Webhook 完整地址。推荐通过环境变量传入，避免把密钥写进脚本。
wechat_webhook_url="${WECHAT_WEBHOOK_URL:-${WEBHOOK_URL:-}}"

show_help() {
    cat <<EOF
GeoIP 国家数据库更新脚本

用法: $0 [--status|--help]

下载并校验 Country.mmdb，原子替换现有数据库，并在配置通过后重载 Nginx。
实际更新需要 root 权限；可通过 WECHAT_WEBHOOK_URL 或 WEBHOOK_URL 配置通知。

选项:
  -h, --help    显示帮助信息
  --status      只读显示本地数据库状态和记录的校验摘要
EOF
}

is_valid_mmdb() {
    local file="$1"
    local size=0
    [[ -f "$file" ]] || return 1
    size=$(wc -c < "$file" 2>/dev/null || echo 0)
    [[ "$size" -ge 102400 ]] || return 1
    tail -c 131072 "$file" 2>/dev/null | grep -aFq 'MaxMind.com'
}

recorded_sha256() {
    [[ -s "$version_file" ]] || return 1
    awk 'tolower($1) == "sha256:" {print tolower($2); exit}' "$version_file"
}

is_trusted_local_mmdb() {
    local expected actual
    is_valid_mmdb "$target_path" || return 1
    expected=$(recorded_sha256) || return 1
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
    actual=$(sha256sum "$target_path" | awk '{print tolower($1)}') || return 1
    [[ "$actual" == "$expected" ]]
}

rollback_database() {
    if [[ "$target_was_present" -eq 1 && -f "$backup_path" ]]; then
        local restore_stage
        restore_stage=$(mktemp "$(dirname "$target_path")/.Country.mmdb.rollback.XXXXXX") \
            || return 1
        if ! cp -a -- "$backup_path" "$restore_stage" \
            || ! mv -f "$restore_stage" "$target_path"; then
            rm -f -- "$restore_stage"
            return 1
        fi
    else
        rm -f -- "$target_path"
    fi
}

if [[ $# -gt 0 ]]; then
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        --status)
            [[ $# -eq 1 ]] || { show_help >&2; exit 2; }
            printf 'GeoIP 数据库: %s\n' "$target_path"
            if [[ -f "$target_path" ]]; then
                printf '文件大小: %s 字节\n' "$(wc -c < "$target_path")"
                printf '结构检查: '; if is_valid_mmdb "$target_path"; then printf '通过\n'; else printf '失败\n'; fi
                printf 'SHA-256 信任检查: '; if is_trusted_local_mmdb; then printf '通过\n'; else printf '未通过或缺少记录\n'; fi
            else
                printf '状态: 未安装\n'
            fi
            [[ ! -r "$version_file" ]] || sed -n '1,4p' "$version_file"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ 未知参数: $1${RESET}" >&2
            show_help >&2
            exit 2
            ;;
    esac
fi

if [[ "$(uname -s)" != Linux || -f /etc/openwrt_release ]]; then
    printf '❌ 当前 GeoIP 更新目标固定为 Linux Nginx 路径；macOS/OpenWrt 请使用对应包和实际数据库路径。\n' >&2
    exit 1
fi

# ===== 企业微信推送函数 =====
send_wechat_message() {
    local message="$1"
    if [[ -z "$wechat_webhook_url" || "$wechat_webhook_url" == *"加入你自己的KEY"* || "$wechat_webhook_url" == *"你的"* ]]; then
        echo -e "${YELLOW}⚠️  未配置企业微信 webhook，跳过推送。${RESET}"
        return 0
    fi

    if [[ ! "$wechat_webhook_url" =~ ^https:// ]]; then
        echo -e "${YELLOW}⚠️  Webhook URL 非 https，跳过推送。${RESET}"
        return 0
    fi

    local safe_message response
    safe_message=$(printf '%b' "$message" \
        | sed ':a;N;$!ba;s/\\/\\\\/g;s/"/\\"/g;s/\n/\\n/g')
    local json="{\"msgtype\":\"text\",\"text\":{\"content\":\"$safe_message\"}}"
    echo -e "\n📤 正在推送内容到企业微信..."
    if response=$(curl -fsS --connect-timeout 8 --max-time 15 -X POST \
        "$wechat_webhook_url" -H 'Content-Type: application/json' -d "$json") \
        && echo "$response" | grep -Eq '"errcode"[[:space:]]*:[[:space:]]*0'; then
        echo -e "${GREEN}✅ 企业微信推送成功。${RESET}"
    else
        echo -e "${YELLOW}⚠️  企业微信推送失败，继续执行主流程。${RESET}"
    fi
}

# ===== 前置检查与临时目录 =====
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ 请使用 root 权限运行此脚本。${RESET}" >&2
    exit 1
fi

missing=()
for cmd in curl sha256sum awk grep sed tail wc mktemp install flock cp mv; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}❌ 缺少必要命令：${missing[*]}${RESET}" >&2
    exit 1
fi

tmp_dir=$(mktemp -d /tmp/geoip-country.XXXXXX) \
    || { echo -e "${RED}❌ 无法创建临时目录。${RESET}" >&2; exit 1; }
tmp_path="$tmp_dir/Country.mmdb"
header_file="$tmp_dir/headers.txt"
checksum_path="$tmp_dir/Country.mmdb.sha256sum"
mkdir -p "$(dirname "$lock_file")"
exec 9>"$lock_file"
if ! flock -n 9; then
    echo -e "${YELLOW}⚠️  已有 GeoIP 更新任务正在运行，本次退出。${RESET}"
    rm -rf "$tmp_dir"
    exit 0
fi
trap '[[ -n "${stage_path:-}" ]] && rm -f "$stage_path"; [[ -n "${tmp_dir:-}" ]] && rm -rf "$tmp_dir"' EXIT

mkdir -p "$(dirname "$target_path")" "$(dirname "$etag_file")" "$(dirname "$log_file")"
if [[ -L "$target_path" ]]; then
    echo -e "${RED}❌ 目标数据库不能是符号链接：$target_path${RESET}"
    exit 1
fi

echo -e "${CYAN}🌏 正在检查 GeoIP 数据库更新...${RESET}"
echo "[$(date '+%F %T')] 开始检查更新..." >> "$log_file"

# ===== 构建条件请求头 =====
header_args=()
target_is_valid=0
target_is_structurally_valid=0
if is_valid_mmdb "$target_path"; then
    target_is_structurally_valid=1
fi
if is_trusted_local_mmdb; then
    target_is_valid=1
elif [[ "$target_is_structurally_valid" -eq 1 ]]; then
    echo -e "${YELLOW}⚠️  本地数据库缺少可信 SHA-256 或摘要不匹配，本次禁用条件请求并强制重下。${RESET}"
fi
if [[ "$target_is_valid" -eq 1 && -s "$etag_file" ]]; then
    etag=$(<"$etag_file")
    [[ -n "$etag" ]] && header_args+=("-H" "If-None-Match: $etag")
fi
if [[ "$target_is_valid" -eq 1 && -s "$last_modified_file" ]]; then
    lm=$(<"$last_modified_file")
    [[ -n "$lm" ]] && header_args+=("-H" "If-Modified-Since: $lm")
fi

# ===== 条件下载（一次请求同时获得状态、文件和响应头） =====
echo -e "${YELLOW}⬇️  正在请求最新数据库...${RESET}"
if ! http_code=$(curl -fsSL --retry 3 --retry-delay 2 \
    --connect-timeout 8 --max-time 60 \
    -D "$header_file" -o "$tmp_path" -w '%{http_code}' \
    "${header_args[@]}" "$db_url"); then
    echo -e "${RED}❌ 数据库下载失败，请检查网络。${RESET}"
    send_wechat_message "【🌏 GeoIP 数据库更新通知】\n❌ 数据库下载失败。\n📅 时间：$(date '+%F %T')"
    exit 1
fi

if [[ "$http_code" == "304" ]]; then
    if [[ "$target_is_valid" -ne 1 ]]; then
        echo -e "${RED}❌ 未发送可信条件请求却收到 HTTP 304，已拒绝保留本地数据库。${RESET}"
        exit 1
    fi
    echo -e "${GREEN}✅ 数据库无更新，无需下载。${RESET}"
    send_wechat_message "【🌏 GeoIP 数据库更新通知】\n✅ 数据库已是最新，无需更新。\n📅 时间：$(date '+%F %T')"
    exit 0
fi

if [[ "$http_code" != "200" || ! -s "$tmp_path" ]]; then
    echo -e "${RED}❌ 下载响应异常（HTTP $http_code）或文件为空。${RESET}"
    send_wechat_message "【🌏 GeoIP 数据库更新通知】\n❌ 下载响应异常（HTTP $http_code）。\n📅 时间：$(date '+%F %T')"
    exit 1
fi

if ! is_valid_mmdb "$tmp_path"; then
    echo -e "${RED}❌ 下载文件未通过 MMDB 完整性检查。${RESET}"
    send_wechat_message "【🌏 GeoIP 数据库更新通知】\n❌ 下载文件不是有效的 MaxMind MMDB，更新终止。\n📅 时间：$(date '+%F %T')"
    exit 1
fi

if ! curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 8 --max-time 30 \
    -o "$checksum_path" "$checksum_url"; then
    echo -e "${RED}❌ 上游 SHA-256 校验文件下载失败。${RESET}"
    exit 1
fi
expected_sha256=$(awk 'NF >= 1 {print tolower($1); exit}' "$checksum_path")
if ! [[ "$expected_sha256" =~ ^[0-9a-f]{64}$ ]]; then
    echo -e "${RED}❌ 上游 SHA-256 校验文件格式无效。${RESET}"
    exit 1
fi
sha256=$(sha256sum "$tmp_path" | awk '{print tolower($1)}')
if [[ "$sha256" != "$expected_sha256" ]]; then
    echo -e "${RED}❌ 数据库 SHA-256 不匹配，已拒绝更新。${RESET}"
    exit 1
fi
echo -e "${GREEN}✅ 下载并通过 SHA-256 校验：$tmp_path${RESET}"

# ===== 提取版本信息 =====
etag=$(awk 'tolower($0) ~ /^etag:/{sub(/^[^:]+:[[:space:]]*/, ""); sub(/\r$/, ""); value=$0} END{print value}' "$header_file")
last_modified=$(awk 'tolower($0) ~ /^last-modified:/{sub(/^[^:]+:[[:space:]]*/, ""); sub(/\r$/, ""); value=$0} END{print value}' "$header_file")

if [[ "$target_is_structurally_valid" -eq 1 ]]; then
    current_sha256=$(sha256sum "$target_path" | awk '{print $1}')
    if [[ "$current_sha256" == "$sha256" ]]; then
        printf '%s\n' "$etag" > "$etag_file"
        printf '%s\n' "$last_modified" > "$last_modified_file"
        {
            echo "Time:         $(date '+%F %T')"
            echo "ETag:         $etag"
            echo "Last-Modified:$last_modified"
            echo "SHA256:       $sha256"
        } > "$tmp_dir/version"
        install -m 0644 "$tmp_dir/version" "$version_file" \
            || echo -e "${YELLOW}⚠️  版本信息文件写入失败，下次将重新完整校验。${RESET}"
        echo -e "${GREEN}✅ 文件内容未变化，仅刷新缓存标识。${RESET}"
        exit 0
    fi
fi

# ===== 替换数据库并备份 =====
if [[ -f "$target_path" ]]; then
    target_was_present=1
    backup_path=$(mktemp "$(dirname "$target_path")/Country.mmdb.bak_$(date +%Y%m%d_%H%M%S).XXXXXX") \
        || { echo -e "${RED}❌ 无法创建旧数据库备份文件。${RESET}"; exit 1; }
    if ! cp -a -- "$target_path" "$backup_path"; then
        rm -f -- "$backup_path"
        backup_path=""
        echo -e "${RED}❌ 旧数据库备份失败，已停止更新。${RESET}"
        exit 1
    fi
    echo -e "${CYAN}💾 旧数据库已备份：$backup_path${RESET}"
fi

stage_path=$(mktemp "$(dirname "$target_path")/.Country.mmdb.XXXXXX") \
    || { echo -e "${RED}❌ 无法在目标目录创建临时文件。${RESET}"; exit 1; }
install -m 0644 "$tmp_path" "$stage_path"
mv -f "$stage_path" "$target_path"
stage_path=""
echo -e "${GREEN}📁 数据库更新完成：$target_path${RESET}"

# ===== 测试并重载 Nginx =====
echo -e "${BLUE}🧪 检查 Nginx 配置...${RESET}"
if ! command -v nginx >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  未检测到 Nginx，数据库已更新但未执行重载。${RESET}"
    send_wechat_message "【🌏 GeoIP 数据库更新成功】\n✅ 数据库已更新。\n⚠️ 未检测到 Nginx，未执行重载。\n📅 时间：$(date '+%F %T')\n🔐 SHA256: $sha256"
elif nginx -t; then
    if nginx -s reload; then
        echo -e "${GREEN}🚀 Nginx 重载成功！${RESET}"
        send_wechat_message "【🌏 GeoIP 数据库更新成功】\n✅ 数据库已更新并成功应用。\n📅 时间：$(date '+%F %T')\n🔐 SHA256: $sha256\n📦 ETag: $etag"
    else
        echo -e "${RED}❌ Nginx 重载失败，正在恢复旧数据库。${RESET}"
        rollback_database || echo -e "${RED}❌ 旧数据库自动恢复失败：$backup_path${RESET}"
        nginx -t >/dev/null 2>&1 && nginx -s reload >/dev/null 2>&1 || true
        send_wechat_message "【🌏 GeoIP 数据库更新失败】\n❌ Nginx 重载失败，已尝试恢复旧数据库。\n📅 时间：$(date '+%F %T')"
        exit 1
    fi
else
    echo -e "${RED}❌ 新数据库导致 Nginx 配置测试失败，正在恢复旧数据库。${RESET}"
    rollback_database || echo -e "${RED}❌ 旧数据库自动恢复失败：$backup_path${RESET}"
    nginx -t >/dev/null 2>&1 && nginx -s reload >/dev/null 2>&1 || true
    send_wechat_message "【🌏 GeoIP 数据库更新失败】\n❌ Nginx 配置测试失败，已尝试恢复旧数据库。\n📅 时间：$(date '+%F %T')"
    exit 1
fi

# 数据库已成功应用后再保存条件请求标识，避免失败版本被 304 长期缓存。
printf '%s\n' "$etag" > "$etag_file" \
    || echo -e "${YELLOW}⚠️  ETag 缓存写入失败，下次将重新下载。${RESET}"
printf '%s\n' "$last_modified" > "$last_modified_file" \
    || echo -e "${YELLOW}⚠️  Last-Modified 缓存写入失败。${RESET}"

{
    echo "Time:         $(date '+%F %T')"
    echo "ETag:         $etag"
    echo "Last-Modified:$last_modified"
    echo "SHA256:       $sha256"
} > "$tmp_dir/version"
install -m 0644 "$tmp_dir/version" "$version_file" \
    || echo -e "${YELLOW}⚠️  版本信息文件写入失败，但数据库已更新。${RESET}"
echo -e "${CYAN}📄 版本信息保存至：$version_file${RESET}"

echo -e "${YELLOW}🎉 所有操作完成！GeoIP 数据库已是最新版本。${RESET}"
