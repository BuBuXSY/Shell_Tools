#!/bin/bash

test_edns_support() {
  # 获取本地IP
  local local_ip=$(curl -s https://ipinfo.io/ip)
  # 将本地IP添加变成IP-cidr
  local subnet="${local_ip}/24"
  
  # 用来储存支持EDNS的服务器
  local edns_servers=()


  local servers=(
    # 剩下的服务器列表...
    # google dns
    tcp://8.8.8.8
    tcp://8.8.4.4
    https://dns.google/dns-query
    tls://dns.google
    # NextDNS
    https://dns.nextdns.io
    tls://dns.nextdns.io
    https://anycast.dns.nextdns.io
    tls://anycast.dns.nextdns.io
    # Quad101
    tcp://101.101.101.101
    tcp://101.102.103.104
    https://dns.twnic.tw/dns-query
    tls://101.101.101.101
    # cloudflare
    tcp://1.1.1.1
    tcp://1.0.0.1
    https://dns.cloudflare-dns.com/dns-query
    tls://1dot1dot1dot1.cloudflare-dns.com
    # Ali DNS
    tcp://223.5.5.5
    tcp://223.6.6.6
    https://dns.alidns.com/dns-query
    tls://dns.alidns.com
    # DNSPod Public DNS+
    tcp://119.29.29.29
    tcp://119.28.28.28
    https://doh.pub/dns-query
    https://dns.pub/dns-query
    tls://dot.pub
    # 114 DNS
    tcp://114.114.114.114
    tcp://114.114.115.115
    # Quad9 DNS
    tcp://9.9.9.11
    tcp://149.112.112.11
    https://dns11.quad9.net/dns-query
    tls://dns11.quad9.net
    # 威瑞信公共DNS
    tcp://64.6.64.6
    tcp://64.6.65.6
    # SWITCH DNS
    https://dns.switch.ch/dns-query
    tls://dns.switch.ch 	
    # DNS.SB
    tcp://185.222.222.222
    tcp://45.11.45.11
    https://doh.dns.sb/dns-query
    tls://185.222.222.222
    # ibksturm DNS
    tls://ibksturm.synology.me
    https://ibksturm.synology.me/dns-query
    # Cisco OpenDNS
    tcp://208.67.222.222
    tcp://208.67.220.220
    https://doh.opendns.com/dns-query
    # IIJ.JP
    https://public.dns.iij.jp/dns-query
    tls://public.dns.iij.jp
    # Yandex DNS
    tcp://77.88.8.8
    tcp://77.88.8.1
    # Adguard DNS
    tcp://94.140.14.14
    tcp://94.140.15.15
    https://dns.adguard-dns.com/dns-query
    tls://dns.adguard-dns.com
    quic://dns.adguard-dns.com
    # bubujun
    https://doh.bubujun.top/dns-query
    # oolongcha
    https://dns.oolongcha.top/dns-query
    )

	commandline="q A '--subnet='$subnet'' --timeout=5s -t txt o-o.myaddr.l.google.com -s @DNS_SERVER -S 2>/dev/null"

	# 测试支持edns的dns服务器
	test_server() {
  	server=$1

  	echo -n "测试DNS: $server "

  	if res=$(eval "${commandline//@DNS_SERVER/$server}"); then
    	if [[ $res == *"edns0"* ]]; then
      	echo -e "\033[32m支持 EDNS\033[0m"
      	edns_servers+=("$server")  # 用来储存支持EDNS的服务器
    	else
      	echo -e "\033[31m不支持 EDNS\033[0m"
    	fi
  	else
    	echo -e "\033[31mDNS错误\033[0m"
  	fi
	}

	# 遍历 DNS 服务器并测试 EDNS 支持
	for server in "${servers[@]}"; do
  		test_server "$server"
  		sleep 1 # 等待 1 秒
  	done
	# 打印支持 EDNS 的服务器列表
	echo -e "\e[32m支持EDNS的服务器列表:\e[0m"
	for edns_server in "${edns_servers[@]}"; do
  		echo "$edns_server"
	done
}



# 在Ubuntu或Debian上安装q
install_q_deb() {
  echo "正在为您安装'q' ....."
  
  # Download 'q' package
  wget -O q.deb https://github.com/natesales/q/releases/download/v0.11.1/q_0.11.1_linux_amd64.deb

  # Install 'q' package
  sudo dpkg -i q.deb
  sudo apt-get install -f -y

  # Clean up downloaded package
  rm q.deb

  echo "'q' 安装成功!"
}

# 在MACOS (M1/2) 上安装q
install_q_mac() {
  echo "正在为您安装'q' ....."

  # Download 'q' package
  curl -LO https://github.com/natesales/q/releases/download/v0.11.1/q_0.11.1_darwin_arm64.tar.gz

  # Extract 'q' package
  tar xf q_0.11.1_darwin_arm64.tar.gz

  # Move 'q' binary to /usr/local/bin
  sudo mv q /usr/local/bin

  # Clean up downloaded package and extracted files
  rm q_0.11.1_darwin_arm64.tar.gz

  echo "'q' 安装成功!"
}

# 在Centos或Redhat上安装q
install_q_rpm() {
  echo "正在为您安装'q' ....."

  # Download 'q' package
  wget -O q.rpm https://github.com/natesales/q/releases/download/v0.11.1/q_0.11.1_linux_amd64.rpm

  # Install 'q' package
  sudo rpm -i q.rpm

  # Clean up downloaded package
  rm q.rpm

  echo "'q' 安装成功!"
}

# 在Openwrt arm64 上安装q
install_q_openwrt() {
  echo "正在为您安装'q' ....."

  # Download 'q' package
  wget -O q.tar.gz https://github.com/natesales/q/releases/download/v0.11.1/q_0.11.1_linux_arm64.tar.gz

  # Extract 'q' package
  tar xf q.tar.gz

  # Move 'q' binary to /usr/bin
  mv q /usr/bin

  # Clean up downloaded package and extracted files
  rm q.tar.gz

  echo "'q' 安装成功!"
}

# Check OS type
case "$(uname -s)" in
  Linux*)
    if [ -f "/etc/os-release" ]; then
      source "/etc/os-release"

      if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
        echo "Detected $NAME $VERSION_ID"

        # Check if 'q' command-line tool is installed
        if ! command -v q &>/dev/null; then
          install_q_deb
        else
          echo "'q' 已经安装，接下来将用'q'来进行测试"
        fi

      # Continue with testing DNS servers for EDNS support
      test_edns_support
        exit 0
      elif [[ "$ID" == "centos" || "$ID" == "rhel" ]]; then
        echo "Detected $NAME $VERSION_ID"

        # Check if 'q' command-line tool is installed
        if ! command -v q &>/dev/null; then
          install_q_rpm
        else
          echo "'q' 已经安装，接下来将用'q'来进行测试"
        fi
      
      # Continue with testing DNS servers for EDNS support
      test_edns_support
        exit 0
      fi
    fi
    ;;
  Darwin*)
    if [[ "$(uname -m)" == "arm64" ]]; then
      echo "Detected macOS (M1/2 chip)"

      # Check if 'q' command-line tool is installed
      if ! command -v q &>/dev/null; then
        install_q_mac
      else
          echo "'q' 已经安装，接下来将用'q'来进行测试"
      fi

      # Continue with testing DNS servers for EDNS support
      test_edns_support
      exit 0
    fi
    ;;
  *)
    echo "这个脚本仅支持Ubuntu, Debian, macOS (M1/2 chip), CentOS, Red Hat, and OpenWrt ARM64 systems."
    exit 1
    ;;
esac

# Handle OpenWrt ARM64 separately
if [[ "$(uname -m)" == "aarch64" && -f "/etc/openwrt_release" ]]; then
  echo "Detected OpenWrt ARM64"

  # Check if 'q' command-line tool is installed
  if ! command -v q &>/dev/null; then
    install_q_openwrt
  else
     echo "'q' 已经安装，接下来将用'q'来进行测试"
  fi

  # Continue with testing DNS servers for EDNS support
  test_edns_support
  exit 0
fi

echo "这个脚本仅支持Ubuntu, Debian, macOS (M1/2 chip), CentOS, Red Hat, and OpenWrt ARM64 systems."
exit 1
