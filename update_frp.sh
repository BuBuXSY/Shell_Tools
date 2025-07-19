#!/bin/bash
# FRP 安装和升级脚本
# 支持 frps 和 frpc 的安装、升级和卸载
# By: BuBuXSY
# Version: 2025-07-17
# License: MIT


set -euo pipefail  # 严格模式：遇到错误立即退出

# ==== 配置常量 ====
readonly INSTALL_DIR="/usr/bin"
readonly TMP_DIR="/tmp/frp_installer"
readonly GITHUB_API="https://api.github.com/repos/fatedier/frp/releases/latest"
readonly GITHUB_RELEASES="https://github.com/fatedier/frp/releases"

# ==== 颜色和格式 ====
readonly RED="\e[31m"
readonly GREEN="\e[32m"
readonly YELLOW="\e[33m"
readonly BLUE="\e[34m"
readonly MAGENTA="\e[35m"
readonly CYAN="\e[36m"
readonly BOLD="\e[1m"
readonly RESET="\e[0m"
readonly INFO="${CYAN}ℹ️ ${RESET}"
readonly SUCCESS="${GREEN}✅ ${RESET}"
readonly WARN="${YELLOW}⚠️ ${RESET}"
readonly ERROR="${RED}❌ ${RESET}"
readonly PROMPT="${MAGENTA}👉 ${RESET}"

# ==== 全局变量 ====
LATEST_VERSION=""
ARCHITECTURE=""
PLATFORM=""

# ==== 工具函数 ====

# 日志函数 - 修改为输出到 stderr
log_info() { printf "${INFO}%s\n" "$1" >&2; }
log_success() { printf "${SUCCESS}%s\n" "$1" >&2; }
log_warn() { printf "${WARN}%s\n" "$1" >&2; }
log_error() { printf "${ERROR}%s\n" "$1" >&2; }

# 清理函数
cleanup() {
    log_error "任务已取消或发生错误"
    [[ -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
    exit 1
}

# 设置信号处理（移除 ERR trap，避免正常退出时触发）
trap cleanup INT TERM

# 强制刷新输出缓冲区
flush_output() {
    exec 1>&1  # 刷新 stdout
    exec 2>&2  # 刷新 stderr
    sync
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查必要的依赖
check_dependencies() {
    local missing_deps=()
    
    for cmd in curl wget tar; do
        if ! command_exists "$cmd"; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "缺少必要的依赖: ${missing_deps[*]}"
        log_info "请先安装这些工具再运行此脚本"
        exit 1
    fi
}

# 检查 sudo 权限
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log_info "此脚本需要 sudo 权限来安装文件"
        sudo -v || {
            log_error "无法获取 sudo 权限"
            exit 1
        }
    fi
}

# 获取系统架构
detect_architecture() {
    ARCHITECTURE=$(uname -m)
    case "$ARCHITECTURE" in
        x86_64)
            PLATFORM="amd64"
            ;;
        aarch64|arm64)
            PLATFORM="arm64"
            ;;
        armv7l)
            PLATFORM="arm"
            ;;
        *)
            log_error "不支持的系统架构: $ARCHITECTURE"
            exit 1
            ;;
    esac
    log_info "检测到系统架构: $ARCHITECTURE ($PLATFORM)"
}

# 获取最新版本号（使用 GitHub API）
get_latest_version() {
    log_info "正在获取最新版本信息..."
    
    # 尝试使用 GitHub API
    if LATEST_VERSION=$(curl -sL --connect-timeout 10 --max-time 30 "$GITHUB_API" | grep -o '"tag_name": "v[^"]*"' | head -n1 | cut -d'"' -f4 | sed 's/^v//'); then
        if [[ -n "$LATEST_VERSION" ]]; then
            log_success "获取到最新版本: $LATEST_VERSION"
            return 0
        fi
    fi
    
    # 备用方案：解析 releases 页面
    log_warn "API 获取失败，尝试备用方案..."
    if LATEST_VERSION=$(curl -sL --connect-timeout 10 --max-time 30 "$GITHUB_RELEASES/latest" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | sed 's/^v//'); then
        if [[ -n "$LATEST_VERSION" ]]; then
            log_success "获取到最新版本: $LATEST_VERSION"
            return 0
        fi
    fi
    
    log_error "无法获取最新版本信息，请检查网络连接"
    exit 1
}

