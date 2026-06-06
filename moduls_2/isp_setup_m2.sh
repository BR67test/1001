#!/bin/bash
echo "=== ISP (Модуль 2) ==="

# NTP-сервер (дополнительно к настройкам модуля 1)
sed -i 's/^#pool/#pool/' /etc/chrony.conf
cat >> /etc/chrony.conf <<EOF
server ntp0.ntp-servers.net iburst prefer minstratum 4
local stratum 5
allow 0.0.0.0/0
EOF
systemctl restart chronyd

# Nginx
apt-get install -y nginx

# Базовая аутентификация
apt-get install -y apache2-htpasswd
htpasswd -bc /etc/nginx/.htpasswd WEB P@ssw0rd

# Настройка Nginx как reverse proxy
cat > /etc/nginx/sites-available.d/default.conf <<EOF
server {
    listen 80;
    server_name web.au-team.irpo;
    location / {
        proxy_pass http://172.16.1.2:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        auth_basic "Restricted area";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}

server {
    listen 80;
    server_name docker.au-team.irpo;
    location / {
        proxy_pass http://172.16.2.2:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

systemctl enable --now nginx

echo "=== ISP готов ==="
