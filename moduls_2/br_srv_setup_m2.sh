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
# Установка Samba DC
# ============================================
apt-get install -y task-samba-dc

rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba/
rm -rf /var/cache/samba/
mkdir -p /var/lib/samba/sysvol

# Provision домена (с DNS forwarder)
samba-tool domain provision --realm=AU-TEAM.IRPO --domain=AU-TEAM --server-role=dc --dns-backend=SAMBA_INTERNAL --adminpass='P@ssw0rd' --use-rfc2307

# Копирование Kerberos конфига
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

# Настройка DNS
cat > /etc/net/ifaces/enp7s1/resolv.conf <<EOF
search au-team.irpo
nameserver 127.0.0.1
EOF

systemctl restart network
systemctl enable --now samba
sleep 5

# ============================================
# Создание группы и пользователей (пароли как в рабочих скринах)
# ============================================
samba-tool group add hq

for i in {1..5}; do
    samba-tool user add "hquser$i" "P@ssw0rd${i}!"
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
if [ -f /mnt/docker/site_latest.tar ]; then
    docker load < /mnt/docker/site_latest.tar
fi
if [ -f /mnt/docker/mariadb_latest.tar ]; then
    docker load < /mnt/docker/mariadb_latest.tar
fi

# Docker Compose
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
      - "8080:8080"
    environment:
      DB_TYPE: "maria"
      DB_HOST: "192.168.0.2"
      DB_PORT: "3306"
      DB_NAME: "testdb"
      DB_USER: "testc"
      DB_PASS: "P@ssw0rd"
    depends_on:
      - database
EOF

cd /root && docker compose up -d

# ============================================
# Ansible
# ============================================
apt-get install -y ansible sshpass

mkdir -p /etc/ansible

cat > /etc/ansible/ansible.cfg <<EOF
[defaults]
inventory = /etc/ansible/hosts
host_key_checking = False
EOF

cat > /etc/ansible/hosts <<EOF
HQ-SRV ansible_host=192.168.1.10 ansible_user=sshuser ansible_password=P@ssw0rd ansible_port=2026
HQ-CLI ansible_host=192.168.2.10 ansible_user=user ansible_password=resu ansible_port=22
HQ-RTR ansible_host=172.16.1.10 ansible_user=user ansible_password=resu ansible_port=22
BR-RTR ansible_host=172.16.2.10 ansible_user=user ansible_password=resu ansible_port=22

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOF

# ============================================
# NTP-клиент
# ============================================
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.2.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

echo "=== BR-SRV готов ==="
echo "SSH: port 2026, user: sshuser, password: P@ssw0rd"
echo "Пользователи AD: hquser1 (P@ssw0rd1!), hquser2 (P@ssw0rd2!), ..."
