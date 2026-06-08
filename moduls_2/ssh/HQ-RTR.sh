#!/bin/bash
echo "=== SSH настройка HQ-RTR ==="

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
systemctl status sshd --no-pager

echo "=== SSH на HQ-RTR готов (порт 2026, пользователь net_admin) ==="
