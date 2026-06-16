#!/bin/bash
# Очистка и пересоздание
rm -rf /etc/pki/CA
mkdir -p /etc/pki/CA/{private,certs,newcerts,crl}
touch /etc/pki/CA/index.txt
echo 1000 > /etc/pki/CA/serial
chmod 777 /etc/pki/CA/private

# Создание CA
openssl req -x509 -new -nodes -keyout /etc/pki/CA/private/ca.key -out /etc/pki/CA/certs/ca.crt -days 3650 -sha256 -subj "/CN=AU-TEAM Root CA"

# Создание сертификатов
openssl genrsa -out /etc/pki/CA/private/web.au-team.irpo.key 2048
openssl req -new -key /etc/pki/CA/private/web.au-team.irpo.key -out /etc/pki/CA/web.au-team.irpo.csr -subj "/CN=web.au-team.irpo"
openssl ca -batch -config /etc/ssl/openssl-ca.cnf -in /etc/pki/CA/web.au-team.irpo.csr -out /etc/pki/CA/certs/web.au-team.irpo.crt -days 30
