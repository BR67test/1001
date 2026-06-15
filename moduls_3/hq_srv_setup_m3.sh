#!/bin/bash
echo "=== HQ-SRV (Модуль 3) ==="

# ============================================
# 2. Центр сертификации (CA)
# ============================================

apt-get update && apt-get install -y openssl ca-certificates

mkdir -p /etc/pki/CA/{private,certs,newcerts,crl}
touch /etc/pki/CA/index.txt
echo 1000 > /etc/pki/CA/serial
chmod 777 /etc/pki/CA/private

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

# Сертификат для docker.au-team.irpo
openssl genrsa -out /etc/pki/CA/private/docker.au-team.irpo.key 2048
openssl req -new \
    -key /etc/pki/CA/private/docker.au-team.irpo.key \
    -out /etc/pki/CA/docker.au-team.irpo.csr \
    -subj "/CN=docker.au-team.irpo"

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
subjectAltName = DNS:web.au-team.irpo
EOF

openssl ca -config /etc/ssl/openssl-ca.cnf \
    -in /etc/pki/CA/web.au-team.irpo.csr \
    -out /etc/pki/CA/certs/web.au-team.irpo.crt \
    -extensions server_cert \
    -days 30 \
    -batch

openssl ca -config /etc/ssl/openssl-ca.cnf \
    -in /etc/pki/CA/docker.au-team.irpo.csr \
    -out /etc/pki/CA/certs/docker.au-team.irpo.crt \
    -extensions server_cert \
    -days 30 \
    -batch

# Копирование сертификатов на BR-SRV
scp -P 2026 /etc/pki/CA/certs/docker.au-team.irpo.crt \
    /etc/pki/CA/private/docker.au-team.irpo.key \
    sshuser@192.168.0.2:/etc/pki/CA/ 2>/dev/null

cp /etc/pki/CA/certs/ca.crt /raid/nfs/ 2>/dev/null

# Настройка Apache для HTTPS
apt-get install -y apache2-mod_ssl
a2enmod ssl

cat > /etc/httpd2/conf/extra/ssl.conf <<'EOF'
Listen 443
<VirtualHost _default_:443>
    DocumentRoot /var/www/html
    ServerName web.au-team.irpo
    SSLEngine on
    SSLCertificateFile /etc/pki/CA/certs/web.au-team.irpo.crt
    SSLCertificateKeyFile /etc/pki/CA/private/web.au-team.irpo.key
</VirtualHost>
EOF

systemctl restart httpd2

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
# 7. Zabbix сервер
# ============================================

apt-get install -y postgresql17-server zabbix-server-pgsql fping

/etc/init.d/postgresql initdb
systemctl enable --now postgresql

su - postgres -c "createuser --no-superuser --no-createdb --no-createrole --encrypted --pwprompt zabbix" <<'EOF'
P@ssw0rd!
P@ssw0rd!
EOF

su - postgres -c "createdb -O zabbix zabbix"

for SCHEMA in /usr/share/doc/zabbix-common-database-pgsql-*/schema.sql; do
    [ -f "$SCHEMA" ] && su - postgres -c "psql -U zabbix -f $SCHEMA zabbix"
done
for IMAGES in /usr/share/doc/zabbix-common-database-pgsql-*/images.sql; do
    [ -f "$IMAGES" ] && su - postgres -c "psql -U zabbix -f $IMAGES zabbix"
done
for DATA in /usr/share/doc/zabbix-common-database-pgsql-*/data.sql; do
    [ -f "$DATA" ] && su - postgres -c "psql -U zabbix -f $DATA zabbix"
done

apt-get install -y apache2 apache2-mod_php8.2
apt-get install -y php8.2 php8.2-mbstring php8.2-sockets php8.2-gd \
    php8.2-xmlreader php8.2-pgsql php8.2-ldap php8.2-openssl

systemctl enable --now httpd2

cat >> /etc/php/8.2/apache2-mod_php/php.ini <<'EOF'
memory_limit = 256M
post_max_size = 32M
max_execution_time = 600
max_input_time = 600
date.timezone = Asia/Yekaterinburg
always_populate_raw_post_data = -1
EOF

systemctl restart httpd2

cat > /etc/zabbix/zabbix_server.conf <<'EOF'
DBHost=localhost
DBName=zabbix
DBUser=zabbix
DBPassword=P@ssw0rd!
EOF

systemctl enable --now zabbix-server

apt-get install -y zabbix-phpfrontend-apache2 zabbix-phpfrontend-php8.2

if [ -f /etc/httpd2/conf/addon.d/A.zabbix.conf ]; then
    ln -sf /etc/httpd2/conf/addon.d/A.zabbix.conf /etc/httpd2/conf/extra-enabled/ 2>/dev/null
fi

# Zabbix Agent на HQ-SRV
apt-get install -y zabbix-agent
cat > /etc/zabbix/zabbix_agentd.conf <<'EOF'
Server=127.0.0.1
ServerActive=127.0.0.1
Hostname=zabbix_server
EOF

systemctl enable --now zabbix-agent

# ============================================
# 9. Fail2ban для SSH
# ============================================

apt-get install -y fail2ban python3-module-systemd

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

systemctl enable --now fail2ban

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

echo "=== HQ-SRV (Модуль 3) готов ==="
