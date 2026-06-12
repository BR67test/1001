#!/bin/bash
echo "=== HQ-RTR (Модуль 2) ==="

# ============================================
# SSH настройка (порт 2026)
# ============================================
apt-get update && apt-get install -y openssh-server

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
# Смена DNS-сервера в DHCP (ISC DHCP)
# ============================================
if [ -f /etc/dnsmasq.conf ]; then
    # Замена DNS на 192.168.0.2
    sed -i 's/dhcp-option=6,.*/dhcp-option=6,192.168.3.10,192.168.1.10/' /etc/dnsmasq.conf
    systemctl restart dnsmasq
    echo "dnsmasq обновлён (DNS = 192.168.1.10)"
else
    echo "Файл /etc/dnsmasq.conf не найден"
fi

# ============================================
# NTP-клиент
# ============================================
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.1.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

echo "=== HQ-RTR готов ==="
echo "SSH: port 2026, user: net_admin, password: P@ssw0rd"
