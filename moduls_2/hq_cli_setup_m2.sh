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
MaxAuthTries 2
PermitRootLogin no
AllowUsers sshuser
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF

systemctl enable --now sshd

# ============================================
# Настройка DNS через nmcli
# ============================================
apt-get install -y NetworkManager
nmcli con modify DHCP-CLI ipv4.method auto ipv4.ignore-auto-dns yes ipv4.dns 192.168.3.10 2>/dev/null
nmcli con down DHCP-CLI 2>/dev/null
nmcli con up DHCP-CLI 2>/dev/null

# ============================================
# /etc/hosts для доступа к сайтам
# ============================================
echo "172.16.1.1 web.au-team.irpo" >> /etc/hosts
echo "172.16.2.1 docker.au-team.irpo" >> /etc/hosts

# ============================================
# Установка пакетов
# ============================================
apt-get install -y task-auth-ad-sssd admc gpui sudo gpupdate yandex-browser-stable nfs-utils

echo ""
echo "!!! РУЧНОЙ ШАГ !!!"
echo "Введите HQ-CLI в домен через веб-интерфейс:"
echo "  Откройте Firefox: http://192.168.3.10:8081"
echo "  Configuration > Expert mode > Apply"
echo "  Web Interface"
echo "  Меняем порт 8080 на 8081 > Apply > Restart http server"
echo "  Вкладка Domain"
echo "  Выбираем Active Directory Domain Controller"
echo "  DNS Forwarders - 192.168.1.10"
echo "  Domain - au-team.irpo"
echo "  Password - P@ssw0rd"
echo "  Apply"
echo "  Ждём статус OK"
echo ""
echo "Затем в терминале выполните:"
echo "  nmcli con modify DHCP-CLI ipv4.method auto ipv4.ignore-auto-dns yes ipv4.dns 192.168.3.10"
echo "  nmcli con down DHCP-CLI && nmcli con up DHCP-CLI"
echo "  reboot"
echo ""
read -p "Нажмите Enter после перезагрузки и входа в домен..."

# ============================================
# Настройка NFS-клиента
# ============================================
mkdir -p /mnt/nfs
chmod 777 /mnt/nfs
echo "192.168.1.10:/raid/nfs /mnt/nfs nfs defaults 0 0" >> /etc/fstab
mount -a

# ============================================
# NTP-клиент
# ============================================
apt-get install -y chrony
cat > /etc/chrony.conf <<EOF
pool 172.16.1.1 iburst prefer
EOF
systemctl restart chronyd
systemctl enable --now chronyd
timedatectl set-timezone Asia/Yekaterinburg

echo "=== HQ-CLI готов ==="
echo "SSH: port 2026, user: sshuser, password: P@ssw0rd"
