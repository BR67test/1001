#!/bin/bash
echo "=== HQ-RTR (Модуль 2) ==="

# ============================================
# 1. Проброс портов на HQ-SRV
# ============================================
iptables -t nat -A PREROUTING -i enp7s1 -p tcp --dport 2026 -j DNAT --to-destination 192.168.100.2:2026
iptables -t nat -A PREROUTING -i enp7s1 -p tcp --dport 8080 -j DNAT --to-destination 192.168.100.2:80
iptables-save > /etc/sysconfig/iptables

# ============================================
# 2. Смена DNS-сервера в DHCP (с HQ-SRV на BR-SRV)
# ============================================
if [ -f /etc/dhcp/dhcpd.conf ]; then
    # Замена DNS сервера
    sed -i 's/dhcp-option=6,192.168.100.2/dhcp-option=6,192.168.0.2/' /etc/dnsmasq.con
    
    # Перезапуск DHCP
    systemctl restart dnsmasq
    
    echo "DNS в DHCP изменён на 192.168.0.2 (BR-SRV)"
else
    echo "Файл /etc/dhcp/dhcpd.conf не найден"
fi

# ============================================
# 3. NTP-клиент (сервер — ISP)
# ============================================
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.1.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

# ============================================
# 4. Проверка
# ============================================
echo ""
echo "=== ПРОВЕРКА ==="
echo ""

echo "Правила NAT:"
iptables -t nat -L -n | grep -E "2026|8080" || echo "Правила не найдены"

echo ""
echo "NTP:"
chronyc sources 2>/dev/null | head -5

echo ""
echo "DHCP конфигурация:"
grep "option domain-name-servers" /etc/dhcp/dhcpd.conf 2>/dev/null

echo ""
echo "=== HQ-RTR обновлен ==="
