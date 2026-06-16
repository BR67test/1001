#!/bin/bash
echo "=== HQ-CLI (Модуль 3) ==="

# ============================================
# 2. Доверие сертификату CA
# ============================================

cp /mnt/nfs/ca.cer /etc/pki/ca-trust/source/anchors/ 2>/dev/null
update-ca-trust

# ============================================
# 5. CUPS клиент
# ============================================

apt-get update && apt-get install -y cups-client cups-common

lpadmin -p PDF_Printer -E -v ipp://192.168.1.10:631/printers/PDF -m everywhere 2>/dev/null
lpoptions -d PDF_Printer 2>/dev/null

echo "192.168.1.10 hq-srv.au-team.irpo hq-srv" >> /etc/hosts

# ============================================
# 10. Кибер Бэкап (узел хранилища)
# ============================================

mkdir -p /backup
chmod 755 /backup

useradd irpoadmin -m 2>/dev/null
echo "irpoadmin:P@ssw0rd1!" | chpasswd

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
