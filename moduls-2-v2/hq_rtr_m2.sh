#!/bin/bash
set -euo pipefail
echo "[ OK ] Start"

# --- IP адреса (твоя топология) ---
HQ_SRV_IP="192.168.1.10"
HQ_SRV_PORT="80"
ISP_GATEWAY="172.16.1.1"

# --- Флаги ---
PKG_INSTALLED=0

# --- Функция отката ---
rollback() {
  echo "[ INFO ] Rolling back changes..."
  if [[ $PKG_INSTALLED -eq 1 ]]; then
    apt-get remove -y iptables openssh-server >/dev/null 2>&1 || true
  fi
  echo "[ OK ] Rollback completed"
}
fail() { echo "[ ERROR ] $1"; rollback; exit 1; }

[[ $EUID -ne 0 ]] && fail "Root privileges required"

# --- Установка пакетов ---
apt-get update -qq >/dev/null 2>&1 || fail "Failed to update package lists"
apt-get install -y iptables openssh-server >/dev/null 2>&1 || fail "Failed to install packages"
PKG_INSTALLED=1

# --- SSH ---
echo "net_admin:P@ssw0rd" | chpasswd
cat > /etc/openssh/sshd_config <<'EOF' || fail "Failed to configure SSH"
Port 2026
MaxAuthTries 3
PermitRootLogin no
AllowUsers net_admin
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF
systemctl enable --now sshd.service >/dev/null 2>&1 || fail "Failed to start SSH"

# --- Проброс портов ---
iptables -t nat -A PREROUTING -i enp7s1 -p tcp --dport 8080 -j DNAT --to-destination ${HQ_SRV_IP}:${HQ_SRV_PORT}
iptables -t nat -A PREROUTING -i enp7s1 -p tcp --dport 2026 -j DNAT --to-destination ${HQ_SRV_IP}:2026
iptables-save > /etc/sysconfig/iptables 2>/dev/null || fail "Failed to save iptables rules"

# --- NTP клиент ---
apt-get install -y chrony >/dev/null 2>&1 || fail "Failed to install chrony"
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server $ISP_GATEWAY iburst" >> /etc/chrony.conf
systemctl restart chronyd >/dev/null 2>&1

echo "[ OK ] Done"
