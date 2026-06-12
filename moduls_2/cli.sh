# Создание директории
mkdir -p /home/AU-TEAM.IRPO/hquser1

# Копирование шаблонных файлов
cp -r /etc/skel/. /home/AU-TEAM.IRPO/hquser1/

# Установка прав
chown -R hquser1:domain\ users /home/AU-TEAM.IRPO/hquser1
chmod 700 /home/AU-TEAM.IRPO/hquser1
