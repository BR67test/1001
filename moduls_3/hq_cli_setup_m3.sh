#!/bin/bash
echo "=== HQ-CLI (Модуль 3) ==="

# ============================================
# 2. Доверие сертификату CA
# ============================================

scp -P 2026 sshuser@192.168.100.2:/etc/ssl/CA/certs/ca.crt /usr/local/share/ca-certificates/
update-ca-certificates

# ============================================
# 5. CUPS клиент
# ============================================

apt-get update && apt-get install -y cups-client cups-common
lpadmin -p PDF_Printer -E -v ipp://192.168.100.2/printers/PDF -m everywhere
lpoptions -d PDF_Printer

# ============================================
# 8. Ansible (как цель для инвентаризации)
# ============================================

useradd ansible 2>/dev/null
echo "ansible:ansible" | chpasswd
echo "AllowUsers ansible sshuser" >> /etc/openssh/sshd_config
systemctl restart sshd

# ============================================
# 10. Кибер Бэкап (агент + узел хранилища)
# ============================================

# Монтирование диска с агентом
mount /dev/cdrom /mnt 2>/dev/null || mount /dev/sr0 /mnt 2>/dev/null

if [ -d /mnt/cyberbackup-agent ]; then
    echo "Установка агента Кибер Бэкап..."
    dpkg -i /mnt/cyberbackup-agent/*.deb 2>/dev/null
    if [ -f /mnt/cyberbackup-agent/install.sh ]; then
        /mnt/cyberbackup-agent/install.sh --mode unattended --server 192.168.100.2
    fi
fi

# Создание директории хранилища
mkdir -p /backup
chmod 755 /backup

# Настройка SFTP для пользователя irpoadmin
useradd irpoadmin -m 2>/dev/null
echo "irpoadmin:P@ssw0rd" | chpasswd

cat >> /etc/openssh/sshd_config <<EOF

Match User irpoadmin
    ForceCommand internal-sftp
    PasswordAuthentication yes
    ChrootDirectory /backup
    PermitTunnel no
    AllowAgentForwarding no
    AllowTcpForwarding no
    X11Forwarding no
EOF

systemctl restart sshd

chown root:root /backup
mkdir -p /backup/home/irpoadmin
chown irpoadmin:irpoadmin /backup/home/irpoadmin

# Подключение к серверу управления
if command -v cbagent &>/dev/null; then
    cbagent config set server 192.168.100.2
    cbagent config set port 443
    cbagent config set --insecure
    cbagent connect --username irpoadmin --password P@ssw0rd
fi

echo "=== HQ-CLI (Модуль 3) готов ==="
