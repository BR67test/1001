#!/bin/bash
echo "=== BR-RTR ==="

hostnamectl set-hostname br-rtr.au-team.irpo

# enp7s1 — к ISP
mkdir -p /etc/net/ifaces/enp7s1
cat > /etc/net/ifaces/enp7s1/options <<EOF
BOOTPROTO=static
TYPE=eth
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF
echo "172.16.5.14/28" > /etc/net/ifaces/enp7s1/ipv4address
echo "default via 172.16.5.1" > /etc/net/ifaces/enp7s1/ipv4route

# enp7s2 — к BR-SRV
mkdir -p /etc/net/ifaces/enp7s2
cat > /etc/net/ifaces/enp7s2/options <<EOF
BOOTPROTO=static
TYPE=eth
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF
echo "192.168.200.1/27" > /etc/net/ifaces/enp7s2/ipv4address

systemctl restart network

# GRE-туннель
ip tunnel add gre1 mode gre local 172.16.5.14 remote 172.16.4.14 ttl 255
ip link set gre1 up
ip addr add 10.10.10.2/30 dev gre1

# NAT
iptables -t nat -A POSTROUTING -s 192.168.200.0/27 -o enp7s1 -j MASQUERADE
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
 ospf router-id 10.10.10.2
 passive-interface default
 no passive-interface gre1
interface gre1
 ip ospf area 0
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 P@ssw0rd
interface enp7s2
 ip ospf area 0
do wr mem
VTYSH

# Пользователь
useradd net_admin -u 1010
echo "net_admin:P@\$\$word" | chpasswd
echo "net_admin ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers

# Время
apt-get install -y tzdata
timedatectl set-timezone Asia/Yekaterinburg

echo "=== BR-RTR готов ==="
