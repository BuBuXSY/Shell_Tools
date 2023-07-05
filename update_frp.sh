#!/bin/bash

# 设置安装目录
install_dir="/usr/local/frp"


# 获取最新版本号
latest_version=$(curl -sL "https://github.com/fatedier/frp/releases/latest" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

# 删除版本号前缀 "v"
latest_version=${latest_version#v}

# 检查系统是否已安装frp
frp_version=$(/usr/local/frp/frps --version 2>/dev/null || /usr/local/frp/frpc --version 2>/dev/null)
if [[ -n "$frp_version" ]]; then
    echo "系统已安装frp，当前版本为: $frp_version"

    # 检查已安装的版本是否与最新版本相同
    if [[ "$frp_version" == "$latest_version" ]]; then
        echo "已安装最新版本 $latest_version，取消安装"
        exit 0
    fi

    # 检查已安装的版本是否低于最新版本
    if [[ "$frp_version" < "$latest_version" ]]; then
        read -p "已安装的frp版本 $frp_version 低于最新版本 $latest_version，是否要升级？ (y/n): " upgrade_choice
        if [[ "$upgrade_choice" == "y" ]]; then
            echo "开始升级frp..."

            # 获取已安装的frp类型
            installed_type=""
            if [[ -x "/usr/local/frp/frps" ]]; then
                installed_type="frps"
            elif [[ -x "/usr/local/frp/frpc" ]]; then
                installed_type="frpc"
            fi

            # 判断用户选择的升级类型
            if [[ "$installed_type" == "frps" ]]; then
                frp_executable="frps"
            elif [[ "$installed_type" == "frpc" ]]; then
                frp_executable="frpc"
            else
                echo "无效的安装类型"
                exit 1
            fi

            # 解码链接中的编码字符
		    decoded_version=$(echo -e "$latest_version")
		    download_url="https://github.com/fatedier/frp/releases/download/v${decoded_version}/frp_${latest_version}_linux_${platform}.tar.gz"

		    # 获取下载文件名
		    file_name=$(basename "$download_url")


		    # 创建安装目录
		    sudo mkdir -p "$install_dir"

		    # 下载frp
		    sudo wget -O "/tmp/$file_name" "$download_url"

		    # 解压缩并安装frp
		    sudo tar -xzf "/tmp/$file_name" -C "/tmp"

		    # 移动frps/frpc文件到安装目录
		    sudo mv "/tmp/frp_${latest_version}_linux_${platform}/$frp_executable" "$install_dir/$frp_executable"

		    # 清理临时文件
		    sudo rm "/tmp/$file_name"

            # 显示已升级成功
            echo "升级成功"
            
        else
            echo "取消升级"
            exit 0
        fi
    fi

else
    echo "系统未安装frp"
fi

# 询问用户需要安装frps还是frpc
read -p "请选择要安装的frp类型 (frps/frpc): " frp_type

# 检查用户选择
if [[ "$frp_type" == "frps" ]]; then
    frp_executable="frps"
elif [[ "$frp_type" == "frpc" ]]; then
    frp_executable="frpc"
else
    echo "无效的选择"
    exit 1
fi

# 显示系统架构
echo "系统架构: $architecture"

# 判断系统架构
architecture=$(uname -m)
if [[ "$architecture" == "x86_64" ]]; then
    platform="amd64"
elif [[ "$architecture" == "aarch64" ]]; then
    platform="arm64"
else
    echo "不支持的系统架构: $architecture"
    exit 1
fi

# 获取最新版本号
#latest_version=$(curl -sL "https://github.com/fatedier/frp/releases/latest" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)


# 删除版本号前缀 "v"
#latest_version=${latest_version#v}

# 解码链接中的编码字符
decoded_version=$(echo -e "$latest_version")
download_url="https://github.com/fatedier/frp/releases/download/v${decoded_version}/frp_${latest_version}_linux_${platform}.tar.gz"

# 获取下载文件名
file_name=$(basename "$download_url")


# 创建安装目录
sudo mkdir -p "$install_dir"

# 下载frp
sudo wget -O "/tmp/$file_name" "$download_url"

# 解压缩并安装frp
sudo tar -xzf "/tmp/$file_name" -C "/tmp"

# 移动frps/frpc文件到安装目录
sudo mv "/tmp/frp_${latest_version}_linux_${platform}/$frp_executable" "$install_dir/$frp_executable"


# 清理临时文件
sudo rm "/tmp/$file_name"


# 显示安装的frp版本和类型
installed_version=$("$install_dir/$frp_executable" --version | awk '{print $3}')
echo "frp安装完成，版本: $installed_version 类型: $frp_type"
