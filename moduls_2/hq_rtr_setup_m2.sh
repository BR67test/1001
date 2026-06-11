#!/bin/bash
echo "=== HQ-RTR (Модуль 2) ==="

# ============================================
# 0. SSH настройка (порт 2026)
# ============================================

apt-get update && apt-get install -y openssh-server

# Пользователь net_admin (из модуля 1)
echo "net_admin:P@ssw0rd" | chpasswd

cat > /etc/openssh/sshd_config <<EOF
Port 2026
MaxAuthTries 3
PermitRootLogin no
AllowUsers net_admin
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF

systemctl enable --now sshd

# ============================================
# 1. Смена DNS-сервера в DHCP
# ============================================

if [ -f /etc/dhcp/dhcpd.conf ]; then
    sed -i 's/option domain-name-servers 192.168.1.10;/option domain-name-servers 192.168.3.10,192.168.1.10;/g' /etc/dhcp/dhcpd.conf
    systemctl restart dhcpd
    echo "ISC DHCP обновлён"
elif [ -f /etc/dnsmasq.conf ]; then
    sed -i 's/dhcp-option=6,192.168.1.10/dhcp-option=6,192.168.3.10,192.168.1.10/' /etc/dnsmasq.conf
    systemctl restart dnsmasq
    echo "dnsmasq обновлён"
fi

echo "=== Текущая конфигурация DHCP ==="
cat /etc/dnsmasq.conf 2>/dev/null | grep dhcp-option
cat /etc/dhcp/dhcpd.conf 2>/dev/null | grep domain-name-servers

echo "=== HQ-RTR (Модуль 2) готов ==="
echo "SSH: port 2026, user: net_admin, password: P@ssw0rd"
