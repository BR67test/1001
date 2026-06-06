#!/bin/bash
echo "=== HQ-SRV (Модуль 2) ==="

# RAID0
mdadm --create /dev/md0 -l 0 -n 2 /dev/sdb /dev/sdc --force
mdadm --detail --scan | tee -a /etc/mdadm.conf
mkfs.ext4 /dev/md0
mkdir -p /raid
echo "/dev/md0 /raid ext4 defaults 0 0" >> /etc/fstab
mount -a

# NFS-сервер
apt-get install -y nfs-server
mkdir -p /raid/nfs
chmod 777 /raid/nfs
echo "/raid/nfs *(rw,sync,no_subtree_check)" >> /etc/exports
systemctl enable --now nfs-server

# LAMP-сервер
apt-get install -y lamp-server

# Копирование файлов с Additional.iso
if [ -d /mnt/web ]; then
    cp /mnt/web/index.php /var/www/html/ 2>/dev/null
    cp /mnt/web/logo.png /var/www/html/ 2>/dev/null
    cp /mnt/web/dump.sql /tmp/ 2>/dev/null
fi

# Настройка PHP-подключения к БД
if [ -f /var/www/html/index.php ]; then
    sed -i 's/$username = "user"/$username = "webc"/' /var/www/html/index.php
    sed -i 's/$password = "password"/$password = "Password"/' /var/www/html/index.php
    sed -i 's/$dbname = "db"/$dbname = "webdb"/' /var/www/html/index.php
fi

# MariaDB
systemctl enable --now mariadb

mariadb -u root <<MYSQL
CREATE DATABASE webdb;
CREATE USER 'webc'@'localhost' IDENTIFIED BY 'Password';
GRANT ALL PRIVILEGES ON webdb.* TO 'webc'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL

if [ -f /tmp/dump.sql ]; then
    mariadb -u webc -pPassword -D webdb < /tmp/dump.sql
fi

# Apache
systemctl enable --now httpd2

# NTP-клиент
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.1.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

echo "=== HQ-SRV готов ==="
