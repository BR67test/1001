#!/bin/bash
echo "=== HQ-CLI (Модуль 2) ==="

# /etc/hosts для доступа через ISP
echo "172.16.1.1 web.au-team.irpo" >> /etc/hosts
echo "172.16.2.1 docker.au-team.irpo" >> /etc/hosts

# SSSD для входа в домен
apt-get update && apt-get install -y task-auth-ad-sssd yandex-browser-stable

# NFS-клиент
mkdir -p /mnt/nfs
chmod 777 /mnt/nfs
echo "192.168.100.2:/raid/nfs /mnt/nfs nfs defaults,_netdev 0 0" >> /etc/fstab
mount -a

# Sudo для доменных пользователей (только разрешённые команды)
cat > /etc/sudoers.d/hq <<EOF
Cmnd_Alias SHELLCMD = /bin/cat, /bin/grep, /usr/bin/id
%WHEEL_USERS ALL=(ALL:ALL) SHELLCMD
EOF

# NTP-клиент
sed -i 's/^pool/#pool/' /etc/chrony.conf
echo "server 172.16.1.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

echo "=== HQ-CLI готов ==="
echo "!!! Ручные шаги: !!!"
echo "1. Введите HQ-CLI в домен через ЦУС (раздел Аутентификация)"
echo "2. Перезагрузите VM"
echo "3. Выполните: roledad 'hq' wheel"
