#!/bin/bash
echo "=== HQ-SRV ==="

hostnamectl set-hostname hq-srv.au-team.irpo

# ========== СЕТЬ ==========
# enp7s1 — manual (Trunk)
mkdir -p /etc/net/ifaces/enp7s1
cat > /etc/net/ifaces/enp7s1/options <<EOF
BOOTPROTO=manual
TYPE=eth
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF

# VLAN 100
mkdir -p /etc/net/ifaces/enp7s1.100
cat > /etc/net/ifaces/enp7s1.100/options <<EOF
TYPE=vlan
HOST=enp7s1
VID=100
BOOTPROTO=static
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF
echo "192.168.100.2/26" > /etc/net/ifaces/enp7s1.100/ipv4address
echo "default via 192.168.100.1" > /etc/net/ifaces/enp7s1.100/ipv4route
echo "nameserver 127.0.0.1" > /etc/net/ifaces/enp7s1.100/resolv.conf

systemctl restart network

# ========== BIND9 (DNS) ==========
apt-get update
apt-get install -y bind bind-utils

# Основной конфиг
cat > /etc/bind/options.conf <<BIND
options {
    listen-on { 192.168.100.2; };
    listen-on-v6 { none; };
    forwarders { 77.88.8.8; };
    allow-query { any; };
    allow-recursion { any; };
};
BIND

# Добавляем зоны
cat >> /etc/bind/rfc1912.conf <<ZONES

zone "au-team.irpo" {
    type master;
    file "au-team.irpo";
};

zone "100.168.192.in-addr.arpa" {
    type master;
    file "100.168.192.in-addr.arpa";
};
ZONES

# Файл прямой зоны
cat > /etc/bind/zone/au-team.irpo <<ZONE
\$TTL 1D
@       IN SOA  hq-srv.au-team.irpo. root.au-team.irpo. (
                2025010101 ; serial
                12H        ; refresh
                1H         ; retry
                1W         ; expire
                1H         ; minimum
)
        IN NS   hq-srv.au-team.irpo.
        IN A    192.168.100.2
hq-srv  IN A    192.168.100.2
hq-rtr  IN A    192.168.100.1
hq-cli  IN A    192.168.100.66
br-rtr  IN A    192.168.200.1
br-srv  IN A    192.168.200.2
moodle  IN CNAME hq-srv
wiki    IN CNAME hq-srv
ZONE

# Файл обратной зоны
cat > /etc/bind/zone/100.168.192.in-addr.arpa <<ZONE
\$TTL 1D
@       IN SOA  hq-srv.au-team.irpo. root.au-team.irpo. (
                2025010101 ; serial
                12H        ; refresh
                1H         ; retry
                1W         ; expire
                1H         ; minimum
)
        IN NS   hq-srv.au-team.irpo.
2       IN PTR  hq-srv.au-team.irpo.
1       IN PTR  hq-rtr.au-team.irpo.
ZONE

# Права
chown root:named /etc/bind/zone/au-team.irpo
chown root:named /etc/bind/zone/100.168.192.in-addr.arpa

# Запуск
systemctl enable --now bind

# ========== ПОЛЬЗОВАТЕЛЬ ==========
useradd sshuser -u 1010
echo "sshuser:P@ssw0rd" | chpasswd
usermod -aG wheel sshuser
echo "sshuser ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers

# ========== SSH ==========
apt-get install -y openssh-server
cat > /etc/openssh/sshd_config <<SSH
Port 2024
MaxAuthTries 2
PermitRootLogin no
AllowUsers sshuser
Banner /etc/openssh/banner
Subsystem sftp /usr/libexec/openssh/sftp-server
SSH
echo "Authorized access only" > /etc/openssh/banner
systemctl restart sshd

# ========== ВРЕМЯ ==========
timedatectl set-timezone Asia/Yekaterinburg

echo "=== HQ-SRV готов ==="
