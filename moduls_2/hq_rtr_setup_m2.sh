#!/bin/bash
echo "=== HQ-RTR (Модуль 2) ==="

# ============================================
# Установка iptables и SSH
# ============================================
apt-get update && apt-get install -y iptables openssh-server

echo "net_admin:P@ssw0rd" | chpasswd 2>/dev/null

cat > /etc/openssh/sshd_config <<EOF
Port 2026
MaxAuthTries 3
PermitRootLogin no
AllowUsers net_admin
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF

systemctl enable --now sshd

# ============================================
# Настройка dnsmasq (DHCP)
# ============================================
if [ -f /etc/dnsmasq.conf ]; then
    # Устанавливаем DNS сервер BR-SRV
    sed -i 's/dhcp-option=6,.*/dhcp-option=6,192.168.3.10,192.168.1.10/' /etc/dnsmasq.conf
    systemctl restart dnsmasq
    echo "dnsmasq обновлён (DNS = 192.168.3.10)"
fi

# ============================================
# Удаление старого правила и добавление нового
# ============================================
iptables -t nat -D PREROUTING -i enp7s1 -p tcp --dport 8080 -j DNAT --to-destination 192.168.100.2:80 2>/dev/null
iptables -t nat -A PREROUTING -i enp7s1 -p tcp --dport 8080 -j DNAT --to-destination 192.168.1.10:80
iptables -t nat -A PREROUTING -i enp7s1 -p tcp --dport 2026 -j DNAT --to-destination 192.168.1.10:2026
iptables-save > /etc/sysconfig/iptables

# ============================================
# NTP-клиент
# ============================================
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.1.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

echo "=== HQ-RTR готов ==="
echo "SSH: port 2026, user: net_admin, password: P@ssw0rd"
