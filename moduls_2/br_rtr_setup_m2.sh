#!/bin/bash
echo "=== BR-RTR (Модуль 2) ==="

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
# Установка iptables (если нет)
# ============================================
apt-get install -y iptables

# ============================================
# Проброс портов
# ============================================
iptables -t nat -A PREROUTING -i enp7s1 -p tcp --dport 2026 -j DNAT --to-destination 192.168.0.2:2026
iptables -t nat -A PREROUTING -i enp7s1 -p tcp --dport 8080 -j DNAT --to-destination 192.168.0.2:8080
iptables-save > /etc/sysconfig/iptables
systemctl restart iptables

# ============================================
# NTP-клиент
# ============================================
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.2.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

echo "=== BR-RTR готов ==="
echo "SSH: port 2026, user: net_admin, password: P@ssw0rd"
