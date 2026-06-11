#!/bin/bash
echo "=== BR-SRV (Модуль 2) ==="

# ============================================
# 0. SSH настройка (порт 2026)
# ============================================

apt-get update && apt-get install -y openssh-server

useradd sshuser -u 2026 2>/dev/null
echo "sshuser:P@ssw0rd" | chpasswd
usermod -aG wheel sshuser

cat > /etc/openssh/sshd_config <<EOF
Port 2026
MaxAuthTries 3
PermitRootLogin no
AllowUsers sshuser
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF

systemctl enable --now sshd

# ============================================
# 1. Установка Samba DC
# ============================================

apt-get install -y task-samba-dc

# Очистка старых конфигов
rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba/
rm -rf /var/cache/samba/
mkdir -p /var/lib/samba/sysvol

# Provision домена
samba-tool domain provision \
    --realm=AU-TEAM.IRPO \
    --domain=AU-TEAM \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass='P@ssw0rd' \
    --use-rfc2307

# Копирование Kerberos конфига
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

# Настройка DNS
cat > /etc/net/ifaces/enp7s1/resolv.conf <<EOF
search au-team.irpo
nameserver 127.0.0.1
EOF

systemctl restart network

# Запуск Samba
systemctl enable --now samba
sleep 5

# ============================================
# 2. Проверка Samba
# ============================================

echo "=== Проверка Samba ==="
samba-tool domain info 127.0.0.1

# Проверка Kerberos
echo "P@ssw0rd" | kinit Administrator@AU-TEAM.IRPO
klist

# ============================================
# 3. Отключение политики сложности паролей
# ============================================

samba-tool domain passwordsettings set --complexity=off
samba-tool domain passwordsettings set --history-length=0
samba-tool domain passwordsettings set --min-pwd-length=3

# ============================================
# 4. Создание группы и пользователей
# ============================================

samba-tool group add hq

for i in {1..5}; do
    samba-tool user add "hquser$i" "P@ssw0rd${i}!"
    samba-tool user setexpiry "hquser$i" --noexpiry
    samba-tool group addmembers "hq" "hquser$i"
done

echo "=== Созданные пользователи ==="
samba-tool group listmembers hq

# ============================================
# 5. Установка Docker
# ============================================

apt-get install -y docker-engine docker-compose-v2
systemctl enable --now docker

# ============================================
# 6. Загрузка Docker образов с ISO
# ============================================

ISO_PATH=$(find / -name "*.iso" 2>/dev/null | head -1)
if [ -n "$ISO_PATH" ]; then
    mkdir -p /mnt/iso
    mount -o loop "$ISO_PATH" /mnt/iso 2>/dev/null
fi

if [ -f /mnt/iso/docker/site_latest.tar ]; then
    docker load < /mnt/iso/docker/site_latest.tar
fi
if [ -f /mnt/iso/docker/mariadb_latest.tar ]; then
    docker load < /mnt/iso/docker/mariadb_latest.tar
fi

# ============================================
# 7. Docker Compose
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

cd /root
docker compose up -d

# ============================================
# 8. Проверка
# ============================================

echo "=== Проверка Docker ==="
docker ps

echo "=== Проверка приложения ==="
curl -s http://localhost:8080 | head -5

echo "=== BR-SRV (Модуль 2) готов ==="
echo "SSH: port 2026, user: sshuser, password: P@ssw0rd"
echo "Пароли пользователей AD:"
for i in {1..5}; do
    echo "  hquser$i : P@ssw0rd${i}!"
done
