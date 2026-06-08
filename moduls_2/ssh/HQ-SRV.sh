#!/bin/bash
echo "=== SSH настройка HQ-SRV ==="

apt-get update && apt-get install -y openssh-server

useradd sshuser -u 1010 2>/dev/null
echo "sshuser:P@ssw0rd" | chpasswd
usermod -aG wheel sshuser

cat > /etc/openssh/sshd_config <<EOF
Port 2026
MaxAuthTries 2
PermitRootLogin no
AllowUsers sshuser
Banner /etc/openssh/banner
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF

echo "Authorized access only" > /etc/openssh/banner

systemctl enable --now sshd
systemctl status sshd --no-pager

echo "=== SSH на HQ-SRV готов (порт 2026, пользователь sshuser) ==="
