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
echo "172.16.2.2/28" > /etc/net/ifaces/enp7s1/ipv4address
echo "default via 172.16.2.1" > /etc/net/ifaces/enp7s1/ipv4route
echo "nameserver 77.88.8.8" > /etc/net/ifaces/enp7s1/resolv.conf

# enp7s2 — к BR-SRV
mkdir -p /etc/net/ifaces/enp7s2
cat > /etc/net/ifaces/enp7s2/options <<EOF
BOOTPROTO=static
TYPE=eth
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF
echo "192.168.0.1/28" > /etc/net/ifaces/enp7s2/ipv4address

systemctl restart network

# GRE-туннель
ip tunnel add gre1 mode gre local 172.16.2.2 remote 172.16.1.2 ttl 64
ip link set gre1 up
ip addr add 10.10.10.2/30 dev gre1

# Форвардинг
echo 1 > /proc/sys/net/ipv4/ip_forward
sed -i 's/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g' /etc/sysctl.conf

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
 ospf router-id 192.168.0.1
 passive-interface default
 network 10.10.10.0/30 area 0
 network 192.168.0.0/28 area 0
interface gre1
 no ip ospf passive
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 P@ssw0rd
do wr mem
VTYSH

# Пользователь net_admin
useradd net_admin -u 1010
echo "net_admin:P@ssw0rd" | chpasswd
echo "net_admin ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers

# Время
apt-get install -y tzdata
timedatectl set-timezone Asia/Yekaterinburg


echo "=== BR-RTR готов ==="