# 版本比较函数
version_gt() {
    # $1 > $2 返回 0 (true)，否则返回 1 (false)
    local version1="$1"
    local version2="$2"
    
    # 如果版本相同，返回 false
    [[ "$version1" == "$version2" ]] && return 1
    
    # 使用 sort -V 进行版本比较
    local newer_version=$(printf '%s\n%s\n' "$version1" "$version2" | sort -V | tail -n1)
    [[ "$newer_version" == "$version1" ]]
}

# 获取已安装的 FRP 信息
get_installed_info() {
    local installed_version=""
    local installed_type=""
    local frp_path=""
    
    # 首先检查 PATH 中是否有 frps 或 frpc
    if command_exists frps; then
        frp_path=$(command -v frps)
        installed_version=$(frps --version 2>/dev/null | awk '{print $3}' || echo "")
        installed_type="frps"
    elif command_exists frpc; then
        frp_path=$(command -v frpc)
        installed_version=$(frpc --version 2>/dev/null | awk '{print $3}' || echo "")
        installed_type="frpc"
    else
        # 检查指定安装目录
        local frps_path="$INSTALL_DIR/frps"
        local frpc_path="$INSTALL_DIR/frpc"
        
        if [[ -x "$frps_path" ]]; then
            frp_path="$frps_path"
            installed_version=$("$frps_path" --version 2>/dev/null | awk '{print $3}' || echo "")
            installed_type="frps"
        elif [[ -x "$frpc_path" ]]; then
            frp_path="$frpc_path"
            installed_version=$("$frpc_path" --version 2>/dev/null | awk '{print $3}' || echo "")
            installed_type="frpc"
        fi
    fi
    
    # 如果版本获取失败，尝试其他解析方式
    if [[ -n "$frp_path" && -z "$installed_version" ]]; then
        # 尝试不同的版本输出格式
        local version_output
        version_output=$("$frp_path" --version 2>/dev/null || echo "")
        
        # 尝试提取版本号的不同方式
        if [[ -n "$version_output" ]]; then
            # 方式1: 提取 v 开头的版本号
            installed_version=$(echo "$version_output" | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | sed 's/^v//')
            
            # 方式2: 如果还是没有，尝试获取最后一个数字.数字.数字格式
            if [[ -z "$installed_version" ]]; then
                installed_version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | tail -n1)
            fi
        fi
    fi
    
    if [[ -n "$installed_version" && -n "$installed_type" ]]; then
        echo "$installed_version:$installed_type:$frp_path"
    else
        echo ""
    fi
}

# 检测服务管理系统
detect_service_manager() {
    if command_exists systemctl && [[ -d /etc/systemd/system ]]; then
        echo "systemd"
    elif command_exists service && [[ -d /etc/init.d ]]; then
        echo "sysvinit"
    else
        echo "unknown"
    fi
}

