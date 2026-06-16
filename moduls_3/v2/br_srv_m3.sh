#!/bin/bash
echo "=== BR-SRV (Модуль 3) ==="

# ============================================
# 1. Импорт пользователей из Users.csv
# ============================================

apt-get update && apt-get install -y dos2unix curl

mount /dev/sr0 /mnt 2>/dev/null

CSV_FILE=""
if [ -f /mnt/Users.csv ]; then
    CSV_FILE="/mnt/Users.csv"
elif [ -f /mnt/Users.csu ]; then
    CSV_FILE="/mnt/Users.csu"
fi

if [ -n "$CSV_FILE" ]; then
    echo "Импорт пользователей из $CSV_FILE"
    dos2unix "$CSV_FILE" 2>/dev/null
    
    # Создание OU
    awk -F ';' 'NR>1 {print $5}' "$CSV_FILE" | sort | uniq | while read ou; do
        if [ -n "$ou" ] && [ "$ou" != "OU" ]; then
            samba-tool ou add "OU=$ou,DC=au-team,DC=irpo" 2>/dev/null || echo "OU $ou уже существует"
        fi
    done

    # Создание пользователей
    tail -n +2 "$CSV_FILE" | while IFS=';' read -r firstName lastName role phone ou street zip city country password garbage; do
        firstName=$(echo "$firstName" | tr -d '\r')
        lastName=$(echo "$lastName" | tr -d '\r')
        ou=$(echo "$ou" | tr -d '\r')
        password=$(echo "$password" | tr -d '\r')
        role=$(echo "$role" | tr -d '\r')
        phone=$(echo "$phone" | tr -d '\r')
        
        if [ -z "$firstName" ] || [ "$firstName" = "First Name" ]; then
            continue
        fi
        
        username=$(echo "${firstName,,}.${lastName,,}" | sed 's/[^a-z0-9.-]//g')
        
        echo "Создание: $username ($firstName $lastName)"
        
        samba-tool user add "$username" "$password" \
            --given-name="$firstName" \
            --surname="$lastName" \
            --telephone-number="$phone" \
            --job-title="$role" \
            --userou="OU=$ou" 2>/dev/null || echo "  -> Пользователь уже существует"
        
        samba-tool user setexpiry "$username" --noexpiry 2>/dev/null
        samba-tool group addmembers "Domain Users" "$username" 2>/dev/null
    done
    echo "=== Импорт пользователей завершён ==="
else
    echo "Файл Users.csv не найден, импорт пропущен"
fi

# ============================================
# 6. Rsyslog клиент
# ============================================

apt-get install -y rsyslog

cat > /etc/rsyslog.d/00_common.conf <<'EOF'
module(load="imuxsock")
module(load="imklog")
module(load="imtcp")
*.warning @@192.168.100.2:514
EOF

systemctl enable --now rsyslog

# ============================================
# 7. Node Exporter
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

echo "=== BR-SRV (Модуль 3) готов ==="
