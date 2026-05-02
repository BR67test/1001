#!/bin/bash
echo "=== Настройка ISP ==="

# 1. Имя хоста
hostnamectl set-hostname isp.au-team.irpo; exec bash

# 2. Сеть. Создаём каталоги и настройки для интерфейсов
# Внешний (ens19) — по DHCP, это работает "из коробки", но пропишем для порядка
mkdir -p /etc/net/ifaces/ens19
echo "BOOTPROTO=dhcp" > /etc/net/ifaces/ens19/options

# Внутренний в сторону HQ (ens20)
cp -r /etc/net/ifaces/ens19 /etc/net/ifaces/ens20
sed -i 's/BOOTPROTO=dhcp/BOOTPROTO=static/' /etc/net/ifaces/ens20/options
echo "172.16.4.1/28" > /etc/net/ifaces/ens20/ipv4address
echo "nameserver 8.8.8.8" > /etc/net/ifaces/ens20/resolv.conf

# Внутренний в сторону BR (ens21)
cp -r /etc/net/ifaces/ens20 /etc/net/ifaces/ens21
echo "172.16.5.1/28" > /etc/net/ifaces/ens21/ipv4address

# Применяем сеть
systemctl restart network

# 3. Включаем форвардинг пакетов
echo "net.ipv4.ip_forward = 1" >> /etc/net/sysctl.conf
sysctl -p

# 4. Настройка NAT (маскарадинг для выхода в интернет)
apt-get update && apt-get install -y iptables
iptables -t nat -A POSTROUTING -o ens19 -j MASQUERADE
iptables-save >> /etc/sysconfig/iptables
systemctl enable --now iptables

# 5. Установка временной зоны
apt-get install -y tzdata
timedatectl set-timezone Asia/Yekaterinburg

echo "=== ISP настроен. Ожидание пиров... ==="
