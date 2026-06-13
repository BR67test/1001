#!/bin/bash
set -euo pipefail
echo "[ OK ] Start"

# --- Переменные ---
SAMBA_PASS="P@ssw0rd"
DB_USER="webc"
DB_PASS="P@ssw0rd"
DB_NAME="webdb"
MOUNT_POINT="/raid"
NFS_EXPORT="/raid/nfs"
NFS_NETWORK="192.168.2.0/28"

# --- Флаги ---
PKG_INSTALLED=0
RAID_CREATED=0
NFS_EXPORTED=0
DB_SETUP=0
HTTPD_ENABLED=0

# --- Функция отката ---
rollback() {
  echo "[ INFO ] Rolling back changes..."
  [[ $HTTPD_ENABLED -eq 1 ]] && systemctl disable --now httpd2.service 2>/dev/null || true
  if [[ $DB_SETUP -eq 1 ]]; then
    mariadb -u root -e "DROP DATABASE IF EXISTS $DB_NAME; DROP USER IF EXISTS '$DB_USER'@'localhost';" 2>/dev/null || true
  fi
  if [[ $NFS_EXPORTED -eq 1 ]]; then
    exportfs -u "$NFS_EXPORT" 2>/dev/null || true
    rm -f "$NFS_EXPORT" 2>/dev/null || true
    systemctl disable --now nfs-server.service 2>/dev/null || true
  fi
  if [[ $RAID_CREATED -eq 1 ]]; then
    umount "$MOUNT_POINT" 2>/dev/null || true
    mdadm --stop /dev/md0 2>/dev/null || true
    rmdir "$MOUNT_POINT" 2>/dev/null || true
    sed -i '/\/dev\/md0/d' /etc/fstab 2>/dev/null || true
    sed -i '/ARRAY \/dev\/md0/d' /etc/mdadm.conf 2>/dev/null || true
  fi
  [[ $PKG_INSTALLED -eq 1 ]] && apt-get remove -y nfs-server lamp-server >/dev/null 2>&1 || true
  echo "[ OK ] Rollback completed"
}
fail() { echo "[ ERROR ] $1"; rollback; exit 1; }

[[ $EUID -ne 0 ]] && fail "Root privileges required"

# --- Установка пакетов ---
apt-get update -qq >/dev/null 2>&1 || fail "Failed to update package lists"
apt-get install -y nfs-server lamp-server >/dev/null 2>&1 || fail "Failed to install packages"
PKG_INSTALLED=1

# --- RAID0 ---
mdadm --create /dev/md0 -l 0 -n 2 /dev/sdb /dev/sdc --force >/dev/null 2>&1 || fail "Failed to create RAID"
RAID_CREATED=1
mdadm --detail --scan >> /etc/mdadm.conf 2>/dev/null || fail "Failed to update mdadm.conf"
mkfs.ext4 /dev/md0 >/dev/null 2>&1 || fail "Failed to format RAID"
mkdir -p "$MOUNT_POINT" || fail "Failed to create mount point"
echo "/dev/md0 $MOUNT_POINT ext4 defaults 0 0" >> /etc/fstab || fail "Failed to update fstab"
mount "$MOUNT_POINT" >/dev/null 2>&1 || fail "Failed to mount RAID"

# --- NFS ---
mkdir -p "$NFS_EXPORT" || fail "Failed to create NFS export directory"
chmod -R 777 "$NFS_EXPORT" || fail "Failed to set permissions"
echo "$NFS_EXPORT $NFS_NETWORK(rw,no_root_squash)" > /etc/exports || fail "Failed to write exports"
exportfs -a >/dev/null 2>&1 || fail "Failed to apply exports"
systemctl enable --now nfs-server.service >/dev/null 2>&1 || fail "Failed to start NFS server"
NFS_EXPORTED=1

# --- LAMP ---
systemctl enable --now mariadb.service >/dev/null 2>&1 || fail "Failed to start MariaDB"
sleep 5

mariadb -u root <<'SQL' >/dev/null 2>&1 || fail "Failed to configure database"
CREATE DATABASE IF NOT EXISTS $DB_NAME;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
DB_SETUP=1

mount /dev/sr0 /mnt/ >/dev/null 2>&1 || echo "[ WARNING ] No ISO mounted at /mnt"
if [[ -f /mnt/web/dump.sql ]]; then
  mariadb -u $DB_USER -p$DB_PASS -D $DB_NAME < /mnt/web/dump.sql >/dev/null 2>&1 || echo "[ WARNING ] Failed to import dump"
  cp /mnt/web/index.php /var/www/html/ 2>/dev/null || echo "[ WARNING ] Failed to copy index.php"
  cp /mnt/web/logo.png /var/www/html/ 2>/dev/null || echo "[ WARNING ] Failed to copy logo.png"
fi

if [[ -f /var/www/html/index.php ]]; then
  sed -i "s/\$username = \"user\"/\$username = \"$DB_USER\"/" /var/www/html/index.php
  sed -i "s/\$password = \"password\"/\$password = \"$DB_PASS\"/" /var/www/html/index.php
  sed -i "s/\$dbname = \"db\"/\$dbname = \"$DB_NAME\"/" /var/www/html/index.php
fi

systemctl enable --now httpd2.service >/dev/null 2>&1 || fail "Failed to start HTTP server"
HTTPD_ENABLED=1

umount /mnt/ 2>/dev/null || true

# --- NTP клиент ---
apt-get install -y chrony >/dev/null 2>&1 || fail "Failed to install chrony"
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.1.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd >/dev/null 2>&1

echo "[ OK ] Done"
