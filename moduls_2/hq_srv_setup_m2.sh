#!/bin/bash
echo "=== HQ-SRV (Модуль 2) ==="

# ============================================
# 1. RAID0 массив
# ============================================
mdadm --create /dev/md0 -l 0 -n 2 /dev/sdb /dev/sdc --force
mdadm --detail --scan | tee -a /etc/mdadm.conf
mkfs.ext4 /dev/md0
mkdir -p /raid
echo "/dev/md0 /raid ext4 defaults 0 0" >> /etc/fstab
mount -a

# ============================================
# 2. NFS-сервер
# ============================================
apt-get update
apt-get install -y nfs-server
mkdir -p /raid/nfs
chmod 777 /raid/nfs
echo "/raid/nfs *(rw,sync,no_subtree_check)" >> /etc/exports
systemctl enable --now nfs-server

# ============================================
# 3. LAMP-сервер
# ============================================
apt-get install -y lamp-server

# ============================================
# 4. Запуск MariaDB и ожидание
# ============================================
systemctl enable --now mariadb
sleep 5

# Проверка что MariaDB работает
for i in {1..10}; do
    if mariadb -u root -e "SELECT 1" &>/dev/null; then
        echo "MariaDB запущена"
        break
    fi
    echo "Ожидание запуска MariaDB... ($i/10)"
    sleep 3
done

# ============================================
# 5. Копирование файлов с ISO (если смонтирован)
# ============================================
if [ -d /mnt/web ]; then
    cp /mnt/web/index.php /var/www/html/ 2>/dev/null
    cp /mnt/web/logo.png /var/www/html/ 2>/dev/null
    cp /mnt/web/dump.sql /tmp/ 2>/dev/null
fi

# ============================================
# 6. Настройка PHP файла
# ============================================
if [ -f /var/www/html/index.php ]; then
    sed -i 's/$username = "user"/$username = "webc"/' /var/www/html/index.php
    sed -i 's/$password = "password"/$password = "Password"/' /var/www/html/index.php
    sed -i 's/$dbname = "db"/$dbname = "webdb"/' /var/www/html/index.php
fi

# ============================================
# 7. Настройка MariaDB (БД и пользователь)
# ============================================
mariadb -u root <<MYSQL
CREATE DATABASE IF NOT EXISTS webdb;
CREATE USER IF NOT EXISTS 'webc'@'localhost' IDENTIFIED BY 'Password';
GRANT ALL PRIVILEGES ON webdb.* TO 'webc'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL

# Импорт дампа
if [ -f /tmp/dump.sql ]; then
    mariadb -u webc -pPassword -D webdb < /tmp/dump.sql 2>/dev/null
    echo "Дамп БД импортирован"
fi

# ============================================
# 8. Запуск Apache
# ============================================
systemctl enable --now httpd2

# ============================================
# 9. NTP-клиент
# ============================================
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.1.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

# ============================================
# 10. Проверка
# ============================================
echo ""
echo "=== ПРОВЕРКА ==="
echo ""

echo "RAID:"
df -h /raid 2>/dev/null | tail -1

echo ""
echo "NFS:"
exportfs -v 2>/dev/null | head -3

echo ""
echo "MariaDB:"
mariadb -u webc -pPassword -e "SHOW DATABASES;" 2>/dev/null

echo ""
echo "Apache:"
systemctl is-active httpd2

echo ""
echo "=== HQ-SRV готов ==="
