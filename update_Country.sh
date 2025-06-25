#!/bin/bash

# ===== 脚本设置 =====
set +e

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

# ✅ 企业微信 Webhook 完整地址
wechat_webhook_url="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=加入你自己的KEY"

# ==== 检查 webhook 配置 ====
if [[ ! "$wechat_webhook_url" =~ ^https:// ]]; then
    echo -e "${RED}❌ Webhook URL 配置错误！${RESET}"
    exit 1
fi

# ===== 企业微信推送函数 =====
send_wechat_message() {
    local message="$1"
    local safe_message
    safe_message=$(echo "$message" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
    local json="{\"msgtype\":\"text\",\"text\":{\"content\":\"$safe_message\"}}"
    echo -e "\n📤 正在推送内容到企业微信..."
    curl -s -X POST "$wechat_webhook_url" -H 'Content-Type: application/json' -d "$json" >/dev/null
}

# ===== 准备目录结构 =====
mkdir -p "$tmp_dir" "$(dirname "$etag_file")" "$(dirname "$log_file")"

echo -e "${CYAN}🌏 正在检查 GeoIP 数据库更新...${RESET}"
echo "[`date '+%F %T'`] 开始检查更新..." >> "$log_file"

# ===== 构建条件请求头 =====
header_args=()
[[ -f "$etag_file" ]] && etag=$(<"$etag_file") && header_args+=("-H" "If-None-Match: $etag")
[[ -f "$last_modified_file" ]] && lm=$(<"$last_modified_file") && header_args+=("-H" "If-Modified-Since: $lm")

# ===== 请求响应头进行判断 =====
response=$(curl -fsSIL "${header_args[@]}" "$db_url")
if echo "$response" | grep -q "HTTP/1.1 304 Not Modified"; then
    echo -e "${GREEN}✅ 数据库无更新，无需下载。${RESET}"
    send_wechat_message "【🌏 GeoIP 数据库更新通知】\n✅ 数据库已是最新，无需更新。\n📅 时间：$(date '+%F %T')"
    rm -rf "$tmp_dir"
    exit 0
fi

# ===== 下载新数据库 =====
echo -e "${YELLOW}⬇️  发现更新，开始下载...${RESET}"
curl -fsSL --connect-timeout 8 --max-time 20 "$db_url" -o "$tmp_path"
if [[ ! -s "$tmp_path" ]]; then
    echo -e "${RED}❌ 下载失败或文件为空。${RESET}"
    send_wechat_message "【🌏 GeoIP 数据库更新通知】\n❌ 下载失败或文件为空，更新终止。\n📅 时间：$(date '+%F %T')"
    exit 1
fi
echo -e "${GREEN}✅ 下载成功：$tmp_path${RESET}"

# ===== 提取版本信息 =====
etag=$(curl -fsSI "$db_url" | grep -i '^ETag:' | cut -d' ' -f2- | tr -d '\r')
last_modified=$(curl -fsSI "$db_url" | grep -i '^Last-Modified:' | cut -d' ' -f2- | tr -d '\r')
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

# ===== 清理临时文件 =====
rm -rf "$tmp_dir"

# ===== 测试并重载 Nginx =====
echo -e "${BLUE}🧪 检查 Nginx 配置...${RESET}"
nginx -t
if [[ $? -eq 0 ]]; then
    nginx -s reload
    echo -e "${GREEN}🚀 Nginx 重载成功！${RESET}"
    send_wechat_message "【🌏 GeoIP 数据库更新成功】\n✅ 数据库已更新并成功应用。\n📅 时间：$(date '+%F %T')\n🔐 SHA256: $sha256\n📦 ETag: $etag"
else
    echo -e "${RED}❌ Nginx 配置错误，未重载！${RESET}"
    send_wechat_message "【🌏 GeoIP 数据库更新成功⚠️】\n✅ 数据库已更新，但 Nginx 配置测试失败，未自动重载，请手动检查。\n📅 时间：$(date '+%F %T')"
    exit 1
fi

echo -e "${YELLOW}🎉 所有操作完成！GeoIP 数据库已是最新版本。${RESET}"
