#!/bin/bash
echo "=== Настройка SSH на HQ-CLI ==="


groupadd sshuser

# 2. Создание пользователя в /etc/passwd
echo "sshuser:x:1001:1001::/home/sshuser:/bin/bash" >> /etc/passwd

# 3. Создание пароля
passwd sshuser
# Введи: P@ssw0rd1!
# Подтверди: P@ssw0rd1!

# 4. Создание домашней директории
mkdir -p /home/sshuser
cp -r /etc/skel/. /home/sshuser/
chown -R sshuser:sshuser /home/sshuser

# 5. Добавление в группу wheel для sudo
echo "sshuser:x:10:sshuser" >> /etc/group

# 6. Настройка sudo
echo "sshuser ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/sshuser
chmod 440 /etc/sudoers.d/sshuser

# 7. Настройка SSH
if ! grep -q "AllowUsers sshuser" /etc/openssh/sshd_config; then
    echo "AllowUsers sshuser" >> /etc/openssh/sshd_config
    systemctl restart sshd
fi

# 8. Проверка
id sshuser
su - sshuser -c "whoami"
# ============================================
# 1. Установка SSH сервера
# ============================================
apt-get update && apt-get install -y openssh-server

# ============================================
# 2. Создание пользователя sshuser
# ============================================
useradd sshuser 2>/dev/null

# Установка пароля через passwd (неинтерактивно)
echo "P@ssw0rd!" | passwd --stdin sshuser 2>/dev/null || \
printf "sshuser:P@ssw0rd\n" | chpasswd 2>/dev/null || \
(echo "sshuser:P@ssw0rd" | chpasswd)

# Добавление в группу wheel
usermod -aG wheel sshuser 2>/dev/null

# ============================================
# 3. Настройка SSH (порт 2026)
# ============================================
cat > /etc/openssh/sshd_config <<'EOF'
Port 2026
MaxAuthTries 3
PermitRootLogin no
AllowUsers sshuser
PasswordAuthentication yes
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF

# ============================================
# 4. Разрешение в фаерволе (если включён)
# ============================================
if command -v iptables &>/dev/null; then
    iptables -A INPUT -p tcp --dport 2026 -j ACCEPT 2>/dev/null
    iptables-save > /etc/sysconfig/iptables 2>/dev/null
fi

# ============================================
# 5. Запуск SSH
# ============================================
systemctl enable --now sshd
systemctl restart sshd

# ============================================
# 6. Проверка
# ============================================
echo ""
echo "=== ПРОВЕРКА ==="
ss -tulnp | grep 2026
echo ""
systemctl status sshd --no-pager

echo ""
echo "=== SSH НАСТРОЕН ==="
echo "Порт: 2026"
echo "Пользователь: sshuser"
echo "Пароль: P@ssw0rd!"