# 检查服务是否存在
service_exists() {
    local service_name="$1"
    local service_manager=$(detect_service_manager)
    
    case "$service_manager" in
        systemd)
            systemctl list-unit-files | grep -q "^${service_name}.service"
            ;;
        sysvinit)
            [[ -f "/etc/init.d/$service_name" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# 检查服务状态
get_service_status() {
    local service_name="$1"
    local service_manager=$(detect_service_manager)
    
    case "$service_manager" in
        systemd)
            if systemctl is-active --quiet "$service_name"; then
                echo "running"
            elif systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
                echo "stopped"
            else
                echo "disabled"
            fi
            ;;
        sysvinit)
            if service "$service_name" status >/dev/null 2>&1; then
                echo "running"
            else
                echo "stopped"
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# 重启服务
restart_service() {
    local service_name="$1"
    local service_manager=$(detect_service_manager)
    
    log_info "正在重启 $service_name 服务..."
    
    case "$service_manager" in
        systemd)
            if sudo systemctl restart "$service_name"; then
                log_success "$service_name 服务重启成功"
                
                # 显示服务状态
                local status=$(sudo systemctl is-active "$service_name" 2>/dev/null || echo "unknown")
                log_info "服务状态: $status"
                
                # 如果服务启动失败，显示日志
                if [[ "$status" != "active" ]]; then
                    log_warn "服务似乎启动失败，最近的日志："
                    sudo journalctl -u "$service_name" --no-pager -n 10
                fi
            else
                log_error "$service_name 服务重启失败"
                return 1
            fi
            ;;
        sysvinit)
            if sudo service "$service_name" restart; then
                log_success "$service_name 服务重启成功"
            else
                log_error "$service_name 服务重启失败"
                return 1
            fi
            ;;
        *)
            log_warn "无法识别服务管理系统，请手动重启服务"
            return 1
            ;;
    esac
}

# 创建 systemd 服务文件
create_systemd_service() {
    local frp_type="$1"
    local service_file="/etc/systemd/system/${frp_type}.service"
    local executable_path="$INSTALL_DIR/$frp_type"
    local config_path="/etc/frp/${frp_type}.toml"
    local old_config_path="/etc/frp/${frp_type}.ini"
    
    log_info "正在创建 systemd 服务文件..."
    
    # 创建配置目录
    sudo mkdir -p /etc/frp
    
    # 检查是否存在旧版配置文件
    if [[ -f "$old_config_path" && ! -f "$config_path" ]]; then
        log_warn "发现旧版配置文件: $old_config_path"
        log_info "FRP 0.52.0+ 使用 TOML 格式配置文件，请手动将配置迁移到新格式"
        log_info "参考文档: https://github.com/fatedier/frp#configuration-files"
    fi
    
    # 创建示例配置文件（如果不存在）
    if [[ ! -f "$config_path" ]]; then
        case "$frp_type" in
            frps)
                sudo tee "$config_path" > /dev/null << 'EOF'
# frps.toml
bindPort = 7000

# 仪表板配置
webServer.addr = "0.0.0.0"
webServer.port = 7500
webServer.user = "admin"
webServer.password = "admin"

# 日志配置
log.to = "/var/log/frps.log"
log.level = "info"
log.maxDays = 3

# 认证配置（可选）
# auth.method = "token"
# auth.token = "your_token_here"
EOF
                ;;
            frpc)
                sudo tee "$config_path" > /dev/null << 'EOF'
# frpc.toml
serverAddr = "YOUR_SERVER_IP"
serverPort = 7000

# 日志配置
log.to = "/var/log/frpc.log"
log.level = "info"
log.maxDays = 3

# 认证配置（如果服务端设置了认证）
# auth.method = "token"
# auth.token = "your_token_here"

# 代理配置示例
# [[proxies]]
# name = "ssh"
# type = "tcp"
# localIP = "127.0.0.1"
# localPort = 22
# remotePort = 6000

# [[proxies]]
# name = "web"
# type = "http"
# localIP = "127.0.0.1"
# localPort = 80
# customDomains = ["www.example.com"]
EOF
                ;;
        esac
        log_info "已创建示例配置文件: $config_path"
    fi
    
    # 创建 systemd 服务文件
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=FRP ${frp_type^^} Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
Restart=on-failure
RestartSec=5s
ExecStart=$executable_path -c $config_path
LimitNOFILE=1048576

