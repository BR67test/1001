#!/bin/bash
echo "=== HQ-SRV (Модуль 2) ==="

# ============================================
# 0. SSH настройка (порт 2026)
# ============================================

apt-get update && apt-get install -y openssh-server

useradd sshuser -u 1010 2>/dev/null
echo "sshuser:P@ssw0rd" | chpasswd
usermod -aG wheel sshuser

cat > /etc/openssh/sshd_config <<EOF
Port 2026
MaxAuthTries 2
PermitRootLogin no
AllowUsers sshuser
Banner /etc/openssh/banner
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF

echo "Authorized access only" > /etc/openssh/banner

systemctl enable --now sshd

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
# 4. Запуск MariaDB и создание БД
# ============================================

systemctl enable --now mariadb
sleep 5

mariadb -u root <<MYSQL
CREATE DATABASE IF NOT EXISTS webdb;
CREATE USER IF NOT EXISTS 'webc'@'localhost' IDENTIFIED BY 'Password';
GRANT ALL PRIVILEGES ON webdb.* TO 'webc'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL

# Импорт дампа (если есть)
if [ -f /mnt/web/dump.sql ]; then
    mariadb -u webc -pPassword -D webdb < /mnt/web/dump.sql
fi

# ============================================
# 5. Запуск Apache
# ============================================

systemctl enable --now httpd2

# ============================================
# 6. Проверка
# ============================================

echo "=== Проверка RAID ==="
df -h /raid

echo "=== Проверка NFS ==="
exportfs -v

echo "=== Проверка MariaDB ==="
mariadb -u webc -pPassword -e "SHOW DATABASES;"

echo "=== Проверка Apache ==="
curl -s http://localhost | head -5

echo "=== HQ-SRV (Модуль 2) готов ==="
echo "SSH: port 2026, user: sshuser, password: P@ssw0rd"
