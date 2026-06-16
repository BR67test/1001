#!/bin/bash
echo "=== HQ-SRV (Модуль 3) ==="

# ============================================
# 2. Центр сертификации (CA) — полностью переделано
# ============================================

apt-get update && apt-get install -y openssl ca-certificates

# Создание структуры CA
mkdir -p /etc/pki/CA/{private,certs,newcerts,crl}
touch /etc/pki/CA/index.txt
echo 1000 > /etc/pki/CA/serial
chmod 777 /etc/pki/CA/private

# Создание конфига CA
cat > /etc/ssl/openssl-ca.cnf <<'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
database = /etc/pki/CA/index.txt
serial = /etc/pki/CA/serial
new_certs_dir = /etc/pki/CA/newcerts
default_md = sha256
policy = policy_loose

[ policy_loose ]
countryName = optional
stateOrProvinceName = optional
organizationName = optional
organizationalUnitName = optional
commonName = supplied
emailAddress = optional

[ server_cert ]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

# Корневой сертификат CA
openssl req -x509 -new -nodes \
    -keyout /etc/pki/CA/private/ca.key \
    -out /etc/pki/CA/certs/ca.crt \
    -days 3650 \
    -sha256 \
    -subj "/CN=AU-TEAM Root CA"

# Сертификат для web.au-team.irpo
openssl genrsa -out /etc/pki/CA/private/web.au-team.irpo.key 2048
openssl req -new \
    -key /etc/pki/CA/private/web.au-team.irpo.key \
    -out /etc/pki/CA/web.au-team.irpo.csr \
    -subj "/CN=web.au-team.irpo"

openssl ca -batch -config /etc/ssl/openssl-ca.cnf \
    -in /etc/pki/CA/web.au-team.irpo.csr \
    -out /etc/pki/CA/certs/web.au-team.irpo.crt \
    -extensions server_cert \
    -days 30

# Сертификат для docker.au-team.irpo
openssl genrsa -out /etc/pki/CA/private/docker.au-team.irpo.key 2048
openssl req -new \
    -key /etc/pki/CA/private/docker.au-team.irpo.key \
    -out /etc/pki/CA/docker.au-team.irpo.csr \
    -subj "/CN=docker.au-team.irpo"

openssl ca -batch -config /etc/ssl/openssl-ca.cnf \
    -in /etc/pki/CA/docker.au-team.irpo.csr \
    -out /etc/pki/CA/certs/docker.au-team.irpo.crt \
    -extensions server_cert \
    -days 30

# Копирование сертификатов
scp -P 2026 /etc/pki/CA/certs/docker.au-team.irpo.crt \
    /etc/pki/CA/private/docker.au-team.irpo.key \
    sshuser@192.168.0.2:/etc/pki/CA/ 2>/dev/null

cp /etc/pki/CA/certs/ca.crt /raid/nfs/ 2>/dev/null

# ============================================
# 5. CUPS принт-сервер
# ============================================

apt-get install -y cups cups-pdf

systemctl enable --now cups
cupsctl --share-printers --remote-any

lpadmin -p PDF_Printer -E -v ipp://localhost/printers/PDF -m everywhere 2>/dev/null
cupsenable PDF_Printer 2>/dev/null
cupsaccept PDF_Printer 2>/dev/null
systemctl restart cups

# ============================================
# 6. Rsyslog сервер
# ============================================

apt-get install -y rsyslog

cat > /etc/rsyslog.d/00_common.conf <<'EOF'
module(load="imuxsock")
module(load="imklog")
module(load="imtcp")

$template RemoteLogs, "/opt/%HOSTNAME%/rsyslog.txt"
*.* ?RemoteLogs
& stop
EOF

systemctl enable --now rsyslog

cat > /etc/logrotate.d/opt-logs <<'EOF'
/opt/*/rsyslog.txt {
    weekly
    minsize 10M
    rotate 4
    compress
    missingok
    notifempty
    create 0644 root root
}
EOF

# ============================================
# 7. Zabbix сервер (Prometheus вместо Zabbix)
# ============================================

# Node Exporter
useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null

curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
tar -xvf node_exporter-1.6.1.linux-amd64.tar.gz
cp node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

cat > /etc/systemd/system/node_exporter.service <<'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now node_exporter
rm -rf node_exporter-1.6.1.linux-amd64*

# ============================================
# 9. Fail2ban для SSH
# ============================================

apt-get install -y fail2ban python3-module-systemd

mkdir -p /etc/fail2ban/jail.d

cat > /etc/fail2ban/jail.d/ssh.conf <<'EOF'
[DEFAULT]
bantime = 60
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = 2026
filter = sshd
logpath = /var/log/auth.log
EOF

systemctl enable --now fail2ban 2>/dev/null
systemctl restart fail2ban 2>/dev/null

# ============================================
# 10. Кибер Бэкап (сервер управления)
# ============================================

useradd irpoadmin 2>/dev/null
echo "irpoadmin:P@ssw0rd!" | chpasswd
usermod -aG wheel irpoadmin

mount /dev/sr1 /mnt 2>/dev/null

if [ -f /mnt/cyberbackup/install.sh ]; then
    /mnt/cyberbackup/install.sh --mode unattended --admin-password "P@ssw0rd!" 2>/dev/null
fi

apt-get install -y mariadb-client

mkdir -p /opt/backup_scripts

cat > /opt/backup_scripts/backup_etc.sh <<'EOF'
#!/bin/bash
/opt/cyberbackup/bin/cbcmd backup start --plan "Backup_etc" 2>/dev/null
EOF

cat > /opt/backup_scripts/backup_db.sh <<'EOF'
#!/bin/bash
mysqldump -u web -pP@ssw0rd! webdb > /tmp/webdb_dump.sql 2>/dev/null
/opt/cyberbackup/bin/cbcmd backup start --plan "Backup_webdb" 2>/dev/null
rm -f /tmp/webdb_dump.sql
EOF

chmod +x /opt/backup_scripts/*.sh

(crontab -l 2>/dev/null; echo "0 2 * * 0 /opt/backup_scripts/backup_etc.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * 0 /opt/backup_scripts/backup_db.sh") | crontab -

# ============================================
# Настройка Apache для HTTPS
# ============================================

apt-get install -y apache2-mod_ssl

mkdir -p /etc/httpd2/conf/extra

cat > /etc/httpd2/conf/extra/ssl.conf <<'EOF'
Listen 443
<VirtualHost *:443>
    DocumentRoot /var/www/html
    ServerName web.au-team.irpo
    SSLEngine on
    SSLCertificateFile /etc/pki/CA/certs/web.au-team.irpo.crt
    SSLCertificateKeyFile /etc/pki/CA/private/web.au-team.irpo.key
</VirtualHost>
EOF

grep -q "Include conf/extra/ssl.conf" /etc/httpd2/conf/httpd2.conf || echo "Include conf/extra/ssl.conf" >> /etc/httpd2/conf/httpd2.conf

# Проверка конфига перед перезапуском
httpd2 -t
systemctl restart httpd2

echo "=== HQ-SRV (Модуль 3) готов ==="