# 确保日志文件可写
ExecStartPre=/bin/sh -c 'touch /var/log/${frp_type}.log && chown nobody:nogroup /var/log/${frp_type}.log'

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载 systemd 配置
    sudo systemctl daemon-reload
    
    log_success "systemd 服务文件已创建: $service_file"
    return 0
}

# 服务管理菜单
service_management() {
    local frp_type="$1"
    local service_manager=$(detect_service_manager)
    
    if [[ "$service_manager" == "unknown" ]]; then
        log_warn "无法识别服务管理系统，跳过服务管理"
        return 0
    fi
    
    printf "\n" >&2
    log_info "检测到服务管理系统: $service_manager"
    
    # 检查服务是否存在
    if service_exists "$frp_type"; then
        local status=$(get_service_status "$frp_type")
        log_info "$frp_type 服务已存在，状态: $status"
        
        printf "\n" >&2
        read -p "是否重启 $frp_type 服务？ (Y/n): " -r
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            restart_service "$frp_type"
        fi
    else
        log_info "$frp_type 服务不存在"
        
        if [[ "$service_manager" == "systemd" ]]; then
            printf "\n" >&2
            read -p "是否创建并启动 systemd 服务？ (Y/n): " -r
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                if create_systemd_service "$frp_type"; then
                    # 启用并启动服务
                    printf "\n" >&2
                    read -p "是否立即启动服务？ (Y/n): " -r
                    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                        sudo systemctl enable "$frp_type"
                        restart_service "$frp_type"
                    else
                        log_info "服务已创建但未启动，可以稍后使用以下命令启动："
                        log_info "  sudo systemctl enable $frp_type"
                        log_info "  sudo systemctl start $frp_type"
                    fi
                fi
            fi
        else
            log_info "请手动创建 $service_manager 服务文件"
        fi
    fi
}

# 下载文件并验证 - 修复版本
download_frp() {
    local version="$1"
    local frp_type="$2"
    local download_url="$GITHUB_RELEASES/download/v${version}/frp_${version}_linux_${PLATFORM}.tar.gz"
    local file_name="frp_${version}_linux_${PLATFORM}.tar.gz"
    local download_path="$TMP_DIR/$file_name"
    
    # 创建临时目录
    mkdir -p "$TMP_DIR"
    
    log_info "正在下载 FRP $version ($frp_type)..."
    log_info "下载地址: $download_url"
    
    # 强制刷新输出缓冲区
    flush_output
    
    # 下载文件（在子shell中执行，完全隔离输出）
    (
        if wget --progress=bar:force -O "$download_path" "$download_url"; then
            printf "\n" >&2  # 换行，分隔下载进度和后续输出
            log_success "下载完成"
        else
            log_error "下载失败"
            exit 1
        fi
    ) >&2 2>&1
    
    # 检查子shell的退出状态
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # 验证文件是否下载成功
    if [[ ! -f "$download_path" ]] || [[ ! -s "$download_path" ]]; then
        log_error "下载的文件无效"
        return 1
    fi
    
    # 只输出路径到 stdout
    echo "$download_path"
}

