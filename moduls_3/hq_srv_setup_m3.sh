#!/bin/bash
echo "=== HQ-SRV (Модуль 3) ==="

# ============================================
# 2. Центр сертификации (CA) + сертификаты
# ============================================

apt-get update && apt-get install -y openssl

mkdir -p /etc/ssl/CA/{certs,crl,newcerts,private}
touch /etc/ssl/CA/index.txt
echo 1000 > /etc/ssl/CA/serial

# Корневой CA
openssl genrsa -out /etc/ssl/CA/private/ca.key 4096
openssl req -new -x509 -days 365 -key /etc/ssl/CA/private/ca.key \
    -out /etc/ssl/CA/certs/ca.crt \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=AU-TEAM/CN=ca.au-team.irpo"

# Сертификат для web.au-team.irpo (HQ-SRV)
openssl genrsa -out /etc/ssl/CA/private/web.key 4096
openssl req -new -key /etc/ssl/CA/private/web.key \
    -out /etc/ssl/CA/web.csr \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=AU-TEAM/CN=web.au-team.irpo"
openssl ca -batch -days 30 -in /etc/ssl/CA/web.csr \
    -out /etc/ssl/CA/certs/web.crt \
    -keyfile /etc/ssl/CA/private/ca.key \
    -cert /etc/ssl/CA/certs/ca.crt

# Сертификат для docker.au-team.irpo (BR-SRV)
openssl genrsa -out /etc/ssl/CA/private/docker.key 4096
openssl req -new -key /etc/ssl/CA/private/docker.key \
    -out /etc/ssl/CA/docker.csr \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=AU-TEAM/CN=docker.au-team.irpo"
openssl ca -batch -days 30 -in /etc/ssl/CA/docker.csr \
    -out /etc/ssl/CA/certs/docker.crt \
    -keyfile /etc/ssl/CA/private/ca.key \
    -cert /etc/ssl/CA/certs/ca.crt

# Копирование сертификатов на BR-SRV
scp -P 2026 /etc/ssl/CA/certs/docker.crt /etc/ssl/CA/private/docker.key \
    sshuser@192.168.0.2:/etc/ssl/

# Настройка Apache для HTTPS
cat >> /etc/httpd2/conf/extra/ssl.conf <<EOF
<VirtualHost _default_:443>
    DocumentRoot /var/www/html
    ServerName web.au-team.irpo
    SSLEngine on
    SSLCertificateFile /etc/ssl/CA/certs/web.crt
    SSLCertificateKeyFile /etc/ssl/CA/private/web.key
</VirtualHost>
EOF

systemctl restart httpd2

# ============================================
# 5. CUPS принт-сервер
# ============================================

apt-get install -y cups cups-pdf
systemctl enable --now cups
lpadmin -p PDF_Printer -E -v ipp://localhost/printers/PDF -m everywhere
cupsenable PDF_Printer
cupsaccept PDF_Printer

# ============================================
# 6. Rsyslog сервер
# ============================================

apt-get install -y rsyslog

cat >> /etc/rsyslog.conf <<EOF

module(load="imtcp")
input(type="imtcp" port="514")

\$template RemoteLogs,"/opt/%HOSTNAME%/%PROGRAMNAME%.log"
*.* ?RemoteLogs
EOF

systemctl restart rsyslog

# Настройка ротации логов
cat > /etc/logrotate.d/opt-logs <<EOF
/opt/*/*.log {
    weekly
    rotate 4
    compress
    size 10M
    missingok
    notifempty
    create 644 root root
}
EOF

# ============================================
# 7. Мониторинг Prometheus + Grafana
# ============================================

# Node Exporter
useradd --no-create-home --shell /bin/false node_exporter
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
tar -xvf node_exporter-1.6.1.linux-amd64.tar.gz
cp node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

cat > /etc/systemd/system/node_exporter.service <<EOF
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

systemctl enable --now node_exporter

# Prometheus
curl -LO https://github.com/prometheus/prometheus/releases/download/v2.50.1/prometheus-2.50.1.linux-amd64.tar.gz
tar -xvf prometheus-2.50.1.linux-amd64.tar.gz
cp prometheus-2.50.1.linux-amd64/prometheus /usr/local/bin/
cp prometheus-2.50.1.linux-amd64/promtool /usr/local/bin/
mkdir -p /etc/prometheus /var/lib/prometheus
cp -r prometheus-2.50.1.linux-amd64/consoles /etc/prometheus
cp -r prometheus-2.50.1.linux-amd64/console_libraries /etc/prometheus

cat > /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'hq-srv'
    static_configs:
      - targets: ['localhost:9100']
  - job_name: 'br-srv'
    static_configs:
      - targets: ['192.168.0.2:9100']
EOF

cat > /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus
After=network.target

[Service]
User=root
Type=simple
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus/

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now prometheus

# Grafana
apt-get install -y grafana
systemctl enable --now grafana-server

# Настройка источника данных Grafana
sleep 10
curl -X POST -H "Content-Type: application/json" \
    -d '{"name":"Prometheus","type":"prometheus","url":"http://localhost:9090","access":"proxy"}' \
    http://admin:admin@localhost:3000/api/datasources 2>/dev/null

# ============================================
# 9. Fail2ban для SSH
# ============================================

apt-get install -y fail2ban

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 60
findtime = 60
maxretry = 3

[sshd]
enabled = true
port = 2026
logpath = /var/log/auth.log
EOF

systemctl enable --now fail2ban

# ============================================
# 10. Кибер Бэкап (сервер управления)
# ============================================

# Монтирование диска с Кибер Бэкап
mount /dev/cdrom /mnt 2>/dev/null || mount /dev/sr0 /mnt 2>/dev/null

if [ -d /mnt/cyberbackup ]; then
    echo "Установка Кибер Бэкап сервера..."
    dpkg -i /mnt/cyberbackup/*.deb 2>/dev/null
    if [ -f /mnt/cyberbackup/install.sh ]; then
        /mnt/cyberbackup/install.sh --mode unattended --admin-password P@ssw0rd
    fi
else
    echo "Диск с Кибер Бэкап не найден"
fi

# Создание пользователя irpoadmin
useradd irpoadmin 2>/dev/null
echo "irpoadmin:P@ssw0rd" | chpasswd
usermod -aG wheel irpoadmin

# Скрипты бэкапа
mkdir -p /opt/backup_scripts

cat > /opt/backup_scripts/backup_etc.sh <<'EOF'
#!/bin/bash
/opt/cyberbackup/bin/cbcmd backup start --plan "Backup_etc" 2>/dev/null
EOF

cat > /opt/backup_scripts/backup_db.sh <<'EOF'
#!/bin/bash
mysqldump -u webc -pPassword webdb > /tmp/webdb_dump.sql
/opt/cyberbackup/bin/cbcmd backup start --plan "Backup_webdb" 2>/dev/null
rm -f /tmp/webdb_dump.sql
EOF

chmod +x /opt/backup_scripts/*.sh

(crontab -l 2>/dev/null; echo "0 2 * * 0 /opt/backup_scripts/backup_etc.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * 0 /opt/backup_scripts/backup_db.sh") | crontab -

# ============================================
# NTP-клиент
# ============================================

sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.1.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

echo "=== HQ-SRV (Модуль 3) готов ==="
