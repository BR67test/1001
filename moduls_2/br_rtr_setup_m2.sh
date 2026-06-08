#!/bin/bash
echo "=== BR-RTR (Модуль 2) ==="

# Проброс портов на BR-SRV
iptables -t nat -A PREROUTING -i enp7s3 -p tcp --dport 2026 -j DNAT --to-destination 192.168.0.2:2026
iptables -t nat -A PREROUTING -i enp7s3 -p tcp --dport 8080 -j DNAT --to-destination 192.168.0.2:8080
iptables-save > /etc/sysconfig/iptables

# NTP-клиент (сервер — ISP)
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.2.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

echo "=== BR-RTR обновлен ==="
