### 自建DNS可公益使用，切勿传播，且用且珍惜，华东地区,国内外分流解析 实时监控图
``` 
https://grafana.bubujun.top/grafana/d/w-Sdzen4k/mosdns-v4?orgId=1&refresh=5s 
``` 
### DNS 仅有DOH支持HTTP/3 只允许CN IP访问  
```
https://doh.bubujun.top/dns-query
``` 
#
### 网络性能优化 感谢MapleCool大佬提供
```
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Server_Configure/main/kernel_optimization.sh）
``` 
#
### 适用于Debian系的自动更新Nginx脚本加入了QUIC Brotli OCSP GEOIP2 KTLS的支持 感谢Zhang Xin提供 并由BuBuXSY进行修改	
```
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Server_Configure/main/Auto_Upgrade_Nginx.sh)
``` 
#
### 更新Country.mmdb给nginx用
``` 
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Server_Configure/main/update_Country.sh)
``` 
#### 默认保存的文件地址在/usr/share/GeoIP文件夹内(请先提前创建好文件夹mkdir -p /usr/share/GeoIP)也可将本文件，保存在本地之后利用corntab -e 来执行定时更新运行。 0 4 * * *（每天4点运行一次） /root/update_Country.sh 
#
### 用于查询访问自建DNS的IP的并显示其地理位置，用于辨别恶意刷DNS的
``` 
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Server_Configure/main/search_ip.sh)
``` 
#### 使用前现需要确定安装nali 并且开启nginx的access.log功能
#
