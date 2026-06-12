#!/bin/bash
echo "=== HQ-CLI (Модуль 2) ==="

# ============================================
# SSH настройка (порт 2026)
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
# /etc/hosts для доступа к сайтам
# ============================================
echo "172.16.1.1 web.au-team.irpo" >> /etc/hosts
echo "172.16.2.1 docker.au-team.irpo" >> /etc/hosts

# ============================================
# Обновление DNS от DHCP
# ============================================
systemctl restart network
sleep 3

# ============================================
# Установка SSSD и ADMC
# ============================================
apt-get install -y task-auth-ad-sssd admc

echo ""
echo "!!! РУЧНОЙ ШАГ !!!"
echo "Введите HQ-CLI в домен через ЦУС:"
echo "  Центр управления системой → Аутентификация"
echo "  Домен: au-team.irpo"
echo "  Применить → перезагрузить"
echo ""
read -p "Нажмите Enter после перезагрузки и входа в домен..."

# ============================================
# Настройка sudo для группы hq (ALT Linux синтаксис)
# ============================================
# Добавление группы hq в wheel через control (аналог roledad)
control group wheel add hq 2>/dev/null

cat > /etc/sudoers.d/hq <<EOF
Cmnd_Alias SHELLCMD = /bin/cat, /bin/grep, /usr/bin/id
%wheel ALL=(ALL:ALL) SHELLCMD
EOF

chmod 440 /etc/sudoers.d/hq

# ============================================
# NFS-клиент
# ============================================
apt-get install -y nfs-clients
mkdir -p /mnt/nfs
chmod 777 /mnt/nfs

echo "192.168.1.10:/raid/nfs /mnt/nfs nfs defaults,_netdev 0 0" >> /etc/fstab
mount -a

# ============================================
# Яндекс Браузер
# ============================================
apt-get install -y yandex-browser-stable

# ============================================
# NTP-клиент
# ============================================
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.1.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

echo "=== HQ-CLI готов ==="
echo "SSH: port 2026, user: sshuser, password: P@ssw0rd"
