#!/bin/bash
echo "=== HQ-SRV (Модуль 3) ==="

# ============================================
# 2. ГОСТ сертификаты
# ============================================

apt-get update && apt-get install -y openssl-gost-engine

control openssl-gost enabled 2>/dev/null || control openssl-gost enable 2>/dev/null

# CA
openssl genpkey -algorithm gost2012_256 -pkeyopt paramset:TCB -out /root/ca.key
openssl req -new -x509 -md_gost12_256 -days 30 -key /root/ca.key -out /root/ca.cer -subj "/CN=hq-srv.au-team.irpo"

# Сертификат web.au-team.irpo
openssl genpkey -algorithm gost2012_256 -pkeyopt paramset:A -out /root/web.au-team.irpo.key
openssl req -new -md_gost12_256 -key /root/web.au-team.irpo.key -out /root/web.au-team.irpo.csr -subj "/CN=web.au-team.irpo"
openssl x509 -req -in /root/web.au-team.irpo.csr -CA /root/ca.cer -CAkey /root/ca.key -CAcreateserial -out /root/web.au-team.irpo.cer -days 30

# Сертификат docker.au-team.irpo
openssl genpkey -algorithm gost2012_256 -pkeyopt paramset:A -out /root/docker.au-team.irpo.key
openssl req -new -md_gost12_256 -key /root/docker.au-team.irpo.key -out /root/docker.au-team.irpo.csr -subj "/CN=docker.au-team.irpo"
openssl x509 -req -in /root/docker.au-team.irpo.csr -CA /root/ca.cer -CAkey /root/ca.key -CAcreateserial -out /root/docker.au-team.irpo.cer -days 30

# Копирование в NFS для HQ-CLI
cp /root/ca.cer /raid/nfs/ 2>/dev/null

# ============================================
# 5. CUPS принт-сервер
# ============================================

apt-get install -y cups cups-pdf
systemctl enable --now cups
cupsctl --share-printers --remote-any
lpadmin -p PDF_Printer -E -v ipp://localhost/printers/PDF -m everywhere 2>/dev/null
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

cat > /etc/logrotate.d/opt-logs <<'EOF'
/opt/*/rsyslog.txt {
    weekly
    minsize 10M
    compress
    missingok
    notifempty
    create 0644 root root
    rotate 4
}
EOF

systemctl restart rsyslog

# ============================================
# 7. Zabbix сервер
# ============================================

apt-get install -y postgresql17-server zabbix-server-pgsql fping

/etc/init.d/postgresql initdb
systemctl enable --now postgresql

su - postgres -c "psql -c \"CREATE USER zabbix WITH PASSWORD 'P@ssw0rd1!';\""
su - postgres -c "psql -c \"CREATE DATABASE zabbix OWNER zabbix;\""

for SCHEMA in /usr/share/doc/zabbix-common-database-pgsql-*/schema.sql; do
    [ -f "$SCHEMA" ] && su - postgres -c "psql -U zabbix -f $SCHEMA zabbix"
done

for IMAGES in /usr/share/doc/zabbix-common-database-pgsql-*/images.sql; do
    [ -f "$IMAGES" ] && su - postgres -c "psql -U zabbix -f $IMAGES zabbix"
done

for DATA in /usr/share/doc/zabbix-common-database-pgsql-*/data.sql; do
    [ -f "$DATA" ] && su - postgres -c "psql -U zabbix -f $DATA zabbix"
done

cat > /etc/zabbix/zabbix_server.conf <<'EOF'
DBHost=localhost
DBName=zabbix
DBUser=zabbix
DBPassword=P@ssw0rd1!
EOF

# Создание service файлов
cat > /lib/systemd/system/zabbix-server.service <<'EOF'
[Unit]
Description=Zabbix Server
After=network.target postgresql.service

[Service]
Type=simple
ExecStart=/usr/sbin/zabbix_server
User=zabbix
Group=zabbix
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now zabbix-server

# Zabbix агент на HQ-SRV
apt-get install -y zabbix-agent
cat > /etc/zabbix/zabbix_agentd.conf <<'EOF'
Server=127.0.0.1
ServerActive=127.0.0.1
Hostname=zabbix_server
EOF

systemctl enable --now zabbix-agent

# Apache для Zabbix
apt-get install -y apache2 apache2-mod_php8.2 php8.2 php8.2-pgsql php8.2-mbstring php8.2-gd
systemctl enable --now httpd2

mkdir -p /etc/httpd2/conf/addon.d
cat > /etc/httpd2/conf/addon.d/zabbix.conf <<'EOF'
Alias /zabbix /var/www/webapps/zabbix/ui
<Directory /var/www/webapps/zabbix/ui>
    Options FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
EOF

systemctl restart httpd2

# ============================================
# 9. Fail2ban
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
# 10. Кибер Бэкап (сервер)
# ============================================

useradd irpoadmin 2>/dev/null
echo "irpoadmin:P@ssw0rd1!" | chpasswd
usermod -aG wheel irpoadmin

echo "=== HQ-SRV (Модуль 3) готов ==="
