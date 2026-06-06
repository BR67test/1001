#!/bin/bash
echo "=== HQ-RTR (Модуль 2) ==="

# Проброс портов на HQ-SRV
iptables -t nat -A PREROUTING -i enp7s1 -p tcp --dport 2026 -j DNAT --to-destination 192.168.100.2:2026
iptables -t nat -A PREROUTING -i enp7s1 -p tcp --dport 8080 -j DNAT --to-destination 192.168.100.2:80
iptables-save > /etc/sysconfig/iptables

# Смена DNS-сервера в DHCP (с HQ-SRV на BR-SRV)
if [ -f /etc/dhcp/dhcpd.conf ]; then
    sed -i 's/192.168.100.2/192.168.0.2/g' /etc/dhcp/dhcpd.conf
    systemctl restart dhcpd
fi

# NTP-клиент (сервер — ISP)
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.1.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

echo "=== HQ-RTR обновлен ==="
