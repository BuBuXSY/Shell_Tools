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
# Version: 2025-07-19
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
tmp_dir="/tmp/loyalsoldier"
tmp_path="$tmp_dir/Country.mmdb"
db_url="https://raw.githubusercontent.com/Loyalsoldier/geoip/release/Country-without-asn.mmdb"
target_path="/usr/share/geoip/Country.mmdb"
etag_file="/var/lib/geoip_country_wo_asn.etag"
last_modified_file="/var/lib/geoip_country_wo_asn.last"
version_file="/var/lib/geoip_country_wo_asn.version"
log_file="/var/log/geoip_update.log"

# 企业微信 Webhook 完整地址。推荐通过环境变量传入，避免把密钥写进脚本。
wechat_webhook_url="${WECHAT_WEBHOOK_URL:-${WEBHOOK_URL:-}}"

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

    local safe_message
    safe_message=$(echo "$message" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
    local json="{\"msgtype\":\"text\",\"text\":{\"content\":\"$safe_message\"}}"
    echo -e "\n📤 正在推送内容到企业微信..."
    if curl -fsS -X POST "$wechat_webhook_url" -H 'Content-Type: application/json' -d "$json" >/dev/null; then
        echo -e "${GREEN}✅ 企业微信推送成功。${RESET}"
    else
        echo -e "${YELLOW}⚠️  企业微信推送失败，继续执行主流程。${RESET}"
    fi
}

# ===== 准备目录结构 =====
mkdir -p "$tmp_dir" "$(dirname "$etag_file")" "$(dirname "$log_file")"
trap 'rm -rf "$tmp_dir"' EXIT

echo -e "${CYAN}🌏 正在检查 GeoIP 数据库更新...${RESET}"
echo "[`date '+%F %T'`] 开始检查更新..." >> "$log_file"

# ===== 构建条件请求头 =====
header_args=()
[[ -f "$etag_file" ]] && etag=$(<"$etag_file") && header_args+=("-H" "If-None-Match: $etag")
[[ -f "$last_modified_file" ]] && lm=$(<"$last_modified_file") && header_args+=("-H" "If-Modified-Since: $lm")

# ===== 请求响应头进行判断 =====
if ! response=$(curl -fsSIL "${header_args[@]}" "$db_url"); then
    echo -e "${RED}❌ 无法检查远程数据库更新，请检查网络。${RESET}"
    send_wechat_message "【🌏 GeoIP 数据库更新通知】\n❌ 无法检查远程数据库更新。\n📅 时间：$(date '+%F %T')"
    exit 1
fi

if echo "$response" | grep -Eq "HTTP/[0-9.]+ 304"; then
    echo -e "${GREEN}✅ 数据库无更新，无需下载。${RESET}"
    send_wechat_message "【🌏 GeoIP 数据库更新通知】\n✅ 数据库已是最新，无需更新。\n📅 时间：$(date '+%F %T')"
    exit 0
fi

# ===== 下载新数据库 =====
echo -e "${YELLOW}⬇️  发现更新，开始下载...${RESET}"
curl -fsSL --retry 3 --connect-timeout 8 --max-time 20 "$db_url" -o "$tmp_path"
if [[ ! -s "$tmp_path" ]]; then
    echo -e "${RED}❌ 下载失败或文件为空。${RESET}"
    send_wechat_message "【🌏 GeoIP 数据库更新通知】\n❌ 下载失败或文件为空，更新终止。\n📅 时间：$(date '+%F %T')"
    exit 1
fi
echo -e "${GREEN}✅ 下载成功：$tmp_path${RESET}"

# ===== 提取版本信息 =====
etag=$(curl -fsSI "$db_url" | grep -i '^ETag:' | cut -d' ' -f2- | tr -d '\r' || true)
last_modified=$(curl -fsSI "$db_url" | grep -i '^Last-Modified:' | cut -d' ' -f2- | tr -d '\r' || true)
sha256=$(sha256sum "$tmp_path" | awk '{print $1}')
echo "$etag" > "$etag_file"
echo "$last_modified" > "$last_modified_file"

# ===== 替换数据库并备份 =====
cp -f "$target_path" "${target_path}.bak_$(date +%F_%T)" 2>/dev/null || true
cp -f "$tmp_path" "$target_path"
echo -e "${GREEN}📁 数据库更新完成：$target_path${RESET}"

# ===== 写入版本文件 =====
{
    echo "Time:         $(date '+%F %T')"
    echo "ETag:         $etag"
    echo "Last-Modified:$last_modified"
    echo "SHA256:       $sha256"
} > "$version_file"
echo -e "${CYAN}📄 版本信息保存至：$version_file${RESET}"

# ===== 测试并重载 Nginx =====
echo -e "${BLUE}🧪 检查 Nginx 配置...${RESET}"
if nginx -t; then
    nginx -s reload
    echo -e "${GREEN}🚀 Nginx 重载成功！${RESET}"
    send_wechat_message "【🌏 GeoIP 数据库更新成功】\n✅ 数据库已更新并成功应用。\n📅 时间：$(date '+%F %T')\n🔐 SHA256: $sha256\n📦 ETag: $etag"
else
    echo -e "${RED}❌ Nginx 配置错误，未重载！${RESET}"
    send_wechat_message "【🌏 GeoIP 数据库更新成功⚠️】\n✅ 数据库已更新，但 Nginx 配置测试失败，未自动重载，请手动检查。\n📅 时间：$(date '+%F %T')"
    exit 1
fi

echo -e "${YELLOW}🎉 所有操作完成！GeoIP 数据库已是最新版本。${RESET}"
