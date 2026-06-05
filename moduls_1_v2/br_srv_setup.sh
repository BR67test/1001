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
echo "192.168.0.2/28" > /etc/net/ifaces/enp7s1/ipv4address
echo "default via 192.168.0.1" > /etc/net/ifaces/enp7s1/ipv4route
echo "nameserver 77.88.8.8" > /etc/net/ifaces/enp7s1/resolv.conf

systemctl restart network

# Пользователь sshuser
useradd sshuser -u 2026
echo "sshuser:P@ssw0rd" | chpasswd
usermod -aG wheel sshuser
echo "sshuser ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers

# SSH
apt-get update && apt-get install -y openssh-server
cat > /etc/openssh/sshd_config <<SSH
Port 2026
MaxAuthTries 2
PermitRootLogin no
AllowUsers sshuser
Banner /etc/openssh/banner
Subsystem sftp /usr/libexec/openssh/sftp-server
SSH
echo "Authorized access only" > /etc/openssh/banner
systemctl restart sshd

# Время
apt-get install -y tzdata
timedatectl set-timezone Asia/Yekaterinburg

echo "=== BR-SRV готов ==="
