#!/bin/bash
echo "=== HQ-SRV ==="

hostnamectl set-hostname hq-srv.au-team.irpo

# Сеть (VLAN 100)
mkdir -p /etc/net/ifaces/enp7s1
cat > /etc/net/ifaces/enp7s1/options <<EOF
BOOTPROTO=manual
TYPE=eth
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=yes
DISABLED=no
EOF

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
echo "192.168.100.2/27" > /etc/net/ifaces/enp7s1.100/ipv4address
echo "default via 192.168.100.1" > /etc/net/ifaces/enp7s1.100/ipv4route

systemctl restart network

# DNS-сервер (dnsmasq)
apt-get update && apt-get install -y dnsmasq

cat > /etc/dnsmasq.conf <<DNS
no-hosts
server=77.88.8.8
cache-size=1000
all-servers
interface=enp7s1.100
bind-interfaces
host-record=hq-rtr.au-team.irpo,192.168.100.1
host-record=hq-rtr.au-team.irpo,192.168.200.1
host-record=hq-rtr.au-team.irpo,192.168.99.1
host-record=hq-srv.au-team.irpo,192.168.100.2
host-record=hq-cli.au-team.irpo,192.168.200.2
host-record=br-rtr.au-team.irpo,192.168.0.1
host-record=br-srv.au-team.irpo,192.168.0.2
host-record=docker.au-team.irpo,172.16.1.1
host-record=web.au-team.irpo,172.16.2.1
DNS

systemctl enable --now dnsmasq

# Пользователь sshuser
useradd sshuser -u 2026
echo "sshuser:P@ssw0rd" | chpasswd
usermod -aG wheel sshuser
echo "sshuser ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers

# SSH
apt-get install -y openssh-server
cat > /etc/openssh/sshd_config <<SSH
Port 2026
MaxAuthTries 2
PermitRootLogin no
AllowUsers sshuser
Banner /etc/openssh/banner
Subsystem sftp /usr/libexec/openssh/sftp-server
SSH
echo "Authorized access only" > /etc/openssh/banner
systemctl restart sshd

# Время
apt-get install -y tzdata
timedatectl set-timezone Asia/Yekaterinburg


echo "=== HQ-SRV готов ==="