# 安装 FRP
install_frp() {
    local version="$1"
    local frp_type="$2"
    local download_path="$3"
    local extract_dir="$TMP_DIR/frp_${version}_linux_${PLATFORM}"
    
    log_info "正在安装 $frp_type..."
    
    # 强制刷新输出缓冲区
    flush_output
    
    # 验证下载文件
    if [[ ! -f "$download_path" ]]; then
        log_error "下载文件不存在: $download_path"
        return 1
    fi
    
    if [[ ! -s "$download_path" ]]; then
        log_error "下载文件为空: $download_path"
        return 1
    fi
    
    log_info "文件大小: $(du -h "$download_path" | cut -f1)"
    
    # 解压缩（显示详细信息以便调试）
    log_info "正在解压缩到: $TMP_DIR"
    if ! tar -xzf "$download_path" -C "$TMP_DIR" 2>&1 >&2; then
        log_error "解压缩失败"
        log_info "尝试查看文件内容..."
        file "$download_path" >&2 || true
        log_info "尝试列出 tar 文件内容..."
        tar -tzf "$download_path" 2>&1 | head -10 >&2 || true
        return 1
    fi
    
    # 列出解压后的内容
    log_info "解压后的内容:"
    ls -la "$TMP_DIR" >&2 || true
    
    # 检查可执行文件是否存在
    local executable_path="$extract_dir/$frp_type"
    if [[ ! -f "$executable_path" ]]; then
        log_error "在解压的文件中找不到 $frp_type 可执行文件"
        log_info "预期路径: $executable_path"
        log_info "实际解压内容:"
        find "$TMP_DIR" -name "*frp*" -type f >&2 || true
        return 1
    fi
    
    # 备份现有安装（如果存在）
    local install_path="$INSTALL_DIR/$frp_type"
    if [[ -f "$install_path" ]]; then
        log_info "备份现有安装..."
        sudo cp "$install_path" "${install_path}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # 安装新版本
    sudo cp "$executable_path" "$install_path"
    sudo chmod +x "$install_path"
    
    # 验证安装
    if ! "$install_path" --version >/dev/null 2>&1; then
        log_error "安装验证失败"
        return 1
    fi
    
    log_success "安装完成"
    return 0
}

# 卸载 FRP
uninstall_frp() {
    local frp_type="$1"
    local install_path="$INSTALL_DIR/$frp_type"
    local service_manager=$(detect_service_manager)
    
    # 首先处理服务
    if service_exists "$frp_type"; then
        log_info "正在停止 $frp_type 服务..."
        
        case "$service_manager" in
            systemd)
                sudo systemctl stop "$frp_type" 2>/dev/null || true
                sudo systemctl disable "$frp_type" 2>/dev/null || true
                
                read -p "是否删除 systemd 服务文件？ (Y/n): " -r
                if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                    sudo rm -f "/etc/systemd/system/${frp_type}.service"
                    sudo systemctl daemon-reload
                    log_success "服务文件已删除"
                fi
                ;;
            sysvinit)
                sudo service "$frp_type" stop 2>/dev/null || true
                ;;
        esac
    fi
    
    if [[ -f "$install_path" ]]; then
        log_info "正在卸载 $frp_type..."
        sudo rm "$install_path"
        
        # 清理备份文件（可选）
        read -p "是否删除所有备份文件？ (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo rm -f "${install_path}.backup."*
        fi
        
        # 清理配置文件（可选）
        local config_path="/etc/frp/${frp_type}.toml"
        local old_config_path="/etc/frp/${frp_type}.ini"  # 兼容旧版本
        
        if [[ -f "$config_path" ]]; then
            read -p "是否删除配置文件 $config_path？ (y/N): " -r
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                sudo rm -f "$config_path"
            fi
        fi
        
        # 检查并清理旧版配置文件
        if [[ -f "$old_config_path" ]]; then
            read -p "发现旧版配置文件 $old_config_path，是否删除？ (y/N): " -r
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                sudo rm -f "$old_config_path"
            fi
        fi
        
        # 如果 /etc/frp 目录为空，也删除它
        if [[ -d "/etc/frp" ]] && [[ -z "$(ls -A /etc/frp 2>/dev/null)" ]]; then
            sudo rmdir /etc/frp
        fi
        
        log_success "$frp_type 已卸载"
    else
        log_warn "$frp_type 未安装"
    fi
}

