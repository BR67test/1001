#!/bin/bash
echo "=== BR-SRV (Модуль 3) ==="

# ============================================
# 1. Импорт пользователей из Users.csu
# ============================================

apt-get update && apt-get install -y dos2unix curl

mount /dev/sr0 /mnt 2>/dev/null

CSV_FILE=""
if [ -f /mnt/Users.csu ]; then
    CSV_FILE="/mnt/Users.csu"
elif [ -f /mnt/Users.csv ]; then
    CSV_FILE="/mnt/Users.csv"
fi

if [ -n "$CSV_FILE" ]; then
    echo "Импорт пользователей из $CSV_FILE"
    dos2unix "$CSV_FILE" 2>/dev/null
    
    # Пропускаем заголовок, читаем с разделителем ;
    tail -n +2 "$CSV_FILE" | while IFS=';' read -r firstName lastName role phone ou street zip postalCode city country password garbage; do
        # Удаляем \r из конца строки
        firstName=$(echo "$firstName" | tr -d '\r')
        lastName=$(echo "$lastName" | tr -d '\r')
        role=$(echo "$role" | tr -d '\r')
        phone=$(echo "$phone" | tr -d '\r')
        ou=$(echo "$ou" | tr -d '\r')
        street=$(echo "$street" | tr -d '\r')
        zip=$(echo "$zip" | tr -d '\r')
        postalCode=$(echo "$postalCode" | tr -d '\r')
        city=$(echo "$city" | tr -d '\r')
        country=$(echo "$country" | tr -d '\r')
        password=$(echo "$password" | tr -d '\r')
        
        # Формируем имя пользователя из firstName + lastName
        username=$(echo "${firstName}${lastName}" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
        
        if [ -n "$username" ] && [ "$firstName" != "First Name" ]; then
            echo "Создание пользователя: $username ($firstName $lastName)"
            
            samba-tool user create "$username" "$password" \
                --given-name="$firstName" \
                --surname="$lastName" \
                --department="$ou" \
                --must-change-at-next-login=no 2>/dev/null || echo "  -> Пользователь уже существует"
            
            samba-tool group addmembers "Domain Users" "$username" 2>/dev/null
        fi
    done
    echo "=== Импорт пользователей завершён ==="
else
    echo "Файл Users.csu не найден, импорт пропущен"
fi

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

# ============================================
# 7. Node Exporter для мониторинга (Prometheus)
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
# 7. Zabbix агент (альтернативный мониторинг)
# ============================================

apt-get install -y zabbix-agent

cat > /etc/zabbix/zabbix_agentd.conf <<'EOF'
Server=192.168.100.2
ServerActive=192.168.100.2
Hostname=br-srv.au-team.irpo
EOF

systemctl enable --now zabbix-agent

# ============================================
# 8. Ansible инвентаризация
# ============================================

mkdir -p /etc/ansible/PC_INFO

apt-get install -y ansible

cat > /etc/ansible/inventory.yml <<'EOF'
---
- name: Инвентаризация машин HQ-SRV и HQ-CLI
  hosts: hq-srv,hq-cli
  gather_facts: yes
  vars:
    ansible_python_interpreter: /usr/bin/python3
  tasks:
    - name: Сбор информации о хосте
      set_fact:
        host_info:
          name: "{{ ansible_hostname }}"
          ip: "{{ ansible_default_ipv4.address | default('N/A') }}"

    - name: Сохранение информации в файл
      copy:
        content: |
          ---
          hostname: {{ host_info.name }}
          ip_address: {{ host_info.ip }}
          timestamp: "{{ ansible_date_time.iso8601 }}"
        dest: "/etc/ansible/PC_INFO/{{ host_info.name }}.yml"
      delegate_to: localhost
      run_once: true
EOF

cat > /etc/ansible/hosts <<'EOF'
[hq-srv]
192.168.100.2 ansible_user=sshuser ansible_password=P@ssw0rd! ansible_port=2026

[hq-cli]
192.168.200.4 ansible_user=sshuser ansible_password=P@ssw0rd! ansible_port=2026
EOF

cat > /etc/ansible/ansible.cfg <<'EOF'
[defaults]
host_key_checking = False
inventory = /etc/ansible/hosts
interpreter_python = /usr/bin/python3
EOF

# Запуск плейбука
ansible-playbook /etc/ansible/inventory.yml 2>/dev/null

echo "=== Отчёты Ansible в /etc/ansible/PC_INFO/ ==="
ls -la /etc/ansible/PC_INFO/ 2>/dev/null

# ============================================
# Копирование CA сертификата для HQ-CLI (через NFS)
# ============================================

# Ожидаем, что NFS шара смонтирована с HQ-SRV
if [ -d /mnt/nfs ]; then
    echo "NFS доступен"
fi

echo "=== BR-SRV (Модуль 3) готов ==="
