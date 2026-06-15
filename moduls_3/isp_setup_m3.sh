#!/bin/bash
echo "=== ISP (Модуль 3) ==="

apt-get update && apt-get install -y nginx apache2-htpasswd curl

htpasswd -bc /etc/nginx/.htpasswd WEB P@ssw0rd!

scp -P 2026 sshuser@192.168.100.2:/etc/pki/CA/certs/ca.crt /etc/ssl/ 2>/dev/null
scp -P 2026 sshuser@192.168.100.2:/etc/pki/CA/certs/web.au-team.irpo.crt /etc/ssl/ 2>/dev/null
scp -P 2026 sshuser@192.168.100.2:/etc/pki/CA/private/web.au-team.irpo.key /etc/ssl/ 2>/dev/null
scp -P 2026 sshuser@192.168.0.2:/etc/pki/CA/docker.au-team.irpo.crt /etc/ssl/ 2>/dev/null
scp -P 2026 sshuser@192.168.0.2:/etc/pki/CA/docker.au-team.irpo.key /etc/ssl/ 2>/dev/null

cat > /etc/nginx/sites-available.d/default.conf <<'EOF'
server {
    listen 443 ssl;
    server_name web.au-team.irpo;

    ssl_certificate /etc/ssl/web.au-team.irpo.crt;
    ssl_certificate_key /etc/ssl/web.au-team.irpo.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass https://172.16.1.2:443;
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

    ssl_certificate /etc/ssl/docker.au-team.irpo.crt;
    ssl_certificate_key /etc/ssl/docker.au-team.irpo.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass https://172.16.2.2:443;
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

ln -sf /etc/nginx/sites-available.d/default.conf /etc/nginx/sites-enabled.d/

nginx -t
systemctl enable --now nginx
systemctl restart nginx

echo "=== ISP (Модуль 3) готов ==="
