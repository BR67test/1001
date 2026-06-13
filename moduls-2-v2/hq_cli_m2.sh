#!/bin/bash
set -euo pipefail
echo "[ OK ] Start"

# --- Переменные ---
SSH_USER="sshuser"
SSH_PASS="P@ssw0rd"
DOMAIN="au-team.irpo"
NFS_SERVER="192.168.1.10"
NFS_SHARE="/raid/nfs"
NFS_MOUNT="/mnt/nfs"

# --- Флаги ---
PKG_INSTALLED=0
SSH_CONFIGURED=0

# --- Функция отката ---
rollback() {
  echo "[ INFO ] Rolling back changes..."
  if [[ $SSH_CONFIGURED -eq 1 ]]; then
    systemctl stop sshd.service 2>/dev/null || true
    systemctl disable sshd.service 2>/dev/null || true
    userdel $SSH_USER 2>/dev/null || true
    rm -f /etc/sudoers.d/$SSH_USER 2>/dev/null || true
  fi
  if [[ $PKG_INSTALLED -eq 1 ]]; then
    apt-get remove -y task-auth-ad-sssd admc nfs-clients yandex-browser-stable >/dev/null 2>&1 || true
  fi
  sed -i '/web.au-team.irpo/d' /etc/hosts
  sed -i '/docker.au-team.irpo/d' /etc/hosts
  echo "[ OK ] Rollback completed"
}
fail() { echo "[ ERROR ] $1"; rollback; exit 1; }

[[ $EUID -ne 0 ]] && fail "Root privileges required"

# --- Установка пакетов ---
apt-get update -qq >/dev/null 2>&1 || fail "Failed to update package lists"
apt-get install -y task-auth-ad-sssd admc nfs-clients yandex-browser-stable >/dev/null 2>&1 || fail "Failed to install packages"
PKG_INSTALLED=1

# --- SSH ---
useradd $SSH_USER 2>/dev/null || true
echo "$SSH_USER:$SSH_PASS" | chpasswd
usermod -aG wheel $SSH_USER
echo "$SSH_USER ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/$SSH_USER
chmod 0440 /etc/sudoers.d/$SSH_USER

cat > /etc/openssh/sshd_config <<'EOF' || fail "Failed to configure SSH"
Port 2026
MaxAuthTries 3
PermitRootLogin no
AllowUsers sshuser
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF
systemctl enable --now sshd.service >/dev/null 2>&1 || fail "Failed to start SSH"
SSH_CONFIGURED=1

# --- /etc/hosts ---
echo "172.16.1.10 web.au-team.irpo" >> /etc/hosts
echo "172.16.2.10 docker.au-team.irpo" >> /etc/hosts

# --- Ручной ввод в домен ---
echo ""
echo "!!! РУЧНОЙ ШАГ !!!"
echo "Введите HQ-CLI в домен через ЦУС:"
echo "  Центр управления системой → Аутентификация"
echo "  Домен: $DOMAIN"
echo "  Применить → перезагрузить"
echo ""
read -p "Нажмите Enter после перезагрузки и входа в домен..."

# --- Настройка sudo для группы hq ---
control group wheel add hq 2>/dev/null || true
cat > /etc/sudoers.d/hq <<'EOF'
Cmnd_Alias SHELLCMD = /bin/cat, /bin/grep, /usr/bin/id
%wheel ALL=(ALL:ALL) SHELLCMD
EOF
chmod 440 /etc/sudoers.d/hq

# --- NFS клиент ---
mkdir -p $NFS_MOUNT || fail "Failed to create mount point"
chmod 777 $NFS_MOUNT || fail "Failed to set permissions"
echo "${NFS_SERVER}:${NFS_SHARE} $NFS_MOUNT nfs defaults,_netdev 0 0" >> /etc/fstab || fail "Failed to update fstab"
mount $NFS_MOUNT >/dev/null 2>&1 || echo "[ WARNING ] Failed to mount NFS share, will retry later"

# --- NTP клиент ---
apt-get install -y chrony >/dev/null 2>&1 || fail "Failed to install chrony"
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.1.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd >/dev/null 2>&1

echo "[ OK ] Done"
