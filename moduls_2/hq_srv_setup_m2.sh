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
chmod 766 /raid/nfs
echo "/raid/nfs 192.168.2.0/28(rw,no_subtree_check,no_root_squash)" > /etc/exports
exportfs -arv
systemctl enable --now nfs-server

# ============================================
# LAMP-сервер
# ============================================
apt-get install -y apache2 mariadb php8.2 apache2-mod_php8.2 php8.2-mysqli
systemctl enable --now httpd2 mariadb
sleep 5

# Копирование файлов с ISO
mount /dev/sr0 /mnt 2>/dev/null
if [ -f /mnt/web/dump.sql ]; then
    cp /mnt/web/index.php /var/www/html/
    cp /mnt/web/logo.png /var/www/html/
    
    # Импорт БД
    mysql -u root -e "CREATE DATABASE webdb;"
    mysql -u root webdb < /mnt/web/dump.sql
    mysql -u root -e "CREATE USER 'web'@'localhost' IDENTIFIED BY 'P@ssw0rd';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON webdb.* TO 'web'@'localhost';"
    mysql -u root -e "FLUSH PRIVILEGES;"
fi

# Настройка index.php
if [ -f /var/www/html/index.php ]; then
    sed -i 's/$username = "user"/$username = "web"/' /var/www/html/index.php
    sed -i 's/$password = "password"/$password = "P@ssw0rd"/' /var/www/html/index.php
    sed -i 's/$dbname = "db"/$dbname = "webdb"/' /var/www/html/index.php
fi

# Права на файлы
chown -R apache2:webmaster /var/www/html/
chmod 755 /var/www/html/

systemctl restart httpd2 mariadb

# ============================================
# NTP-клиент
# ============================================
apt-get install -y chrony
cat > /etc/chrony.conf <<EOF
pool 172.16.1.1 iburst prefer
EOF
systemctl restart chronyd
systemctl enable --now chronyd
timedatectl set-timezone Asia/Yekaterinburg

# ============================================
# Удаление стандартного index.html и настройка DirectoryIndex
# ============================================

# Удаляем стандартную заглушку Apache
rm -f /var/www/html/index.html

# Настраиваем DirectoryIndex (index.php имеет приоритет)
mkdir -p /etc/httpd2/conf/extra
cat > /etc/httpd2/conf/extra/dir.conf <<'EOF'
DirectoryIndex index.php index.html
EOF

# Подключаем конфиг, если ещё не подключён
grep -q "Include conf/extra/dir.conf" /etc/httpd2/conf/httpd2.conf || echo "Include conf/extra/dir.conf" >> /etc/httpd2/conf/httpd2.conf

# Перезапускаем Apache
systemctl restart httpd2

echo "=== HQ-SRV готов ==="
echo "SSH: port 2026, user: sshuser, password: P@ssw0rd"
