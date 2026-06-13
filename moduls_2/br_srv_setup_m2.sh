#!/bin/bash
echo "=== BR-SRV (Модуль 2) ==="

# ============================================
# SSH настройка (порт 2026)
# ============================================
apt-get update && apt-get install -y openssh-server

useradd sshuser -u 2026 2>/dev/null
echo "sshuser:P@ssw0rd" | chpasswd
usermod -aG wheel sshuser

cat > /etc/openssh/sshd_config <<EOF
Port 2026
MaxAuthTries 3
PermitRootLogin no
AllowUsers sshuser
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF

systemctl enable --now sshd

# ============================================
# Установка Samba DC и дополнительных пакетов
# ============================================
apt-get install -y task-samba-dc alterator-fbi alterator-net-domain admx-* admc gpui

rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba/
rm -rf /var/cache/samba/
mkdir -p /var/lib/samba/sysvol

# Провизор домена
samba-tool domain provision \
    --realm=AU-TEAM.IRPO \
    --domain=AU-TEAM \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
#    --dns-forwarder=77.88.8.8 \
    --adminpass='P@ssw0rd' \
    --use-rfc2307

cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

# Настройка DNS (два сервера: сначала сам, потом HQ-SRV)
cat >> /etc/resolvconf.conf <<EOF
name_servers=127.0.0.1
name_servers=192.168.1.10
EOF
resolvconf -u
systemctl restart network

systemctl enable --now samba
sleep 5

# ============================================
# Создание группы и пользователей
# ============================================
samba-tool group add hq

for i in {1..5}; do
    samba-tool user add "hquser$i" "P@ssw0rd"
    samba-tool user setexpiry "hquser$i" --noexpiry
    samba-tool group addmembers "hq" "hquser$i"
done

# ============================================
# Docker и Docker Compose
# ============================================
apt-get install -y docker-engine docker-compose-v2
systemctl enable --now docker

# Загрузка образов с ISO
mount /dev/sr0 /mnt 2>/dev/null
[ -f /mnt/docker/site_latest.tar ] && docker load < /mnt/docker/site_latest.tar
[ -f /mnt/docker/mariadb_latest.tar ] && docker load < /mnt/docker/mariadb_latest.tar

cat > /root/compose.yaml <<EOF
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

cd /root && docker compose up -d
sleep 5

# Фикс: создание БД и пользователя вручную
docker exec -i db mariadb -u root -ptoor <<< "CREATE DATABASE IF NOT EXISTS testdb;"
docker exec -i db mariadb -u root -ptoor <<< "CREATE USER IF NOT EXISTS 'testc'@'%' IDENTIFIED BY 'P@ssw0rd';"
docker exec -i db mariadb -u root -ptoor <<< "GRANT ALL PRIVILEGES ON testdb.* TO 'testc'@'%';"
docker exec -i db mariadb -u root -ptoor <<< "FLUSH PRIVILEGES;"

# ============================================
# Ansible
# ============================================
apt-get install -y ansible sshpass

mkdir -p /etc/ansible

cat > /etc/ansible/ansible.cfg <<EOF
[defaults]
inventory = /etc/ansible/hosts
host_key_checking = False
interpreter_python = /usr/bin/python3
EOF

cat > /etc/ansible/hosts <<EOF
[Alt]
hq-rtr.au-team.irpo ansible_user=net_admin ansible_password=P@ssw0rd
hq-srv.au-team.irpo ansible_user=sshuser ansible_password=P@ssw0rd
hq-cli.au-team.irpo ansible_user=sshuser ansible_password=P@ssw0rd
br-rtr.au-team.irpo ansible_user=net_admin ansible_password=P@ssw0rd

[all:vars]
ansible_port=2026
EOF

# ============================================
# NTP-клиент
# ============================================
apt-get install -y chrony
cat > /etc/chrony.conf <<EOF
pool 172.16.2.1 iburst prefer
EOF
systemctl restart chronyd
systemctl enable --now chronyd

echo "=== BR-SRV готов ==="
echo "SSH: port 2026, user: sshuser, password: P@ssw0rd"
echo "Пользователи AD: hquser1 (P@ssw0rd), hquser2 (P@ssw0rd), ..."
