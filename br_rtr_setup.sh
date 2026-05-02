#!/bin/bash
echo "=== Настройка BR-RTR ==="

hostnamectl set-hostname br-rtr.au-team.irpo; exec bash

# 1. Настройка интерфейсов
mkdir -p /etc/net/ifaces/ens18 /etc/net/ifaces/ens19

# WAN-интерфейс к ISP
echo "BOOTPROTO=static" > /etc/net/ifaces/ens18/options
echo "172.16.5.14/28" > /etc/net/ifaces/ens18/ipv4address
echo "default via 172.16.5.1" > /etc/net/ifaces/ens18/ipv4route

# LAN-интерфейс к BR-Net
echo "BOOTPROTO=static" > /etc/net/ifaces/ens19/options
echo "192.168.200.1/27" > /etc/net/ifaces/ens19/ipv4address

systemctl restart network

# 2. NAT для локальной сети
iptables -t nat -A POSTROUTING -s 192.168.200.0/27 -o ens18 -j MASQUERADE
iptables-save >> /etc/sysconfig/iptables

# 3. GRE-туннель до HQ-RTR
ip tunnel add gre1 mode gre local 172.16.5.14 remote 172.16.4.14 ttl 255
ip link set gre1 up

# 4. Маршрутизация и OSPF
echo "net.ipv4.ip_forward = 1" >> /etc/net/sysctl.conf; sysctl -p
apt-get update && apt-get install -y frr
sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
systemctl restart frr

vtysh <<VTYSH
configure terminal
router ospf 1
 ospf router-id 10.10.10.2
 passive-interface default
 no passive-interface gre1
 network 10.10.10.0/30 area 0
 network 192.168.200.0/27 area 0
interface gre1
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 P@ssw0rd
do write memory
VTYSH
echo "=== BR-RTR настроен ==="
