### 网络性能优化 感谢MapleCool大佬提供
```
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Server_Configure/main/kernel_optimization.sh）
```
### 适用于Debian系的自动更新Nginx脚本加入了QUIC Brotli OCSP GEOIP2 KTLS的支持 感谢Zhang Xin提供 并由BuBuXSY进行修改	
```
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Server_Configure/main/Auto_Upgrade_Nginx.sh)
```
### 更新Country.mmdb给nginx用
``` 
bash <(curl -Ls https://raw.githubusercontent.com/BuBuxsy/Server_Configure/main/update_Country.sh)
``` 
#默认保存的文件地址在/usr/share/GeoIP文件夹内，也可将本文件，保存在本地之后利用corntab -e 来执行定时更新运行。
Exmaple  0 4 * * * /root/update_Country.sh
