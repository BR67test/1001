#!/bin/bash
echo "=== HQ-RTR (Модуль 3) ==="

# ============================================
# 3. IPsec туннель (strongSwan)
# ============================================

apt-get update && apt-get install -y strongswan strongswan-pki libcharon-extra-plugins

# Генерация ключей и сертификатов
pki --gen --type rsa --size 4096 --outform pem > /etc/strongswan/ipsec.d/private/hq-rtr-key.pem
pki --self --ca --lifetime 3650 --in /etc/strongswan/ipsec.d/private/hq-rtr-key.pem \
    --dn "CN=HQ-RTR" --outform pem > /etc/strongswan/ipsec.d/cacerts/hq-rtr-cert.pem

cat > /etc/strongswan/ipsec.conf <<EOF
config setup
    charondebug="all"
    uniqueids=yes

conn hq-to-br
    auto=start
    type=tunnel
    keyexchange=ikev2
    authby=pubkey
    left=172.16.1.2
    leftsubnet=10.10.10.0/30,192.168.100.0/24,192.168.200.0/24,192.168.99.0/29
    leftid=@hq-rtr
    leftcert=hq-rtr-cert.pem
    leftfirewall=yes
    right=172.16.2.2
    rightsubnet=10.10.10.0/30,192.168.0.0/24
    rightid=@br-rtr
    ike=aes256-sha256-modp2048
    esp=aes256-sha256
    keyingtries=%forever
    ikelifetime=24h
    lifetime=8h
    dpddelay=30s
    dpdtimeout=120s
    dpdaction=restart
EOF

cat > /etc/strongswan/ipsec.secrets <<EOF
: RSA hq-rtr-key.pem "P@ssw0rd"
EOF

systemctl enable --now strongswan

# ============================================
# 4. Межсетевой экран (файрвол)
# ============================================

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -F
iptables -X

iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT
iptables -A FORWARD -p icmp -j ACCEPT
iptables -A INPUT -p udp --dport 123 -j ACCEPT

iptables -A FORWARD -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -p tcp --dport 8080 -j ACCEPT
iptables -A FORWARD -p tcp --dport 2026 -j ACCEPT

iptables -A INPUT -p udp --dport 500 -j ACCEPT
iptables -A INPUT -p udp --dport 4500 -j ACCEPT
iptables -A INPUT -p esp -j ACCEPT
iptables -A FORWARD -p udp --dport 500 -j ACCEPT
iptables -A FORWARD -p udp --dport 4500 -j ACCEPT
iptables -A FORWARD -p esp -j ACCEPT

iptables-save > /etc/sysconfig/iptables
systemctl restart iptables

echo "=== HQ-RTR (Модуль 3) готов ==="
