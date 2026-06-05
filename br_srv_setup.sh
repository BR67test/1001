#!/bin/bash
echo "=== BR-SRV ==="

hostnamectl set-hostname br-srv.au-team.irpo

# Сеть
mkdir -p /etc/net/ifaces/enp7s1
cat > /etc/net/ifaces/enp7s1/options <<EOF
BOOTPROTO=static
TYPE=eth
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF
echo "192.168.200.2/27" > /etc/net/ifaces/enp7s1/ipv4address
echo "default via 192.168.200.1" > /etc/net/ifaces/enp7s1/ipv4route
echo "nameserver 8.8.8.8" > /etc/net/ifaces/enp7s1/resolv.conf

systemctl restart network

# Пользователь
useradd sshuser -u 1010
echo "sshuser:P@ssw0rd" | chpasswd
usermod -aG wheel sshuser
echo "sshuser ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers

# SSH
apt-get update && apt-get install -y openssh-server
cat > /etc/openssh/sshd_config <<SSH
Port 2024
MaxAuthTries 2
PermitRootLogin no
AllowUsers sshuser
Banner /etc/openssh/banner
Subsystem sftp /usr/libexec/openssh/sftp-server
SSH
echo "Authorized access only" > /etc/openssh/banner
systemctl restart sshd

# Время
timedatectl set-timezone Asia/Yekaterinburg

echo "=== BR-SRV готов ==="
