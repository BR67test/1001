#!/bin/bash
echo "=== ISP ==="

hostnamectl set-hostname isp

# Настройка интерфейсов
mkdir -p /etc/net/ifaces/enp7s1
cat > /etc/net/ifaces/enp7s1/options <<EOF
BOOTPROTO=dhcp
TYPE=eth
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF

mkdir -p /etc/net/ifaces/enp7s2
cat > /etc/net/ifaces/enp7s2/options <<EOF
BOOTPROTO=static
TYPE=eth
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF
echo "172.16.1.1/28" > /etc/net/ifaces/enp7s2/ipv4address

mkdir -p /etc/net/ifaces/enp7s3
cat > /etc/net/ifaces/enp7s3/options <<EOF
BOOTPROTO=static
TYPE=eth
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF
echo "172.16.2.1/28" > /etc/net/ifaces/enp7s3/ipv4address

echo "nameserver 77.88.8.8" > /etc/net/ifaces/enp7s1/resolv.conf
systemctl restart network

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

# Время
apt-get install -y tzdata
timedatectl set-timezone Asia/Yekaterinburg

echo "=== ISP готов ==="
