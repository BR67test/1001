#!/bin/bash
echo "=== BR-SRV (Модуль 2) ==="

# Samba DC
apt-get update && apt-get install -y task-samba-dc

rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba/
rm -rf /var/cache/samba/
mkdir -p /var/lib/samba/sysvol

samba-tool domain provision --realm=AU-TEAM.IRPO --domain=AU-TEAM --server-role=dc --dns-backend=SAMBA_INTERNAL --dns-forwarder=77.88.8.8 --adminpass=P@ssw0rd --use-rfc2307

cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

cat > /etc/net/ifaces/enp7s1/resolv.conf <<EOF
search au-team.irpo
nameserver 127.0.0.1
EOF

systemctl enable --now samba
systemctl restart network

# Группа и пользователи AD
samba-tool group add hq
for i in {1..5}; do
    samba-tool user add hquser$i Password
    samba-tool user setexpiry hquser$i --noexpiry
    samba-tool group addmembers "hq" hquser$i
done

# Docker
apt-get install -y docker-engine docker-compose-v2
systemctl enable --now docker

# Загрузка образов (если монтирован диск с доп. материалами)
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

docker compose -f /root/compose.yaml up -d

# Ansible
apt-get install -y ansible sshpass

cat > /etc/ansible/ansible.cfg <<EOF
[defaults]
inventory = /etc/ansible/hosts
host_key_checking = False
EOF

cat > /etc/ansible/hosts <<EOF
HQ-SRV ansible_host=192.168.100.2 ansible_user=sshuser ansible_password=P@ssw0rd ansible_port=2026
HQ-CLI ansible_host=192.168.200.2 ansible_user=user ansible_password=resu
HQ-RTR ansible_host=10.10.10.1 ansible_user=user ansible_password=resu
BR-RTR ansible_host=192.168.0.1 ansible_user=user ansible_password=resu

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOF

# NTP-клиент (сервер — ISP)
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.2.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

echo "=== BR-SRV готов ==="
