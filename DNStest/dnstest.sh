#!/usr/bin/env bash
sdir=$(cd $(dirname ${BASH_SOURCE[0]}); pwd)
cd "$sdir"

servers=(
# google dns
https://8.8.8.8/dns-query
https://8.8.4.4/dns-query
https://dns64.dns.google/dns-query
tls://8.8.4.4
tls://8.8.8.8

# NextDNS
https://dns.nextdns.io
tls://dns.nextdns.io
https://anycast.dns.nextdns.io
tls://anycast.dns.nextdns.io

#Quad101
https://dns.twnic.tw/dns-query
tls://101.101.101.101

# cloudflare
https://1dot1dot1dot1.cloudflare-dns.com/
https://1.1.1.1/dns-query
https://1.0.0.1/dns-query
https://cloudflare-dns.com/dns-query
https://dns.cloudflare.com/dns-query
tls://1dot1dot1dot1.cloudflare-dns.com
tls://1.1.1.1
tls://1.0.0.1
tls://cloudflare-dns.com
tls://dns.cloudflare.com

# Quad9 DNS 是一个免费、递归、任意播放的 DNS 平台，提供高性能、隐私和安全保护，免受钓鱼和间谍软件的攻击。 Quad9服务器不提供审查组件。
https://dns.quad9.net/dns-query
tls://9.9.9.9
https://dns11.quad9.net/dns-query
tls://9.9.9.11

# DNS.SB provide free DNS service with no logging, DNSSEC enabled.
https://doh.sb/dns-query
tls://dns.sb

# Oolongcha
https://doh.oolongcha.top/xushuangyi
tcp://47.242.79.87:6653

# Cisco OpenDNS 是一项通过整合内容过滤和网络钓鱼保护等功能扩展 DNS 的服务，无需停机时间。
https://doh.opendns.com/dns-query

# IIJ.JP is a public DNS service operated by Internet Initiative Japan. It also blocks child abuse content.
https://public.dns.iij.jp/dns-query
tls://public.dns.iij.jp

# 这些服务器提供了安全和可靠的连接，但它们不会像“默认”和“家庭保护”服务器一样过滤任何请求。
https://94.140.14.140/dns-query
tls://94.140.14.140
quic://94.140.14.140
)



validsers=()
vsersedns=()

usedig=false
if [ -e ./q ];then # https://github.com/natesales/q dns测试工具，支持quic doh
	chmod +x q
	commandline='./q A --subnet=$subnet --timeout=3s www.bilibili.com @$ser 2>/dev/null'
elif command -v dig >/dev/null;then
	usedig=true
	commandline='dig +short +subnet=$subnet +timeout=3  +$scheme @$domain www.taobao.com A 2>/dev/null'
else
	echo '没有测试工具，你需要安装dig或者https://github.com/natesales/q 下载q 和脚本放一起'
	exit
fi
#echo "$commandline"


for ser in "${servers[@]}";do
	echo -n "正在测试：$ser "
	scheme=${ser%%:*}
	if $usedig && [ $scheme = 'quic' ];then
		echo '  dig不支持测试quic，跳过！'
		continue
	fi
	domain=$(awk -F '/' '{print $3}' <<< $ser)
	subnet='8.8.8.8/24'
	retry=3
	for (( i=1; i<=retry; i++));do
		# 先判断是否能访问
		if res=$(eval "$commandline");then
			# ip
			resip=$( grep -m1 -Eo '(\d+\.){3}\d+' <<< $res )
			# ip前两截
			resip_p=$(awk -F '.' '{print $1,$2}' <<< $resip)
			
			validsers+=($ser)
			
			echo -ne '  \033[32m有效\033[0m'
			# 测试edns支持
			subnet='182.100.7.144/24'
			retryy=3
			for ((y=1; y<=retryy; y++));do
				if res2=$(eval "$commandline");then
					res2ip=$( grep -m1 -Eo '(\d+\.){3}\d+' <<< $res2 )
					res2ip_p=$(awk -F '.' '{print $1,$2}' <<< $res2ip)
					
					if [ "$resip_p" = "$res2ip_p" ];then
						echo -ne ' \033[31m不支持edns\033[0m'
					else
						echo -ne ' \033[33m支持edns\033[0m'
						vsersedns+=($ser)
					fi
					echo "  ($resip $res2ip)"
					
					break
				fi
				
				sleep 1
				if (( y == retryy));then
					echo "  edns测试失败"
				fi
			done
			
			break
		fi
		
		sleep 1
		if (( i == retry ));then
			echo -e '  \033[31m无效\033[0m'
		fi
	done
done

echo 
echo 有效的服务器：
for ser in "${validsers[@]}";do
	echo "$ser"
done
echo 

echo -e '有效且支持\033[33medns\033[0m的服务器：'
for ser in "${vsersedns[@]}";do
	echo "$ser"
done
echo 