# 显示使用说明
show_usage() {
    cat << EOF
FRP 安装脚本 - 使用说明

用法: $0 [选项]

选项:
  -h, --help         显示此帮助信息
  -u, --uninstall TYPE  卸载指定类型的 FRP (frps/frpc)
  -d, --debug        调试模式：显示当前安装的详细信息
  
交互模式:
  不带参数运行脚本将进入交互模式，提供完整的菜单选项。

功能特性:
  ✅ 自动检测系统架构 (amd64/arm64/arm)
  ✅ 支持安装、升级、卸载
  ✅ 自动服务管理 (systemd/sysvinit)
  ✅ 创建示例配置文件 (TOML 格式)
  ✅ 备份现有安装
  ✅ 版本检测和比较
  ✅ 交互式菜单系统
  ✅ 支持同时安装 frps 和 frpc
  ✅ 兼容旧版 INI 配置文件检测

服务管理:
  安装后会自动创建 systemd 服务（如果系统支持）
  配置文件位置: /etc/frp/[frps|frpc].toml
  服务操作:
    sudo systemctl start/stop/restart [frps|frpc]
    sudo systemctl enable/disable [frps|frpc]
    sudo journalctl -u [frps|frpc] -f

示例:
  $0                    # 交互模式（推荐）
  $0 --debug            # 调试模式
  $0 --uninstall frps   # 直接卸载 frps
  $0 --uninstall frpc   # 直接卸载 frpc

EOF
}

# 调试模式 - 显示详细的安装信息
debug_mode() {
    printf "=== FRP 安装调试信息 ===\n\n" >&2
    
    # 检查系统架构
    printf "系统架构: $(uname -m)\n" >&2
    
    # 检查 PATH 中的 frps/frpc
    printf "\nPATH 中的 FRP 命令:\n" >&2
    if command_exists frps; then
        local frps_path=$(command -v frps)
        printf "  frps: %s\n" "$frps_path" >&2
        printf "  权限: %s\n" "$(ls -la "$frps_path" 2>/dev/null || echo "无法获取")" >&2
        printf "  版本输出:\n" >&2
        frps --version 2>&1 | sed 's/^/    /' >&2
    else
        printf "  frps: 未找到\n" >&2
    fi
    
    if command_exists frpc; then
        local frpc_path=$(command -v frpc)
        printf "  frpc: %s\n" "$frpc_path" >&2
        printf "  权本: %s\n" "$(ls -la "$frpc_path" 2>/dev/null || echo "无法获取")" >&2
        printf "  版本输出:\n" >&2
        frpc --version 2>&1 | sed 's/^/    /' >&2
    else
        printf "  frpc: 未找到\n" >&2
    fi
    
    # 检查指定目录中的 frps/frpc
    printf "\n指定目录 (%s) 中的 FRP:\n" "$INSTALL_DIR" >&2
    for tool in frps frpc; do
        local tool_path="$INSTALL_DIR/$tool"
        if [[ -e "$tool_path" ]]; then
            printf "  %s: 存在\n" "$tool" >&2
            printf "  权限: %s\n" "$(ls -la "$tool_path" 2>/dev/null || echo "无法获取")" >&2
            if [[ -x "$tool_path" ]]; then
                printf "  版本输出:\n" >&2
                "$tool_path" --version 2>&1 | sed 's/^/    /' >&2
            else
                printf "  状态: 文件存在但不可执行\n" >&2
            fi
        else
            printf "  %s: 不存在\n" "$tool" >&2
        fi
    done
    
    # 运行检测函数
    printf "\n检测函数结果:\n" >&2
    local installed_info=$(get_installed_info)
    if [[ -n "$installed_info" ]]; then
        printf "  检测结果: %s\n" "$installed_info" >&2
        local installed_version="${installed_info%%:*}"
        local remaining="${installed_info#*:}"
        local installed_type="${remaining%%:*}"
        local frp_path="${remaining#*:}"
        printf "  解析版本: %s\n" "$installed_version" >&2
        printf "  解析类型: %s\n" "$installed_type" >&2
        printf "  解析路径: %s\n" "$frp_path" >&2
    else
        printf "  检测结果: 未检测到已安装的 FRP\n" >&2
    fi
    
    # 服务状态
    printf "\n服务状态:\n" >&2
    local service_manager=$(detect_service_manager)
    printf "  服务管理系统: %s\n" "$service_manager" >&2
    
    for tool in frps frpc; do
        if service_exists "$tool"; then
            local status=$(get_service_status "$tool")
            printf "  %s 服务: 存在 (状态: %s)\n" "$tool" "$status" >&2
            
            # 显示服务文件路径
            case "$service_manager" in
                systemd)
                    local service_file="/etc/systemd/system/${tool}.service"
                    if [[ -f "$service_file" ]]; then
                        printf "    服务文件: %s\n" "$service_file" >&2
                    fi
                    ;;
                sysvinit)
                    local init_script="/etc/init.d/$tool"
                    if [[ -f "$init_script" ]]; then
                        printf "    初始化脚本: %s\n" "$init_script" >&2
                    fi
                    ;;
            esac
        else
            printf "  %s 服务: 不存在\n" "$tool" >&2
        fi
        
        # 检查配置文件
        local config_path="/etc/frp/${tool}.toml"
        local old_config_path="/etc/frp/${tool}.ini"
        
        if [[ -f "$config_path" ]]; then
            printf "  %s 配置: %s (存在 - 新格式)\n" "$tool" "$config_path" >&2
        else
            printf "  %s 配置: %s (不存在)\n" "$tool" "$config_path" >&2
        fi
        
        if [[ -f "$old_config_path" ]]; then
            printf "  %s 旧配置: %s (存在 - 需要迁移到 TOML 格式)\n" "$tool" "$old_config_path" >&2
        fi
    done
    
    printf "\n=== 调试信息结束 ===\n" >&2
}

