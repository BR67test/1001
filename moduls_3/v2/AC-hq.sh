#!/bin/bash
echo "=== КОПИРОВАНИЕ СЕРТИФИКАТОВ В NFS ==="

# Проверка, что сертификаты есть
if [ ! -f /root/web.au-team.irpo.cer ]; then
    echo "Ошибка: сертификаты не найдены в /root"
    echo "Сначала создайте сертификаты на HQ-SRV"
    exit 1
fi

# Копирование в NFS
cp /root/web.au-team.irpo.* /raid/nfs/ 2>/dev/null
cp /root/docker.au-team.irpo.* /raid/nfs/ 2>/dev/null
cp /root/ca.cer /raid/nfs/ 2>/dev/null

echo "=== Сертификаты скопированы в /raid/nfs ==="
ls -la /raid/nfs/*.cer /raid/nfs/*.key 2>/dev/null
