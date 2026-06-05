#!/bin/bash
echo "=== HQ-CLI ==="

hostnamectl set-hostname hq-cli.au-team.irpo

# Сеть
mkdir -p /etc/net/ifaces/enp7s1
cat > /etc/net/ifaces/enp7s1/options <<EOF
BOOTPROTO=manual
TYPE=eth
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF

mkdir -p /etc/net/ifaces/enp7s1.200
cat > /etc/net/ifaces/enp7s1.200/options <<EOF
TYPE=vlan
HOST=enp7s1
VID=200
BOOTPROTO=dhcp
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF

systemctl restart network

# Пользователь
useradd sshuser
echo "sshuser:P@ssw0rd" | chpasswd
usermod -aG wheel sshuser
echo "sshuser ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers

# SSH
apt-get update && apt-get install -y openssh-server
systemctl enable --now sshd

# Время
timedatectl set-timezone Asia/Yekaterinburg

echo "=== HQ-CLI готов ==="
