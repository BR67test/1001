#!/bin/bash
set -euo pipefail
echo "[ OK ] Start"

# --- Переменные ---
SAMBA_REALM="AU-TEAM.IRPO"
SAMBA_DOMAIN="AU-TEAM"
SAMBA_PASS="P@ssw0rd"
HOSTNAME="br-srv.au-team.irpo"
ENP7S1_RESOLV="/etc/net/ifaces/enp7s1/resolv.conf"
DOCKER_COMPOSE_FILE="/root/compose.yaml"
ORIG_HOSTNAME=$(hostname)

# --- Флаги для отката ---
PKG_INSTALLED=0
RESOLV_BACKED_UP=0
SAMBA_PROVISIONED=0
DOCKER_COMPOSE_CREATED=0
CONTAINERS_RUNNING=0

# --- Функция отката ---
rollback() {
  echo "[ INFO ] Rolling back changes..."
  if [[ $CONTAINERS_RUNNING -eq 1 ]]; then
    docker compose -f "$DOCKER_COMPOSE_FILE" down -v --rmi all --remove-orphans >/dev/null 2>&1 || true
  fi
  if [[ $DOCKER_COMPOSE_CREATED -eq 1 ]]; then
    rm -f "$DOCKER_COMPOSE_FILE" 2>/dev/null || true
  fi
  if [[ $SAMBA_PROVISIONED -eq 1 ]]; then
    systemctl stop samba.service 2>/dev/null || true
    systemctl disable samba.service 2>/dev/null || true
    rm -rf /var/lib/samba/ /var/cache/samba/ 2>/dev/null || true
    rm -f /etc/samba/smb.conf 2>/dev/null || true
  fi
  if [[ $RESOLV_BACKED_UP -eq 1 ]]; then
    mv -f "${ENP7S1_RESOLV}.bak" "$ENP7S1_RESOLV" 2>/dev/null || true
  fi
  if [[ $PKG_INSTALLED -eq 1 ]]; then
    apt-get remove -y task-samba-dc docker-engine docker-compose-v2 ansible sshpass >/dev/null 2>&1 || true
  fi
  hostnamectl set-hostname "$ORIG_HOSTNAME" 2>/dev/null || true
  echo "127.0.0.1 localhost" > /etc/hosts 2>/dev/null || true
  systemctl restart network >/dev/null 2>&1 || true
  echo "[ OK ] Rollback completed"
}
fail() { echo "[ ERROR ] $1"; rollback; exit 1; }

# --- Проверка прав ---
[[ $EUID -ne 0 ]] && fail "Root privileges required"

# --- Установка пакетов ---
apt-get update -qq >/dev/null 2>&1 || fail "Failed to update package lists"
apt-get install -y task-samba-dc docker-engine docker-compose-v2 ansible sshpass >/dev/null 2>&1 || fail "Failed to install packages"
PKG_INSTALLED=1

# --- Настройка хоста и DNS ---
hostnamectl set-hostname "$HOSTNAME" >/dev/null 2>&1 || fail "Failed to set hostname"
cat > /etc/hosts <<'EOF'
127.0.0.1   localhost localhost.localdomain br-srv
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF
[[ -f "$ENP7S1_RESOLV" ]] && { cp -f "$ENP7S1_RESOLV" "${ENP7S1_RESOLV}.bak" || fail "Failed to backup resolv.conf"; RESOLV_BACKED_UP=1; }
printf "search au-team.irpo\nnameserver 127.0.0.1\n" > "$ENP7S1_RESOLV" || fail "Failed to write resolv.conf"

# --- Провизор домена Samba ---
rm -rf /var/lib/samba/ /var/cache/samba/ 2>/dev/null || true
rm -f /etc/samba/smb.conf 2>/dev/null || true
mkdir -p /var/lib/samba/sysvol || fail "Failed to create samba sysvol"

