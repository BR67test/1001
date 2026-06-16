#!/bin/bash
echo "=== ДОПОЛНИТЕЛЬНО: НАСТРОЙКА ISP С СЕРТИФИКАТАМИ ==="

# ============================================
# 1. Установка пакетов
# ============================================

apt-get update && apt-get install -y nginx apache2-htpasswd openssl-gost-engine

control openssl-gost enabled 2>/dev/null || control openssl-gost enable 2>/dev/null

# ============================================
# 2. Копирование сертификатов
# ============================================

mkdir -p /etc/nginx/ssl

# Проверка наличия сертификатов в /root
if [ -f /root/web.au-team.irpo.cer ]; then
    cp /root/web.au-team.irpo.* /etc/nginx/ssl/
    echo "Сертификат web.au-team.irpo скопирован"
else
    echo "Ошибка: сертификат web.au-team.irpo.cer не найден в /root"
    echo "Сначала запусти скрипт на HQ-SRV"
    exit 1
fi

if [ -f /root/docker.au-team.irpo.cer ]; then
    cp /root/docker.au-team.irpo.* /etc/nginx/ssl/
    echo "Сертификат docker.au-team.irpo скопирован"
else
    echo "Ошибка: сертификат docker.au-team.irpo.cer не найден в /root"
    exit 1
fi

ls -la /etc/nginx/ssl/

# ============================================
# 3. Аутентификация
# ============================================

htpasswd -bc /etc/nginx/.htpasswd WEB P@ssw0rd1!

# ============================================
# 4. Настройка nginx
# ============================================

cat > /etc/nginx/sites-available.d/default.conf <<'EOF'
server {
    listen 443 ssl;
    server_name web.au-team.irpo;
    ssl_certificate /etc/nginx/ssl/web.au-team.irpo.cer;
    ssl_certificate_key /etc/nginx/ssl/web.au-team.irpo.key;
    ssl_ciphers GOST2012-GOST8912-GOST8912:HIGH:MEDIUM;
    ssl_protocols TLSv1.2 TLSv1.3;
    location / {
        proxy_pass http://172.16.1.10:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        auth_basic "Restricted area";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}

server {
    listen 443 ssl;
    server_name docker.au-team.irpo;
    ssl_certificate /etc/nginx/ssl/docker.au-team.irpo.cer;
    ssl_certificate_key /etc/nginx/ssl/docker.au-team.irpo.key;
    ssl_ciphers GOST2012-GOST8912-GOST8912:HIGH:MEDIUM;
    ssl_protocols TLSv1.2 TLSv1.3;
    location / {
        proxy_pass http://172.16.2.10:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80;
    server_name web.au-team.irpo docker.au-team.irpo;
    return 301 https://$server_name$request_uri;
}
EOF

# ============================================
# 5. Запуск nginx
# ============================================

ln -sf /etc/nginx/sites-available.d/default.conf /etc/nginx/sites-enabled.d/
nginx -t
systemctl restart nginx

echo "=== ISP готов ==="
echo "Проверка: curl -k https://web.au-team.irpo"
