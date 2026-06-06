#!/bin/bash
echo "=== BR-SRV (Модуль 2) ==="

# Проверка и настройка DNS (важно для Samba)
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 77.88.8.8" >> /etc/resolv.conf

# Samba DC — правильная команда provision
apt-get update && apt-get install -y task-samba-dc

rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba/
rm -rf /var/cache/samba/
mkdir -p /var/lib/samba/sysvol

# Правильная команда (без --dns-forwarder)
samba-tool domain provision \
    --realm=AU-TEAM.IRPO \
    --domain=AU-TEAM \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass=P@ssw0rd \
    --use-rfc2307

# Если provision прошёл успешно
if [ -f /var/lib/samba/private/krb5.conf ]; then
    cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
fi

# Настройка DNS через resolv.conf (не через интерфейс, т.к. может не работать)
cat > /etc/resolv.conf <<EOF
search au-team.irpo
nameserver 127.0.0.1
nameserver 8.8.8.8
EOF

# Запуск Samba
systemctl enable --now samba

# Пауза для инициализации Samba
sleep 5

# Проверка, что Samba работает
if ! samba-tool domain info 127.0.0.1 2>/dev/null; then
    echo "Ошибка: Samba DC не запустился. Проверьте логи:"
    systemctl status samba --no-pager
    exit 1
fi

# Группа и пользователи AD
samba-tool group add hq
for i in {1..5}; do
    samba-tool user add hquser$i Password
    samba-tool user setexpiry hquser$i --noexpiry
    samba-tool group addmembers "hq" hquser$i
done

# Docker — если нет интернета, установка пропускается
if ping -c1 8.8.8.8 &>/dev/null; then
    apt-get install -y docker-engine docker-compose-v2
    systemctl enable --now docker
else
    echo "Нет доступа в интернет — установка Docker пропущена"
fi

# Загрузка образов с диска (если есть)
if [ -d /mnt/docker ]; then
    if [ -f /mnt/docker/site_latest.tar ]; then
        docker load < /mnt/docker/site_latest.tar 2>/dev/null || echo "Не удалось загрузить site_latest.tar"
    fi
    if [ -f /mnt/docker/mariadb_latest.tar ]; then
        docker load < /mnt/docker/mariadb_latest.tar 2>/dev/null || echo "Не удалось загрузить mariadb_latest.tar"
    fi
fi

# Docker Compose (только если Docker установлен)
if command -v docker &>/dev/null; then
    cat > /root/compose.yaml <<EOF
services:
  database:
    container_name: db
    image: mariadb:10.11
    restart: always
    ports:
      - "3306:3306"
    environment:
      MARIADB_DATABASE: "testdb"
      MARIADB_USER: "testc"
      MARIADB_PASSWORD: "P@ssw0rd"
      MARIADB_ROOT_PASSWORD: "toor"

  app:
    container_name: testapp
    image: site:latest
    restart: always
    ports:
      - "8080:8080"
    environment:
      DB_TYPE: "maria"
      DB_HOST: "192.168.0.2"
      DB_PORT: "3306"
      DB_NAME: "testdb"
      DB_USER: "testc"
      DB_PASS: "P@ssw0rd"
    depends_on:
      - database
EOF

    docker compose -f /root/compose.yaml up -d
fi

# Ansible (только если есть интернет)
if ping -c1 8.8.8.8 &>/dev/null; then
    apt-get install -y ansible sshpass
    mkdir -p /etc/ansible
    
    cat > /etc/ansible/ansible.cfg <<EOF
[defaults]
inventory = /etc/ansible/hosts
host_key_checking = False
EOF

    cat > /etc/ansible/hosts <<EOF
HQ-SRV ansible_host=192.168.100.2 ansible_user=sshuser ansible_password=P@ssw0rd ansible_port=2026
HQ-CLI ansible_host=192.168.200.2 ansible_user=user ansible_password=resu
HQ-RTR ansible_host=10.10.10.1 ansible_user=user ansible_password=resu
BR-RTR ansible_host=192.168.0.1 ansible_user=user ansible_password=resu

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOF
else
    echo "Нет доступа в интернет — установка Ansible пропущена"
fi

# NTP-клиент (сервер — ISP)
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.2.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

echo "=== BR-SRV готов ==="
