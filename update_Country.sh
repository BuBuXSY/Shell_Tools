#!/bin/bash
mkdir -p /tmp/loyalsoldier && curl --socks5 shanghai.mxsym.cn:7891 https://raw.githubusercontent.com/Loyalsoldier/geoip/release/Country.mmdb > /tmp/loyalsoldier/Country.mmdb && \cp -rf /tmp/loyalsoldier/Country.mmdb /usr/share/GeoIP && rm -rf /tmp/loyalsoldier/Country.mmdb && echo 'update successful'
