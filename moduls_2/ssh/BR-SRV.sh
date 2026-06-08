#!/bin/bash
echo "=== SSH настройка BR-SRV ==="

apt-get update && apt-get install -y openssh-server

useradd sshuser -u 2026 2>/dev/null
echo "sshuser:P@ssw0rd" | chpasswd
usermod -aG wheel sshuser

cat > /etc/openssh/sshd_config <<EOF
Port 2026
MaxAuthTries 3
PermitRootLogin no
AllowUsers sshuser
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF

systemctl enable --now sshd
systemctl status sshd --no-pager

echo "=== SSH на BR-SRV готов (порт 2026, пользователь sshuser) ==="
