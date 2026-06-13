#!/bin/bash
echo "=== HQ-RTR ==="

hostnamectl set-hostname hq-rtr.au-team.irpo

# enp7s1 — к ISP
mkdir -p /etc/net/ifaces/enp7s1
cat > /etc/net/ifaces/enp7s1/options <<EOF
BOOTPROTO=static
TYPE=eth
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF
echo "172.16.1.2/28" > /etc/net/ifaces/enp7s1/ipv4address
echo "default via 172.16.1.1" > /etc/net/ifaces/enp7s1/ipv4route
echo "nameserver 77.88.8.8" > /etc/net/ifaces/enp7s1/resolv.conf

# enp7s2 — Trunk (VLAN)
mkdir -p /etc/net/ifaces/enp7s2
cat > /etc/net/ifaces/enp7s2/options <<EOF
BOOTPROTO=manual
TYPE=eth
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF

# VLAN 100
mkdir -p /etc/net/ifaces/enp7s2.100
cat > /etc/net/ifaces/enp7s2.100/options <<EOF
TYPE=vlan
HOST=enp7s2
VID=100
BOOTPROTO=static
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF
echo "192.168.100.1/27" > /etc/net/ifaces/enp7s2.100/ipv4address

# VLAN 200
mkdir -p /etc/net/ifaces/enp7s2.200
cat > /etc/net/ifaces/enp7s2.200/options <<EOF
TYPE=vlan
HOST=enp7s2
VID=200
BOOTPROTO=static
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF
echo "192.168.200.1/24" > /etc/net/ifaces/enp7s2.200/ipv4address

# VLAN 999 (управление)
mkdir -p /etc/net/ifaces/enp7s2.999
cat > /etc/net/ifaces/enp7s2.999/options <<EOF
TYPE=vlan
HOST=enp7s2
VID=999
BOOTPROTO=static
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF
echo "192.168.99.1/29" > /etc/net/ifaces/enp7s2.999/ipv4address

systemctl restart network

# GRE-туннель
ip tunnel add gre1 mode gre local 172.16.1.2 remote 172.16.2.2 ttl 64
ip link set gre1 up
ip addr add 10.10.10.1/30 dev gre1

# Форвардинг
# Временное включение
echo 1 > /proc/sys/net/ipv4/ip_forward

# Перманентное включение
SYSCTL_CONF="/etc/net/sysctl.conf"

if [ -f "$SYSCTL_CONF" ]; then
    # Удаляем старые строки, если есть
    sed -i '/net.ipv4.ip_forward/d' "$SYSCTL_CONF"
    # Добавляем новую строку
    echo "net.ipv4.ip_forward = 1" >> "$SYSCTL_CONF"
else
    # Если файла нет — создаём
    echo "net.ipv4.ip_forward = 1" > "$SYSCTL_CONF"
fi

# Применяем настройки
sysctl -p "$SYSCTL_CONF" 2>/dev/null || sysctl -p /etc/sysctl.conf 2>/dev/null

# NAT
apt-get update && apt-get install -y iptables
iptables -t nat -A POSTROUTING -o enp7s1 -j MASQUERADE
iptables-save > /etc/sysconfig/iptables
systemctl enable --now iptables

# FRR + OSPF
apt-get update && apt-get install -y frr
sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
systemctl restart frr

vtysh <<VTYSH
conf t
router ospf
 ospf router-id 192.168.100.1
 passive-interface default
 network 10.10.10.0/30 area 0
 network 192.168.100.0/27 area 0
 network 192.168.200.0/24 area 0
 network 192.168.99.0/29 area 0
interface gre1
 no ip ospf passive
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 P@ssw0rd
do wr mem
VTYSH

# DHCP-сервер для VLAN 200
apt-get install -y dnsmasq
cat > /etc/dnsmasq.conf <<DNS
port=67
dhcp-range=192.168.200.2,192.168.200.200,255.255.255.0,24h
dhcp-option=3,192.168.200.1
dhcp-option=6,192.168.100.2
interface=enp7s2.200
bind-interfaces
DNS
systemctl enable --now dnsmasq

# Пользователь net_admin
useradd net_admin -u 1010
echo "net_admin:P@ssw0rd" | chpasswd
echo "net_admin ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers

# Время
apt-get install -y tzdata
timedatectl set-timezone Asia/Yekaterinburg

echo "=== HQ-RTR готов ==="
