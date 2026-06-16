#!/bin/bash
echo "=== ДОПОЛНИТЕЛЬНО: СОЗДАНИЕ И КОПИРОВАНИЕ СЕРТИФИКАТОВ ==="

# ============================================
# 1. Проверка и создание сертификатов
# ============================================

cd /root

if [ ! -f /root/ca.cer ]; then
    echo "Создание CA сертификата..."
    openssl genpkey -algorithm gost2012_256 -pkeyopt paramset:TCB -out ca.key
    openssl req -new -x509 -md_gost12_256 -days 30 -key ca.key -out ca.cer -subj "/CN=hq-srv.au-team.irpo"
fi

if [ ! -f /root/web.au-team.irpo.cer ]; then
    echo "Создание сертификата web.au-team.irpo..."
    openssl genpkey -algorithm gost2012_256 -pkeyopt paramset:A -out web.au-team.irpo.key
    openssl req -new -md_gost12_256 -key web.au-team.irpo.key -out web.au-team.irpo.csr -subj "/CN=web.au-team.irpo"
    openssl x509 -req -in web.au-team.irpo.csr -CA ca.cer -CAkey ca.key -CAcreateserial -out web.au-team.irpo.cer -days 30
fi

if [ ! -f /root/docker.au-team.irpo.cer ]; then
    echo "Создание сертификата docker.au-team.irpo..."
    openssl genpkey -algorithm gost2012_256 -pkeyopt paramset:A -out docker.au-team.irpo.key
    openssl req -new -md_gost12_256 -key docker.au-team.irpo.key -out docker.au-team.irpo.csr -subj "/CN=docker.au-team.irpo"
    openssl x509 -req -in docker.au-team.irpo.csr -CA ca.cer -CAkey ca.key -CAcreateserial -out docker.au-team.irpo.cer -days 30
fi

echo "=== Сертификаты на HQ-SRV ==="
ls -la /root/*.cer /root/*.key 2>/dev/null

# ============================================
# 2. Копирование в NFS для HQ-CLI
# ============================================

cp /root/ca.cer /raid/nfs/ 2>/dev/null
echo "CA сертификат скопирован в NFS"

# ============================================
# 3. Копирование на ISP
# ============================================

echo "=== Копирование сертификатов на ISP ==="

# Проверка доступности ISP
ping -c1 172.16.1.1 2>/dev/null || echo "ISP недоступен, проверь сеть"

scp -o StrictHostKeyChecking=no /root/web.au-team.irpo.* root@172.16.1.1:/root/ 2>/dev/null
scp -o StrictHostKeyChecking=no /root/docker.au-team.irpo.* root@172.16.1.1:/root/ 2>/dev/null
scp -o StrictHostKeyChecking=no /root/ca.cer root@172.16.1.1:/root/ 2>/dev/null

echo "=== Копирование завершено ==="