# 简单的安装新类型函数
install_new_type() {
    local frp_type="$1"
    
    log_info "准备安装 $frp_type..."
    
    local download_path
    download_path=$(download_frp "$LATEST_VERSION" "$frp_type")
    
    if install_frp "$LATEST_VERSION" "$frp_type" "$download_path"; then
        local new_version
        new_version=$("$INSTALL_DIR/$frp_type" --version | awk '{print $3}')
        log_success "安装完成！类型: $frp_type，版本: $new_version"
        
        # 服务管理
        service_management "$frp_type"
        
        printf "\n" >&2
        log_info "接下来您可能需要："
        log_info "1. 编辑配置文件: /etc/frp/${frp_type}.toml"
        log_info "2. 配置防火墙规则（如需要）"
        log_info "3. 查看服务状态: sudo systemctl status $frp_type"
        log_info "4. 查看服务日志: sudo journalctl -u $frp_type -f"
    else
        log_error "安装失败"
        exit 1
    fi
}

# 处理已安装情况的升级逻辑
handle_upgrade() {
    local installed_info="$1"
    local installed_version="${installed_info%%:*}"
    local remaining="${installed_info#*:}"
    local installed_type="${remaining%%:*}"
    local frp_path="${remaining#*:}"
    
    log_success "系统已安装 $installed_type，当前版本: $installed_version"
    log_info "安装路径: $frp_path"
    
    if [[ "$installed_version" == "$LATEST_VERSION" ]]; then
        log_success "已是最新版本，无需升级"
        
        # 询问是否安装另一个类型
        local other_type="$([ "$installed_type" = "frps" ] && echo "frpc" || echo "frps")"
        printf "\n" >&2
        read -p "是否安装另一个类型 ($other_type)？ (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_new_type "$other_type"
        fi
        return 0
    fi
    
    if version_gt "$LATEST_VERSION" "$installed_version"; then
        printf "\n" >&2
        read -p "发现新版本 $LATEST_VERSION (当前: $installed_version)，是否升级？ (Y/n): " -r
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            log_info "取消升级"
            return 0
        fi
        
        local download_path
        download_path=$(download_frp "$LATEST_VERSION" "$installed_type")
        
        if install_frp "$LATEST_VERSION" "$installed_type" "$download_path"; then
            local new_version
            new_version=$("$INSTALL_DIR/$installed_type" --version | awk '{print $3}')
            log_success "升级完成！版本: $new_version"
            
            # 服务管理
            service_management "$installed_type"
        else
            log_error "升级失败"
            exit 1
        fi
    else
        log_warn "当前版本 ($installed_version) 比最新版本 ($LATEST_VERSION) 更新"
        log_info "如果确实需要安装 $LATEST_VERSION，请先卸载当前版本"
    fi
    
    # 给用户更多选择
    printf "\n其他操作选项:\n" >&2
    printf "1. 安装另一个 FRP 类型 (%s)\n" "$([ "$installed_type" = "frps" ] && echo "frpc" || echo "frps")" >&2
    printf "2. 卸载当前 FRP ($installed_type)\n" >&2
    printf "3. 退出\n\n" >&2
    
    read -p "请选择操作 (1/2/3): " -r choice
    case "$choice" in
        1)
            local other_type="$([ "$installed_type" = "frps" ] && echo "frpc" || echo "frps")"
            install_new_type "$other_type"
            ;;
        2)
            uninstall_frp "$installed_type"
            ;;
        3)
            log_info "退出脚本"
            exit 0
            ;;
        *)
            log_info "无效选择，退出脚本"
            exit 0
            ;;
    esac
}

