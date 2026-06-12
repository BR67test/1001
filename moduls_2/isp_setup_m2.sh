#!/bin/bash
echo "=== ISP (Модуль 2) ==="

apt-get update && apt-get install -y nginx apache2-htpasswd

htpasswd -bc /etc/nginx/.htpasswd WEB P@ssw0rd

cat > /etc/nginx/sites-available.d/default.conf <<'EOF'
server {
    listen 80;
    server_name web.au-team.irpo;
    location / {
        proxy_pass http://172.16.1.10:8080;
        proxy_set_header Host $host;
        auth_basic "Restricted area";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}

server {
    listen 80;
    server_name docker.au-team.irpo;
    location / {
        proxy_pass http://172.16.2.10:8080;
        proxy_set_header Host $host;
    }
}
EOF

ln -sf /etc/nginx/sites-available.d/default.conf /etc/nginx/sites-enabled.d/
systemctl enable --now nginx
systemctl restart nginx

echo "=== ISP готов ==="
