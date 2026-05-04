#!/bin/bash
echo "=== ISP ==="

hostnamectl set-hostname isp.au-team.irpo

# Сеть
mkdir -p /etc/net/ifaces/enp7s1
echo "BOOTPROTO=dhcp" > /etc/net/ifaces/enp7s1/options

mkdir -p /etc/net/ifaces/enp7s2
cat > /etc/net/ifaces/enp7s2/options <<EOF
BOOTPROTO=static
TYPE=eth
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF
echo "172.16.4.1/28" > /etc/net/ifaces/enp7s2/ipv4address

mkdir -p /etc/net/ifaces/enp7s3
cat > /etc/net/ifaces/enp7s3/options <<EOF
BOOTPROTO=static
TYPE=eth
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF
echo "172.16.5.1/28" > /etc/net/ifaces/enp7s3/ipv4address

echo "nameserver 8.8.8.8" > /etc/net/ifaces/enp7s1/resolv.conf
systemctl restart network

# Форвардинг
echo 1 > /proc/sys/net/ipv4/ip_forward

# NAT
apt-get update && apt-get install -y iptables
iptables -t nat -A POSTROUTING -o enp7s1 -j MASQUERADE
iptables-save > /etc/sysconfig/iptables
systemctl enable --now iptables

# Время
apt-get install -y tzdata
timedatectl set-timezone Asia/Yekaterinburg

echo "=== ISP готов ==="