printf '%s\n' "$SAMBA_REALM" "$SAMBA_DOMAIN" "dc" "SAMBA_INTERNAL" "77.88.8.8" "$SAMBA_PASS" "$SAMBA_PASS" | \
  samba-tool domain provision >/dev/null 2>&1 || fail "Failed to provision samba domain"
SAMBA_PROVISIONED=1
cp -f /var/lib/samba/private/krb5.conf /etc/krb5.conf || fail "Failed to copy krb5.conf"
systemctl enable --now samba.service >/dev/null 2>&1 || fail "Failed to start samba service"

# --- Создание группы и пользователей ---
samba-tool group add hq >/dev/null 2>&1 || fail "Failed to create hq group"
for i in {1..5}; do
  samba-tool user add "hquser$i" "$SAMBA_PASS" >/dev/null 2>&1 || fail "Failed to create user hquser$i"
  samba-tool user setexpiry "hquser$i" --noexpiry >/dev/null 2>&1
  samba-tool group addmembers "hq" "hquser$i" >/dev/null 2>&1
done

# --- Настройка Docker ---
systemctl enable --now docker.service >/dev/null 2>&1 || fail "Failed to start Docker"

# Загрузка образов (требуется смонтированный ISO в /mnt)
if [[ -f /mnt/docker/site_latest.tar ]]; then
  docker load < /mnt/docker/site_latest.tar >/dev/null 2>&1 || fail "Failed to load site image"
  docker load < /mnt/docker/mariadb_latest.tar >/dev/null 2>&1 || fail "Failed to load mariadb image"
else
  echo "[ WARNING ] Docker images not found in /mnt/docker/"
fi

# --- Docker Compose ---
cat > "$DOCKER_COMPOSE_FILE" <<'EOF' || fail "Failed to write compose file"
services:
  database:
    container_name: db
    image: mariadb:10.11
    restart: always
    ports:
      - "3306:3306"
    environment:
      MARIADB_DATABASE: "testdb"
      MARIADB_USER: "testc"
      MARIADB_PASSWORD: "P@ssw0rd"
      MARIADB_ROOT_PASSWORD: "toor"
  app:
    container_name: testapp
    image: site:latest
    restart: always
    ports:
      - "8080:8000"
    environment:
      DB_TYPE: "maria"
      DB_HOST: "192.168.3.10"
      DB_PORT: "3306"
      DB_NAME: "testdb"
      DB_USER: "testc"
      DB_PASS: "P@ssw0rd"
    depends_on:
      - database
EOF
DOCKER_COMPOSE_CREATED=1
docker compose -f "$DOCKER_COMPOSE_FILE" up -d >/dev/null 2>&1 || fail "Failed to start Docker containers"
CONTAINERS_RUNNING=1

# --- Ansible ---
mkdir -p /etc/ansible || fail "Failed to create ansible directory"
cat > /etc/ansible/ansible.cfg <<'EOF' || fail "Failed to write ansible.cfg"
[defaults]
inventory = /etc/ansible/hosts
host_key_checking = False
EOF
cat > /etc/ansible/hosts <<'EOF' || fail "Failed to write hosts"
HQ-SRV ansible_host=192.168.1.10 ansible_user=sshuser ansible_password=P@ssw0rd ansible_port=2026
HQ-CLI ansible_host=192.168.2.10 ansible_user=sshuser ansible_password=P@ssw0rd ansible_port=2026
HQ-RTR ansible_host=10.10.10.1 ansible_user=net_admin ansible_password=P@ssw0rd ansible_port=2026
BR-RTR ansible_host=10.10.10.2 ansible_user=net_admin ansible_password=P@ssw0rd ansible_port=2026

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOF

# --- NTP клиент ---
apt-get install -y chrony >/dev/null 2>&1 || fail "Failed to install chrony"
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.2.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd >/dev/null 2>&1

# --- Завершение ---
rm -f "${ENP7S1_RESOLV}.bak" 2>/dev/null || true
echo "[ OK ] Done"
echo "Пароли пользователей AD: hquser1 (P@ssw0rd), hquser2 (P@ssw0rd), ..."
