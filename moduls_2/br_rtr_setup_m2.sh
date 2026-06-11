#!/bin/bash
echo "=== BR-RTR (Модуль 2) ==="

# ============================================
# 0. SSH настройка (порт 2026)
# ============================================

apt-get update && apt-get install -y openssh-server

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
# 1. Проброс портов на BR-SRV
# ============================================

iptables -t nat -A PREROUTING -i enp7s1 -p tcp --dport 2026 -j DNAT --to-destination 192.168.0.2:2026
iptables -t nat -A PREROUTING -i enp7s1 -p tcp --dport 8080 -j DNAT --to-destination 192.168.0.2:8080
iptables-save > /etc/sysconfig/iptables
systemctl restart iptables

echo "=== Пробросы портов ==="
iptables -t nat -L -n -v | grep -E "2026|8080"

echo "=== BR-RTR (Модуль 2) готов ==="
echo "SSH: port 2026, user: net_admin, password: P@ssw0rd"
