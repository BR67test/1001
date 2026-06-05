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
echo "172.16.4.14/28" > /etc/net/ifaces/enp7s1/ipv4address
echo "default via 172.16.4.1" > /etc/net/ifaces/enp7s1/ipv4route

# enp7s2 — manual (Trunk)
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
echo "192.168.100.1/26" > /etc/net/ifaces/enp7s2.100/ipv4address

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
echo "192.168.100.65/28" > /etc/net/ifaces/enp7s2.200/ipv4address

# VLAN 999
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
echo "192.168.100.81/29" > /etc/net/ifaces/enp7s2.999/ipv4address

systemctl restart network

# GRE-туннель
ip tunnel add gre1 mode gre local 172.16.4.14 remote 172.16.5.14 ttl 255
ip link set gre1 up
ip addr add 10.10.10.1/30 dev gre1

# NAT
iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o enp7s1 -j MASQUERADE
iptables-save > /etc/sysconfig/iptables
systemctl enable --now iptables

# Форвардинг
echo 1 > /proc/sys/net/ipv4/ip_forward

# FRR + OSPF
apt-get update && apt-get install -y frr
sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
systemctl restart frr

vtysh <<VTYSH
conf t
router ospf
 ospf router-id 10.10.10.1
 passive-interface default
 no passive-interface gre1
interface gre1
 ip ospf area 0
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 P@ssw0rd
interface enp7s2.100
 ip ospf area 0
interface enp7s2.200
 ip ospf area 0
interface enp7s2.999
 ip ospf area 0
do wr mem
VTYSH

# DHCP
apt-get install -y dnsmasq
cat > /etc/dnsmasq.conf <<DNS
no-resolv
dhcp-range=192.168.100.66,192.168.100.78,999h
dhcp-option=3,192.168.100.65
dhcp-option=6,192.168.100.2
interface=enp7s2.200
bind-interfaces
DNS
systemctl restart dnsmasq

# Пользователь
useradd net_admin -u 1010
echo "net_admin:P@\$\$word" | chpasswd
echo "net_admin ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers

# Время
timedatectl set-timezone Asia/Yekaterinburg

echo "=== HQ-RTR готов ==="
