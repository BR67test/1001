#!/bin/bash
echo "=== BR-SRV (Модуль 3) ==="

# ============================================
# 1. Импорт пользователей из users.csv
# ============================================

apt-get update && apt-get install -y dos2unix curl

mount /dev/sr0 /mnt 2>/dev/null

CSV_FILE=""
if [ -f /mnt/Users.csv ]; then
    CSV_FILE="/mnt/Users.csv"
elif [ -f /mnt/users.csv ]; then
    CSV_FILE="/mnt/users.csv"
fi

if [ -n "$CSV_FILE" ]; then
    echo "Импорт пользователей из $CSV_FILE"
    dos2unix "$CSV_FILE" 2>/dev/null
    
    tail -n +2 "$CSV_FILE" | while IFS=',' read -r username password firstName lastName department; do
        username=$(echo "$username" | tr -d '\r')
        password=$(echo "$password" | tr -d '\r')
        firstName=$(echo "$firstName" | tr -d '\r')
        lastName=$(echo "$lastName" | tr -d '\r')
        department=$(echo "$department" | tr -d '\r')
        
        if [ -n "$username" ]; then
            echo "Создание пользователя: $username"
            samba-tool user create "$username" "$password" \
                --given-name="$firstName" \
                --surname="$lastName" \
                --department="$department" \
                --must-change-at-next-login=no 2>/dev/null || echo "Пользователь $username уже существует"
            samba-tool group addmembers "Domain Users" "$username" 2>/dev/null
        fi
    done
fi

# ============================================
# 7. Node Exporter для мониторинга
# ============================================

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
# 7. Zabbix агент
# ============================================

apt-get install -y zabbix-agent

cat > /etc/zabbix/zabbix_agentd.conf <<'EOF'
Server=192.168.100.2
ServerActive=192.168.100.2
Hostname=br-srv.au-team.irpo
EOF

systemctl enable --now zabbix-agent

# ============================================
# 6. Rsyslog клиент
# ============================================

apt-get install -y rsyslog

cat > /etc/rsyslog.d/00_common.conf <<'EOF'
module(load="imuxsock")
module(load="imklog")
module(load="imtcp")

*.* @@192.168.100.2:514
*.warning @@192.168.100.2:514
EOF

systemctl enable --now rsyslog

echo "=== BR-SRV (Модуль 3) готов ==="
