#!/bin/bash
echo "=== BR-RTR (Модуль 2) ==="

# ============================================
# SSH настройка (порт 2026)
# ============================================
apt-get update && apt-get install -y openssh-server

echo "net_admin:P@ssw0rd" | chpasswd 2>/dev/null

cat > /etc/openssh/sshd_config <<EOF
Port 2026
MaxAuthTries 2
PermitRootLogin no
AllowUsers net_admin
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF

systemctl enable --now sshd

# ============================================
# Установка iptables
# ============================================
apt-get install -y iptables

# ============================================
# Проброс портов (без привязки к интерфейсу)
# ============================================
# Проброс 8080 на BR-SRV
iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 192.168.3.10:8080
iptables -A FORWARD -p tcp -d 192.168.3.10 --dport 8080 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT

# Проброс 2026 на BR-SRV
iptables -t nat -A PREROUTING -p tcp --dport 2026 -j DNAT --to-destination 192.168.3.10:2026
iptables -A FORWARD -p tcp -d 192.168.3.10 --dport 2026 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT

# Сохранение правил
iptables-save > /etc/sysconfig/iptables
systemctl restart iptables
systemctl enable --now iptables

# ============================================
# NTP-клиент
# ============================================
apt-get install -y chrony
cat > /etc/chrony.conf <<EOF
pool 172.16.2.1 iburst prefer
EOF
systemctl restart chronyd
systemctl enable --now chronyd
timedatectl set-timezone Asia/Yekaterinburg

echo "=== BR-RTR готов ==="
echo "SSH: port 2026, user: net_admin, password: P@ssw0rd"