# 处理新安装情况
handle_new_install() {
    log_info "系统未安装 FRP"
    printf "\n请选择要安装的 FRP 类型：\n" >&2
    printf "  frps - FRP 服务端\n" >&2
    printf "  frpc - FRP 客户端\n\n" >&2
    
    while true; do
        read -p "请输入选择 (frps/frpc): " -r frp_type
        case "$frp_type" in
            frps|frpc)
                break
                ;;
            *)
                log_error "无效选择，请输入 frps 或 frpc"
                ;;
        esac
    done
    
    local download_path
    download_path=$(download_frp "$LATEST_VERSION" "$frp_type")
    
    if install_frp "$LATEST_VERSION" "$frp_type" "$download_path"; then
        local installed_version
        installed_version=$("$INSTALL_DIR/$frp_type" --version | awk '{print $3}')
        log_success "安装完成！类型: $frp_type，版本: $installed_version"
        
        # 服务管理
        service_management "$frp_type"
        
        printf "\n" >&2
        log_info "接下来您可能需要："
        log_info "1. 编辑配置文件: /etc/frp/${frp_type}.toml"
        log_info "2. 配置防火墙规则（如需要）"
        log_info "3. 查看服务状态: sudo systemctl status $frp_type"
        log_info "4. 查看服务日志: sudo journalctl -u $frp_type -f"
    else
        log_error "安装失败"
        exit 1
    fi
}

# 主函数
main() {
    # 解析命令行参数
    case "${1:-}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -d|--debug)
            detect_architecture  # 确保架构检测先运行
            debug_mode
            exit 0
            ;;
        -u|--uninstall)
            if [[ -z "${2:-}" ]]; then
                log_error "请指定要卸载的类型 (frps/frpc)"
                exit 1
            fi
            case "$2" in
                frps|frpc)
                    check_sudo
                    uninstall_frp "$2"
                    exit 0
                    ;;
                *)
                    log_error "无效的类型: $2"
                    exit 1
                    ;;
            esac
            ;;
        "")
            # 交互模式
            ;;
        *)
            log_error "未知选项: $1"
            show_usage
            exit 1
            ;;
    esac
    
    # 检查环境
    check_dependencies
    check_sudo
    detect_architecture
    get_latest_version
    
    # 检查已安装的版本
    local installed_info
    installed_info=$(get_installed_info)
    
    if [[ -n "$installed_info" ]]; then
        handle_upgrade "$installed_info"
    else
        handle_new_install
    fi
}

# 最终清理
final_cleanup() {
    [[ -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}

# 设置退出时清理
trap final_cleanup EXIT

# 运行主函数
main "$@"
