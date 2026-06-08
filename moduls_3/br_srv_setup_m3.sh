#!/bin/bash
echo "=== BR-SRV (Модуль 3) ==="

# ============================================
# 1. Импорт пользователей из users.csv
# ============================================

# Поиск и монтирование ISO
ISO_PATH=$(find / -name "*.iso" -path "*/Additional*" 2>/dev/null | head -1)
if [ -n "$ISO_PATH" ]; then
    mkdir -p /mnt/additional
    mount -o loop "$ISO_PATH" /mnt/additional
fi

# Проверка наличия CSV файла
CSV_PATH=""
if [ -f /mnt/additional/users.csv ]; then
    CSV_PATH="/mnt/additional/users.csv"
elif [ -f /root/users.csv ]; then
    CSV_PATH="/root/users.csv"
else
    echo "Ошибка: users.csv не найден"
    exit 1
fi

echo "Импорт пользователей из $CSV_PATH"

# Чтение CSV и создание пользователей
while IFS=',' read -r username password firstName lastName department; do
    # Пропуск заголовка
    if [[ "$username" == "username" ]]; then
        continue
    fi
    
    echo "Создание пользователя: $username"
    
    # Создание пользователя с атрибутами
    samba-tool user create "$username" "$password" \
        --given-name="$firstName" \
        --surname="$lastName" \
        --department="$department" \
        --must-change-at-next-login=no
    
    # Добавление в группу Domain Users
    samba-tool group addmembers "Domain Users" "$username"
    
done < "$CSV_PATH"

echo "=== Импорт пользователей завершён ==="
echo "Список пользователей:"
samba-tool user list | grep -v "Administrator\|krbtgt\|Guest"

echo "=== BR-SRV (Модуль 3) готов ==="
