#!/bin/bash
echo "=== Настройка BR-SRV ==="

hostnamectl set-hostname br-srv.au-team.irpo; exec bash

# 1. Настройка сети
mkdir -p /etc/net/ifaces/ens19
echo "BOOTPROTO=static" > /etc/net/ifaces/ens19/options
echo "192.168.200.2/27" > /etc/net/ifaces/ens19/ipv4address
echo "default via 192.168.200.1" > /etc/net/ifaces/ens19/ipv4route
echo "nameserver 77.88.8.8" > /etc/net/ifaces/ens19/resolv.conf
systemctl restart network

# 2. Создание пользователя sshuser
useradd sshuser -u 1010
echo "sshuser:P@ssw0rd" | chpasswd
usermod -aG wheel sshuser
echo "sshuser ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers

# 3. Настройка SSH
apt-get install -y openssh-server
sed -i 's/^#Port 22/Port 2024/' /etc/openssh/sshd_config
sed -i 's/^#MaxAuthTries 6/MaxAuthTries 2/' /etc/openssh/sshd_config
sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/openssh/sshd_config
echo "AllowUsers sshuser" >> /etc/openssh/sshd_config
echo "Authorized access only" > /etc/openssh/banner
sed -i '/^#Banner none/a Banner /etc/openssh/banner' /etc/openssh/sshd_config
systemctl restart sshd

echo "=== BR-SRV настроен ==="
