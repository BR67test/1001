#!/bin/bash
echo "=== BR-SRV (Модуль 2) ==="

# ============================================
# 1. Временная настройка DNS для установки
# ============================================
cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 77.88.8.8
EOF

# ============================================
# 2. Настройка времени
# ============================================
timedatectl set-timezone Europe/Moscow

# ============================================
# 3. Установка Samba DC
# ============================================
apt-get update
apt-get install -y task-samba-dc

# Очистка старых конфигураций
rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba/
rm -rf /var/cache/samba/
mkdir -p /var/lib/samba/sysvol

# Provision домена (без --dns-forwarder)
samba-tool domain provision \
    --realm=AU-TEAM.IRPO \
    --domain=AU-TEAM \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="P@ssw0rd" \
    --use-rfc2307 \
    --dns-forwarder=192.168.100.2

# Копирование Kerberos конфигурации
if [ -f /var/lib/samba/private/krb5.conf ]; then
    cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
fi

# Настройка DNS
cat > /etc/resolv.conf <<EOF
search au-team.irpo
nameserver 127.0.0.1
nameserver 8.8.8.8
EOF

# Запуск Samba
systemctl enable --now samba
sleep 5

# ============================================
# 4. Отключение политики сложности паролей
# ============================================
samba-tool domain passwordsettings set --complexity=off
samba-tool domain passwordsettings set --history-length=0
samba-tool domain passwordsettings set --min-pwd-length=3

# ============================================
# 5. Создание группы и пользователей
# ============================================
samba-tool group add hq 2>/dev/null || echo "Группа hq уже существует"

for i in {1..5}; do
    # Сложный пароль для AD
    PASS="P@ssw0rd${i}!"
    
    samba-tool user add hquser$i $PASS 2>/dev/null || echo "Пользователь hquser$i уже существует"
    samba-tool user setexpiry hquser$i --noexpiry
    samba-tool group addmembers "hq" hquser$i
done

echo ""
echo "=== Созданные пользователи ==="
samba-tool group listmembers hq

# ============================================
# 6. Установка Docker и Docker Compose
# ============================================
apt-get install -y docker-engine docker-compose-v2
systemctl enable --now docker

# ============================================
# 7. Монтирование ISO и загрузка Docker образов
# ============================================
# Поиск ISO файла
ISO_PATH=$(find / -name "*.iso" -path "*/Additional*" 2>/dev/null | head -1)

if [ -n "$ISO_PATH" ]; then
    echo "Найден ISO: $ISO_PATH"
    mkdir -p /mnt/additional
    mount -o loop "$ISO_PATH" /mnt/additional
    
    # Загрузка MariaDB
    if [ -f /mnt/additional/docker/mariadb_latest.tar ]; then
        docker load < /mnt/additional/docker/mariadb_latest.tar
    else
        find /mnt/additional -name "*mariadb*.tar" -type f -exec docker load < {} \; 2>/dev/null
    fi
    
    # Загрузка site:latest
    if [ -f /mnt/additional/docker/site_latest.tar ]; then
        docker load < /mnt/additional/docker/site_latest.tar
    else
        find /mnt/additional -name "*site*.tar" -type f -exec docker load < {} \; 2>/dev/null
    fi
else
    echo "ISO с Docker образами не найден. Пропуск загрузки образов."
fi

# ============================================
# 8. Docker Compose
# ============================================
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

# Запуск контейнеров
cd /root
docker compose up -d 2>/dev/null || echo "Ошибка запуска контейнеров. Проверьте образы."

# ============================================
# 9. Установка Ansible
# ============================================
apt-get install -y ansible sshpass

mkdir -p /etc/ansible

cat > /etc/ansible/ansible.cfg <<EOF
[defaults]
inventory = /etc/ansible/hosts
host_key_checking = False
EOF

cat > /etc/ansible/hosts <<EOF
# Все устройства используют порт 2026
HQ-SRV ansible_host=192.168.100.2 ansible_user=sshuser ansible_password=P@ssw0rd ansible_port=2026
HQ-CLI ansible_host=192.168.200.2 ansible_user=sshuser ansible_password=P@ssw0rd ansible_port=2026
BR-SRV ansible_host=192.168.0.2 ansible_user=sshuser ansible_password=P@ssw0rd ansible_port=2026

# Маршрутизаторы (если они Linux с SSH)
HQ-RTR ansible_host=10.10.10.1 ansible_user=net_admin ansible_password=P@ssw0rd ansible_port=2026
BR-RTR ansible_host=10.10.10.2 ansible_user=net_admin ansible_password=P@ssw0rd ansible_port=2026

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOF

# ============================================
# 10. NTP-клиент
# ============================================
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.2.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

# ============================================
# 11. SSH (порт 2026)
# ============================================
useradd sshuser -u 2026 2>/dev/null
echo "sshuser:P@ssw0rd" | chpasswd
usermod -aG wheel sshuser
echo "sshuser ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers

apt-get install -y openssh-server

cat > /etc/openssh/sshd_config <<SSH
Port 2026
MaxAuthTries 2
PermitRootLogin no
AllowUsers sshuser
Banner /etc/openssh/banner
Subsystem sftp /usr/libexec/openssh/sftp-server
SSH

echo "Authorized access only" > /etc/openssh/banner
systemctl restart sshd

# ============================================
# 12. Проверка
# ============================================
echo ""
echo "=== ПРОВЕРКА ==="
echo ""
echo "Samba DC:"
samba-tool domain info 127.0.0.1 2>/dev/null || echo "Ошибка: Samba не запущена"

echo ""
echo "Docker контейнеры:"
docker ps 2>/dev/null || echo "Docker не запущен"

echo ""
echo "Ansible:"
ansible --version 2>/dev/null | head -1 || echo "Ansible не установлен"

echo ""
echo "=== BR-SRV готов ==="
echo ""
echo "Пароли пользователей AD:"
for i in {1..5}; do
    echo "  hquser$i : P@ssw0rd${i}!"
done
