#!/bin/bash
echo "=== HQ-CLI (Модуль 3) ==="

# ============================================
# 2. Доверие сертификату CA
# ============================================

if [ -f /mnt/nfs/ca.crt ]; then
    cp /mnt/nfs/ca.crt /etc/pki/ca-trust/source/anchors/
    update-ca-trust
fi

# ============================================
# 5. CUPS клиент
# ============================================

apt-get update && apt-get install -y cups-client cups-common

sleep 5

lpadmin -p PDF_Printer -E -v ipp://192.168.100.2:631/printers/PDF -m everywhere 2>/dev/null
lpoptions -d PDF_Printer 2>/dev/null

echo "Принтер PDF_Printer настроен"

# Добавление записи в /etc/hosts
if ! grep -q "hq-srv.au-team.irpo" /etc/hosts; then
    echo "192.168.100.2 hq-srv.au-team.irpo hq-srv" >> /etc/hosts
fi

# ============================================
# 10. Кибер Бэкап (узел хранилища)
# ============================================

mkdir -p /backup
chmod 755 /backup

useradd irpoadmin -m 2>/dev/null
echo "irpoadmin:P@ssw0rd!" | chpasswd

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

chown root:root /backup
mkdir -p /backup/home/irpoadmin
chown irpoadmin:irpoadmin /backup/home/irpoadmin

echo "=== HQ-CLI (Модуль 3) готов ==="
