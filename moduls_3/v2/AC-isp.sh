#!/bin/bash
echo "=== ЗАБОР СЕРТИФИКАТОВ ИЗ NFS ==="

# Установка NFS клиента
apt-get update && apt-get install -y nfs-clients

# Создание точки монтирования
mkdir -p /mnt/nfs

# Монтирование NFS
mount -t nfs 192.168.100.2:/raid/nfs /mnt/nfs

# Проверка, что файлы есть
echo "=== Файлы в NFS ==="
ls -la /mnt/nfs/*.cer /mnt/nfs/*.key 2>/dev/null

# Копирование сертификатов
mkdir -p /etc/nginx/ssl
cp /mnt/nfs/web.au-team.irpo.* /etc/nginx/ssl/ 2>/dev/null
cp /mnt/nfs/docker.au-team.irpo.* /etc/nginx/ssl/ 2>/dev/null
cp /mnt/nfs/ca.cer /etc/nginx/ssl/ 2>/dev/null

# Размонтирование
umount /mnt/nfs

echo "=== Сертификаты скопированы в /etc/nginx/ssl ==="
ls -la /etc/nginx/ssl/
