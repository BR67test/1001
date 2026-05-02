#!/bin/bash
echo "=== Настройка HQ-RTR ==="

hostnamectl set-hostname hq-rtr.au-team.irpo; exec bash

# 1. Настройка интерфейсов
mkdir -p /etc/net/ifaces/ens18 /etc/net/ifaces/ens19

# WAN-интерфейс к ISP
echo "BOOTPROTO=static" > /etc/net/ifaces/ens18/options
echo "172.16.4.14/28" > /etc/net/ifaces/ens18/ipv4address
echo "default via 172.16.4.1" > /etc/net/ifaces/ens18/ipv4route

# LAN-интерфейс
echo "BOOTPROTO=static" > /etc/net/ifaces/ens19/options
echo "192.168.100.1/26" > /etc/net/ifaces/ens19/ipv4address

systemctl restart network

# 2. Настройка VLAN'ов
for vlan in 100 200 999; do
    mkdir -p /etc/net/ifaces/ens19.${vlan}
    cat > /etc/net/ifaces/ens19.${vlan}/options <<EOF
TYPE=vlan
HOST=ens19
VID=${vlan}
DISABLED=no
BOOTPROTO=static
EOF
    case $vlan in
        100) echo "192.168.100.1/26" > /etc/net/ifaces/ens19.100/ipv4address ;;
        200) echo "192.168.100.65/28" > /etc/net/ifaces/ens19.200/ipv4address ;;
        999) echo "192.168.100.81/29" > /etc/net/ifaces/ens19.999/ipv4address ;;
    esac
done

# 3. NAT для локальных сетей
iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o ens18 -j MASQUERADE
iptables-save >> /etc/sysconfig/iptables

# 4. Настройка GRE-туннеля до BR-RTR
ip tunnel add gre1 mode gre local 172.16.4.14 remote 172.16.5.14 ttl 255
ip link set gre1 up

# 5. Маршрутизация и OSPF
# Включаем форвардинг
echo "net.ipv4.ip_forward = 1" >> /etc/net/sysctl.conf; sysctl -p

# Установка и настройка FRR для OSPF
apt-get update && apt-get install -y frr
sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
systemctl restart frr

vtysh <<VTYSH
configure terminal
router ospf 1
 ospf router-id 10.10.10.1
 passive-interface default
 no passive-interface gre1
 network 10.10.10.0/30 area 0
 network 192.168.100.0/26 area 0
 network 192.168.100.64/28 area 0
 network 192.168.100.80/29 area 0
interface gre1
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 P@ssw0rd
do write memory
VTYSH

# 6. DHCP-сервер
apt-get install -y dnsmasq
cat > /etc/dnsmasq.conf <<DNS
no-resolv
dhcp-range=192.168.100.66,192.168.100.78,999h
dhcp-option=3,192.168.100.65
dhcp-option=6,192.168.100.2
interface=ens19.200
bind-interfaces
DNS
systemctl restart dnsmasq

echo "=== HQ-RTR настроен ==="
