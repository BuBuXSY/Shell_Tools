#!/bin/bash
mkdir -p /tmp/loyalsoldier && curl https://raw.githubusercontent.com/Loyalsoldier/geoip/release/Country.mmdb > /tmp/loyalsoldier/Country.mmdb && \cp -rf /tmp/loyalsoldier/Country.mmdb /usr/share/geoip && rm -rf /tmp/loyalsoldier/Country.mmdb && echo 'update successful'
