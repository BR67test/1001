#!/bin/bash
echo "=== HQ-SRV (Модуль 2) ==="

# ============================================
# SSH настройка (порт 2026)
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
# RAID0
# ============================================
mdadm --create /dev/md0 -l 0 -n 2 /dev/sdb /dev/sdc --force
mdadm --detail --scan | tee -a /etc/mdadm.conf
mkfs.ext4 /dev/md0
mkdir -p /raid
echo "/dev/md0 /raid ext4 defaults 0 0" >> /etc/fstab
mount -a

# ============================================
# NFS-сервер
# ============================================
apt-get install -y nfs-server
mkdir -p /raid/nfs
chmod 777 /raid/nfs
echo "/raid/nfs 192.168.2.0/28(rw,no_root_squash)" > /etc/exports
systemctl enable --now nfs-server

# ============================================
# LAMP-сервер
# ============================================
apt-get install -y lamp-server
systemctl enable --now mariadb
sleep 5

mariadb -u root <<MYSQL
CREATE DATABASE IF NOT EXISTS webdb;
CREATE USER IF NOT EXISTS 'webc'@'localhost' IDENTIFIED BY 'Password';
GRANT ALL PRIVILEGES ON webdb.* TO 'webc'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL

mount /dev/sr0 /mnt 2>/dev/null
if [ -f /mnt/web/dump.sql ]; then
    mariadb -u webc -pPassword -D webdb < /mnt/web/dump.sql
    cp /mnt/web/index.php /var/www/html/
    cp /mnt/web/logo.png /var/www/html/
fi

if [ -f /var/www/html/index.php ]; then
    sed -i 's/$username = "user"/$username = "webc"/' /var/www/html/index.php
    sed -i 's/$password = "password"/$password = "Password"/' /var/www/html/index.php
    sed -i 's/$dbname = "db"/$dbname = "webdb"/' /var/www/html/index.php
fi

systemctl enable --now httpd2

# ============================================
# NTP-клиент
# ============================================
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.1.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

echo "=== HQ-SRV готов ==="
echo "SSH: port 2026, user: sshuser, password: P@ssw0rd"
