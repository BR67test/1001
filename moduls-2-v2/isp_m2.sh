#!/bin/bash
set -euo pipefail
echo "[ OK ] Start"

# --- IP адреса маршрутизаторов ---
HQ_RTR_IP="172.16.1.10"
BR_RTR_IP="172.16.2.10"

# --- Флаги ---
PKG_INSTALLED=0

# --- Функция отката ---
rollback() {
  echo "[ INFO ] Rolling back changes..."
  if [[ $PKG_INSTALLED -eq 1 ]]; then
    apt-get remove -y nginx apache2-htpasswd >/dev/null 2>&1 || true
  fi
  rm -f /etc/nginx/sites-available.d/default.conf 2>/dev/null || true
  rm -f /etc/nginx/.htpasswd 2>/dev/null || true
  echo "[ OK ] Rollback completed"
}
fail() { echo "[ ERROR ] $1"; rollback; exit 1; }

[[ $EUID -ne 0 ]] && fail "Root privileges required"

# --- Установка пакетов ---
apt-get update -qq >/dev/null 2>&1 || fail "Failed to update package lists"
apt-get install -y nginx apache2-htpasswd >/dev/null 2>&1 || fail "Failed to install packages"
PKG_INSTALLED=1

# --- Аутентификация ---
htpasswd -bc /etc/nginx/.htpasswd WEB P@ssw0rd >/dev/null 2>&1 || fail "Failed to create htpasswd"

# --- Nginx reverse proxy ---
cat > /etc/nginx/sites-available.d/default.conf <<'EOF' || fail "Failed to write nginx config"
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
systemctl enable --now nginx.service >/dev/null 2>&1 || fail "Failed to start nginx"

echo "[ OK ] Done"
