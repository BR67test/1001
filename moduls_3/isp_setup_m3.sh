#!/bin/bash
echo "=== ISP (Модуль 3) ==="

# ============================================
# 2. Настройка nginx для HTTPS проксирования
# ============================================

apt-get update && apt-get install -y nginx

cat > /etc/nginx/sites-available.d/default.conf <<EOF
server {
    listen 443 ssl;
    server_name web.au-team.irpo;

    ssl_certificate /etc/ssl/CA/certs/web.crt;
    ssl_certificate_key /etc/ssl/CA/private/web.key;

    location / {
        proxy_pass https://172.16.1.2:443;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 443 ssl;
    server_name docker.au-team.irpo;

    ssl_certificate /etc/ssl/CA/certs/docker.crt;
    ssl_certificate_key /etc/ssl/CA/private/docker.key;

    location / {
        proxy_pass https://172.16.2.2:443;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Редирект HTTP → HTTPS
server {
    listen 80;
    server_name web.au-team.irpo docker.au-team.irpo;
    return 301 https://\$server_name\$request_uri;
}
EOF

nginx -t
systemctl enable --now nginx

echo "=== ISP (Модуль 3) готов ==="
