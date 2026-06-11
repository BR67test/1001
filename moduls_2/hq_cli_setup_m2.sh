#!/bin/bash
echo "=== HQ-CLI (Модуль 2) ==="

# ============================================
# 0. SSH настройка (порт 2026)
# ============================================

apt-get update && apt-get install -y openssh-server

useradd sshuser 2>/dev/null
echo "sshuser:P@ssw0rd" | chpasswd
usermod -aG wheel sshuser

cat > /etc/openssh/sshd_config <<EOF
Port 2026
MaxAuthTries 3
PermitRootLogin no
AllowUsers sshuser
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF

systemctl enable --now sshd

# ============================================
# 1. Обновление DNS (ждём DHCP)
# ============================================

echo "Ожидание обновления DNS от DHCP..."
sleep 5
systemctl restart network

echo "=== Проверка DNS ==="
cat /etc/resolv.conf
ping -c2 au-team.irpo

# ============================================
# 2. Установка SSSD
# ============================================

apt-get install -y task-auth-ad-sssd

echo ""
echo "!!! РУЧНОЙ ШАГ !!!"
echo "Введите HQ-CLI в домен через ЦУС:"
echo "  Центр управления системой → Аутентификация"
echo "  Домен: au-team.irpo"
echo "  Применить → перезагрузить"
echo ""
read -p "Нажмите Enter после перезагрузки и входа в домен..."

# ============================================
# 3. Настройка sudo для группы hq
# ============================================

echo "=== Настройка sudo ==="
roledad hq wheel

cat > /etc/sudoers.d/hq <<EOF
Cmnd_Alias SHELLCMD = /bin/cat, /bin/grep, /usr/bin/id
%wheel ALL=(ALL:ALL) SHELLCMD
EOF

chmod 440 /etc/sudoers.d/hq

# ============================================
# 4. NFS-клиент
# ============================================

apt-get install -y nfs-client
mkdir -p /mnt/nfs

echo "192.168.100.2:/raid/nfs /mnt/nfs nfs defaults,_netdev 0 0" >> /etc/fstab
mount -a

echo "=== Проверка NFS ==="
df -h | grep nfs

# ============================================
# 5. Проверка
# ============================================

echo "=== Проверка доменного пользователя ==="
su - hquser1 -c "sudo id && sudo cat /etc/hosts && sudo grep 127 /etc/hosts"

echo "=== HQ-CLI (Модуль 2) готов ==="
echo "SSH: port 2026, user: sshuser, password: P@ssw0rd"
