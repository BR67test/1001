#!/bin/bash
echo "=== ISP (Модуль 2) ==="

# ============================================
# Установка nginx и htpasswd
# ============================================
apt-get update && apt-get install -y nginx apache2-htpasswd mc

htpasswd -bc /etc/nginx/.htpasswd WEB P@ssw0rd

# ============================================
# Настройка nginx как reverse proxy
# ============================================
cat > /etc/nginx/sites-available.d/default.conf <<'EOF'
server {
    listen 80;
    server_name web.au-team.irpo;

    location / {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://172.16.1.10:8080;
        auth_basic "Restricted area";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}

server {
    listen 80;
    server_name docker.au-team.irpo;

    location / {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://172.16.2.10:8080;
    }
}
EOF

ln -sf /etc/nginx/sites-available.d/default.conf /etc/nginx/sites-enabled.d/

# ============================================
# NTP-сервер
# ============================================
apt-get install -y chrony tzdata
cat > /etc/chrony.conf <<EOF
initstepslew 10 ntp0.ntp-servers.net
pool 127.0.0.1 iburst prefer
hwtimestamp *
local stratum 5
allow 0/0
EOF

systemctl restart chronyd
systemctl enable --now chronyd
timedatectl set-timezone Asia/Yekaterinburg

# ============================================
# Запуск nginx
# ============================================
systemctl enable --now nginx
systemctl restart nginx

echo "=== ISP готов ==="
