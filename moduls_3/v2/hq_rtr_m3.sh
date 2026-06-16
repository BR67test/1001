#!/bin/bash
echo "=== HQ-RTR (Модуль 3) ==="

# ============================================
# 3. IPsec туннель
# ============================================

apt-get update && apt-get install -y strongswan nftables

cat > /etc/strongswan/ipsec.conf <<'EOF'
config setup
    uniqueids = yes
    charondebug="ike 2, knl 2, cfg 2, mgr 2, chd 2"

conn br-rtr.au-team.irpo
    type=transport
    left=172.16.1.10
    leftid=172.16.1.10
    right=172.16.2.10
    rightid=172.16.2.10
    authby=secret
    ike=aes256-sha256-modp2048!
    esp=aes256-sha256!
    keyexchange=ikev2
    ikelifetime=24h
    lifetime=8h
    dpddelay=30
    dpdtimeout=120
    dpdaction=restart
    auto=start
EOF

cat > /etc/strongswan/ipsec.secrets <<'EOF'
172.16.1.10 172.16.2.10 : PSK "P@ssw0rd1!"
EOF

systemctl enable --now strongswan-starter
#systemctl start ipsec

# ============================================
# 4. Межсетевой экран (nftables)
# ============================================

cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        iif lo accept
        ct state established,related accept
        ip protocol icmp accept
        ip protocol udp dport 123 accept
        ip protocol udp dport 500 accept
        ip protocol udp dport 4500 accept
        ip protocol esp accept
        tcp dport 2026 accept
        tcp dport 80 accept
        tcp dport 443 accept
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
        ct state established,related accept
        tcp dport 80 accept
        tcp dport 443 accept
        tcp dport 8080 accept
        tcp dport 2026 accept
        ip protocol esp accept
        ip protocol udp dport 500 accept
        ip protocol udp dport 4500 accept
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

systemctl enable --now nftables

# ============================================
# 6. Rsyslog клиент
# ============================================

apt-get install -y rsyslog

cat > /etc/rsyslog.d/00_common.conf <<'EOF'
module(load="imuxsock")
module(load="imklog")
module(load="imtcp")
*.warning @@192.168.100.2:514
EOF

systemctl restart rsyslog

# ============================================
# 7. Zabbix агент
# ============================================

apt-get install -y zabbix-agent

cat > /etc/zabbix/zabbix_agentd.conf <<'EOF'
Server=192.168.100.2
ServerActive=192.168.100.2
EOF

systemctl enable --now zabbix_agentd.service

echo "=== HQ-RTR (Модуль 3) готов ==="
