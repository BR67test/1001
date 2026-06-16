#!/bin/bash
echo "=== HQ-CLI (Модуль 3) ==="

# ============================================
# 2. Доверие сертификату CA
# ============================================

if [ -f /mnt/nfs/ca.cer ]; then
    cp /mnt/nfs/ca.cer /etc/pki/ca-trust/source/anchors/
    update-ca-trust
    echo "CA сертификат установлен"
else
    echo "CA сертификат не найден в /mnt/nfs/ca.cer"
fi

# ============================================
# 5. CUPS клиент
# ============================================

# В ALT Linux пакет называется cups-client или cups-common
apt-get update
apt-get install -y cups-client cups-common 2>/dev/null || apt-get install -y cups

# Добавление принтера (если CUPS сервер доступен)
if command -v lpadmin &>/dev/null; then
    lpadmin -p PDF_Printer -E -v ipp://192.168.1.10:631/printers/PDF -m everywhere 2>/dev/null
    lpoptions -d PDF_Printer 2>/dev/null
    echo "Принтер PDF_Printer настроен"
else
    echo "CUPS клиент не установлен, пропускаем настройку принтера"
fi

# Добавление записи в /etc/hosts
if ! grep -q "hq-srv.au-team.irpo" /etc/hosts; then
    echo "192.168.1.10 hq-srv.au-team.irpo hq-srv" >> /etc/hosts
fi

# ============================================
# 10. Кибер Бэкап (узел хранилища)
# ============================================

# Создание директории хранилища
mkdir -p /backup
chmod 755 /backup

# Создание пользователя irpoadmin (правильное имя!)
useradd irpoadmin -m 2>/dev/null

# Установка пароля через passwd (не chpasswd)
echo "irpoadmin:P@ssw0rd1!" | passwd --stdin irpoadmin 2>/dev/null || \
echo "irpoadmin:P@ssw0rd1!" | chpasswd 2>/dev/null || \
(echo "irpoadmin"; echo "P@ssw0rd1!") | passwd irpoadmin

# Настройка SFTP для irpoadmin
if ! grep -q "Match User irpoadmin" /etc/openssh/sshd_config; then
    cat >> /etc/openssh/sshd_config <<'EOF'

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
fi

# Права для chroot
chown root:root /backup
mkdir -p /backup/home/irpoadmin
chown irpoadmin:irpoadmin /backup/home/irpoadmin

echo "=== HQ-CLI (Модуль 3) готов ==="
